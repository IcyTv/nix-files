#!/usr/bin/env python3
"""IcyOS coordinator. Only execute_install crosses the destructive boundary."""
import argparse
import copy
import fcntl
import getpass
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile

from model import API, PRIMARY, SIGNING, REPOSITORY, check_storage_names, generate, swap_suggestion, swap_warnings, validate, write_json
from storage import check_target, device_key, flatten, inventory, stable_path

REMOTE = "https://github.com/IcyTv/nix-files.git"
HERE = Path(__file__).resolve().parent
# Persistent, private (0600) log in the workspace; set by main() once the workspace is known.
LOG = None
# Consecutive dismissed prompts tolerated before assuming the terminal is gone.
CANCEL_LIMIT = 5


def log_line(text):
    """Append to the workspace log. Callers pass only text that is safe to print (see describe())."""
    if LOG is None:
        return
    try:
        fd = os.open(LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "a") as stream:
            stream.write(text if text.endswith("\n") else text + "\n")
    except OSError:
        pass  # logging must never stop the installer


def run(args, *, cwd=None, input=None, capture=True, env=None, private=False, show_errors=False, pass_fds=(),
        stream_errors=False):
    """Never include argument values in exceptions (some are sensitive paths).

    stream_errors: capture stdout only and let stderr (progress, diagnostics) reach the terminal.
    """
    if private:
        # Bypass stdout/stderr redirection and tee: recovery output is terminal-only.
        fd = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
        try:
            result = subprocess.run(
                [str(x) for x in args],
                cwd=cwd,
                text=True,
                stdin=fd,
                stdout=fd,
                stderr=fd,
                env=env,
                pass_fds=pass_fds,
            )
        finally:
            os.close(fd)
    else:
        result = subprocess.run([str(x) for x in args], cwd=cwd, input=input, text=True,
                                stdout=subprocess.PIPE if capture else None,
                                stderr=subprocess.PIPE if capture and not stream_errors else None,
                                env=env, pass_fds=pass_fds)
    if result.returncode:
        if show_errors and result.stderr:
            print(result.stderr, file=sys.stderr, end="")
            log_line(result.stderr)
        # Full diagnostics of Nix builds go directly to terminal, not to a persistent log.
        raise RuntimeError(f"{Path(args[0]).name} failed (exit {result.returncode})")
    return result.stdout if capture else ""


class BackToWizard(Exception):
    """Raised by a failed stage when the operator wants to change their answers."""


class Cancelled(KeyboardInterrupt):
    """A prompt was dismissed (Esc in gum, EOF in bash) rather than interrupted with Ctrl+C.

    Unhandled, it stops the installer like Ctrl+C; prompts where stopping is unsafe
    or unhelpful catch it and ask again.
    """


def run_interactive(args, *, cwd=None, env=None):
    fd = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
    try:
        result = subprocess.run(
            [str(arg) for arg in args],
            cwd=cwd,
            env=env,
            stdin=fd,
            stdout=subprocess.PIPE,
            stderr=fd,
            text=True,
        )
        # gum exits 130 on Ctrl+C and 1 on Esc; bash killed by SIGINT reports -SIGINT.
        if result.returncode in (130, -signal.SIGINT):
            raise KeyboardInterrupt
        if result.returncode:
            raise Cancelled
        return result.stdout.strip()
    finally:
        os.close(fd)


def list_height(count):
    try:
        fd = os.open("/dev/tty", os.O_RDONLY | os.O_NOCTTY)
        try:
            rows = os.get_terminal_size(fd).lines
        finally:
            os.close(fd)
    except OSError:
        rows = 24
    return max(5, min(count, rows - 6))


def choose(title, values, current=None):
    """`current` keeps the cursor (and page) on that entry. gum splits --selected on commas."""
    args = ["gum", "choose", "--header", title, "--height", str(list_height(len(values)))]
    if current is not None and current in values and "," not in current:
        args += ["--selected", current]
    return run_interactive([*args, "--", *values]).strip()


def ask(title, default=""):
    return run_interactive([
        "gum", "input", "--header", title,
        "--value", str(default)
    ]).strip()


def ask_path(title):
    # bash's readline gives Tab completion and history; the prompt and echo go to the tty.
    return run_interactive(["bash", "-c", 'read -e -r -p "$1: " value && printf %s "$value"', "_", title]).strip()


def ask_file(title, check=None):
    """Prompt until a readable file (accepted by `check`) is given; never exits on a typo."""
    cancelled = 0

    def dismissed():
        nonlocal cancelled
        cancelled += 1
        if cancelled >= CANCEL_LIMIT:
            raise RuntimeError("Prompt keeps failing; terminal may be gone.")

    while True:
        try:
            text = ask_path(title + " (Tab completes, empty to cancel)")
            cancelled = 0
        except Cancelled:
            dismissed()
            text = ""  # Ctrl+D or similar: ask whether to cancel instead of stopping outright
        if not text:
            try:
                cancel = confirm("Cancel the installer?")
                cancelled = 0
            except Cancelled:
                dismissed()
                cancel = False  # Esc on the question means "No"
            if cancel:
                raise KeyboardInterrupt
            continue
        path = Path(text).expanduser()
        if not path.is_file():
            notice("Not a readable file. Try again.")
            continue
        try:
            if check is None or check(path):
                return path
        except (OSError, ValueError, RuntimeError) as exc:
            notice(f"Rejected: {describe(exc)}")
        else:
            notice("Rejected. Try again.")


def confirm(title, default=False):
    return choose(title, ["Yes", "No"] if default else ["No", "Yes"]) == "Yes"


def notice(text):
    print(text, flush=True)
    log_line(str(text))


def secret_twice(title):
    while True:
        a = getpass.getpass(f"{title}: ")
        b = getpass.getpass("Confirm: ")
        if a and a == b and "\n" not in a and "\0" not in a:
            return a
        notice("Empty or mismatched secret. Try again.")


def nix_eval(repo, attr):
    # Git-aware references exclude .git, including git-crypt's runtime key cache.
    # Never use path: on an unlocked Git checkout.
    # stderr streams to the terminal so long evaluations show progress and errors.
    return json.loads(run(["nix", "eval", "--no-write-lock-file", "--json", f"{repo}#{attr}"], stream_errors=True))


def engine_digest(directory):
    digest = hashlib.sha256()
    for path in sorted(Path(directory).rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            digest.update(str(path.relative_to(directory)).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def stage_files(repo, files):
    names = [str(Path(p).relative_to(repo)) for p in files]
    for offset in range(0, len(names), 100):
        run(["git", "add", "--", *names[offset:offset + 100]], cwd=repo)


SYSTEM_PRESET = ["ananicy", "bluetooth", "console-font", "docker", "geoclue", "greetd", "keyd", "keymap",
                 "limine", "niri", "plymouth", "printing", "rebuild", "stylix", "subniri", "sudo-rs", "tools", "zsh"]
HOME_DISABLED = ["ai", "anyrun", "games", "unifiedremote"]
CRYPT_MAGIC = b"\0GITCRYPT\0"
BOOKMARKS = ("bookmarks-default.json", "bookmarks-yes.json")


def snapshot_ignore(directory, names):
    """Skip tooling/keys, and bookmark files unless they are git-crypt ciphertext."""
    skipped = {n for n in names if n in ("__pycache__", ".keys")}
    for name in names:
        if name in BOOKMARKS:
            with open(Path(directory) / name, "rb") as handle:
                if handle.read(len(CRYPT_MAGIC)) != CRYPT_MAGIC:
                    skipped.add(name)
    return skipped


def writable_snapshot(repo):
    # copytree preserves Nix store's read-only directory modes. Modify only the
    # session-owned copy, never symlink referents or the immutable source.
    for path in [repo, *repo.rglob("*")]:
        if path.is_symlink() or ".git" in path.relative_to(repo).parts:
            continue
        path.chmod(path.stat().st_mode | (0o700 if path.is_dir() else 0o600))


def prepare(work, source, update=True):
    env = os.environ | {"GIT_LFS_SKIP_SMUDGE": "1", "GIT_TERMINAL_PROMPT": "0"}
    repo = work / "repository"
    history = False
    if update:
        try:
            run(["git", "clone", "--no-checkout", REMOTE, repo], env=env, show_errors=True)
            revision = run(["git", "rev-parse", "HEAD"], cwd=repo, show_errors=True).strip()
            run(["git", "checkout", "--detach", revision], cwd=repo, env=env, show_errors=True)
            history = True
        except RuntimeError as exc:
            raise RuntimeError(
                "Failed to prepare upstream Git repository; refusing to substitute a synthetic snapshot. "
                "Use --no-update for an explicit offline snapshot."
            ) from exc
    if not (repo / "flake.nix").exists():
        if not source.is_dir():
            raise ValueError("No usable installer snapshot")
        # A retained workspace from an older run may have .git but no commit; treat it as a snapshot.
        # The installer runs as root but --source is often owned by another user;
        # trust only this explicitly chosen source for read-only clone/inspection.
        trust = ["-c", f"safe.directory={source}", "-c", f"safe.directory={source / '.git'}"]
        source_has_head = False
        if (source / ".git").exists():
            probe = subprocess.run(["git", *trust, "rev-parse", "--verify", "HEAD"], cwd=source,
                                   capture_output=True, text=True)
            source_has_head = probe.returncode == 0
            if not source_has_head:
                notice(f"Source has no commit ({probe.stderr.strip() or 'no HEAD'}); treating it as a file snapshot.")
        if source_has_head:
            # Restart from an explicitly chosen checkout without losing history
            # or copying .git/git-crypt's private symmetric-key cache.
            run(["git", *trust, "clone", "--no-hardlinks", "--no-checkout", source, repo], env=env, show_errors=True)
            revision = run(["git", "rev-parse", "HEAD"], cwd=repo, show_errors=True).strip()
            run(["git", "checkout", "--detach", revision], cwd=repo, env=env, show_errors=True)
            history = True
        else:
            repo.mkdir()
            run(["git", "init", repo], show_errors=True)
        allowed = {"flake.nix", "flake.lock", "rebuild.sh", "installer", "modules", "scripts", "secrets", "hosts", ".gitattributes", ".gitignore"}
        ignore_private = snapshot_ignore
        for entry in source.iterdir():
            if entry.name not in allowed:
                continue
            if entry.is_dir():
                if (repo / entry.name).exists() and entry.name != "secrets":
                    # Only an explicitly named directory in this run's new clone.
                    shutil.rmtree(repo / entry.name)
                # Keep encrypted bookmark blobs from Git, never source plaintext.
                shutil.copytree(entry, repo / entry.name, dirs_exist_ok=True, ignore=ignore_private)
            else:
                shutil.copyfile(entry, repo / entry.name)
        (repo / "wallpapers").mkdir(exist_ok=True)
        writable_snapshot(repo)
        run(["git", "lfs", "install", "--local"], cwd=repo, show_errors=True)
        # Scope initial snapshot staging to supplied configuration roots; never
        # enumerate incidental ignored tooling directories from a local clone.
        stage_files(repo, [repo / name for name in sorted(allowed) if (repo / name).exists()])
        # git-crypt unlock needs a valid HEAD and a clean tree. No git-crypt filter
        # is configured yet, so staged ciphertext blobs are stored verbatim.
        staged = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo).returncode != 0
        if not history or staged:
            run(["git", "-c", "user.name=Installer snapshot", "-c", "user.email=installer@localhost",
                 "-c", "commit.gpgsign=false", "commit", "--quiet", "--no-verify", "--allow-empty",
                 "-m", "Offline installer snapshot" if not history else "Installer resume snapshot"],
                cwd=repo, env=env, show_errors=True)
            if history:
                # The resume snapshot commit is the source actually installed, not the cloned HEAD.
                revision = run(["git", "rev-parse", "HEAD"], cwd=repo, show_errors=True).strip()
        if not history or run(["git", "status", "--porcelain"], cwd=repo).strip():
            revision = snapshot_digest(repo)
    verify_repo(repo, revision, history)
    # Snapshot repositories need an origin for later user pushes, without publishing anything now.
    if not run(["git", "remote"], cwd=repo).strip():
        run(["git", "remote", "add", "origin", REMOTE], cwd=repo, show_errors=True)
    if len(revision) == 64:
        revision = snapshot_digest(repo)
    # Last step: only a fully prepared workspace is offered by --resume.
    (work / ".prepared").touch()
    return repo, revision, history


def verify_repo(repo, revision, history):
    """Compatibility and content checks; repeated on --resume because the workspace may have changed."""
    try:
        api = nix_eval(repo, "installerApi")
    except RuntimeError as exc:
        raise ValueError("Selected upstream revision lacks installerApi. Publish the installer changes first, or explicitly use --source PATH --no-update.") from exc
    if api != API:
        raise ValueError("Selected repository is incompatible with this installer API; use a matching ISO/revision")
    if engine_digest(repo / "installer") != engine_digest(HERE):
        notice(f"Selected revision {revision} contains a different installer. Recommended restart command:")
        notice(f"  nix run '{repo}#installer' -- --source '{repo}' --no-update")
        if not confirm("Continue with this installer version instead? Compatibility API matches."):
            raise KeyboardInterrupt
    run(["git", "lfs", "install", "--local"], cwd=repo, show_errors=True)
    if history:
        run(["git", "remote", "set-url", "origin", REMOTE], cwd=repo, show_errors=True)
        run(["git", "lfs", "pull"], cwd=repo, capture=False)
        run(["git", "lfs", "fsck"], cwd=repo, capture=False)


def snapshot_digest(repo):
    """A snapshot without Git history is identified by its actual complete contents."""
    digest = hashlib.sha256()
    for path in sorted(repo.rglob("*")):
        if path.is_file() and not any(p in (".git", "__pycache__") for p in path.relative_to(repo).parts):
            digest.update(str(path.relative_to(repo)).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def detect_hardware():
    cpu = Path("/proc/cpuinfo").read_text()
    pci = run(["lspci", "-nn"])
    gpu_lines = "\n".join(line for line in pci.splitlines() if any(x in line.lower() for x in ("vga", "3d controller", "display controller")))
    vendor = "nvidia" if "NVIDIA" in gpu_lines else "amd" if "AMD" in gpu_lines or "ATI" in gpu_lines else "intel" if "Intel" in gpu_lines else "other"
    virt = subprocess.run(["systemd-detect-virt"], capture_output=True, text=True).stdout.strip()
    return {"cpu": "amd" if "AuthenticAMD" in cpu else "intel" if "GenuineIntel" in cpu else "other",
            "gpu": vendor, "vm": virt if virt in ("kvm", "oracle", "none") else "other",
            "laptop": bool(list(Path("/sys/class/power_supply").glob("BAT*")))}


def ram_gib():
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemTotal:"):
            return int(line.split()[1]) / 1024 ** 2
    raise ValueError("Cannot determine available RAM")


def scan_hardware(work):
    # --no-filesystems suppresses declarations, but the upstream generator still
    # probes mounted Btrfs filesystems first (requiring root). Scan PCI/CPU/sysfs
    # against an empty target prefix instead of probing the live root filesystem.
    probe = work / "hardware-probe"
    probe.mkdir(exist_ok=True)
    return run(["nixos-generate-config", "--root", probe, "--no-filesystems", "--show-hardware-config"])


def edit_options(schema, scope, answers):
    available = {".".join(o["path"]): o for o in schema if o["scope"] == scope and o["writable"]}
    def effective(option):
        if scope == "home" and answers.get("my.hm.default.enable", False):
            return option.get("presetDefault", option["default"])
        return option["default"]
    last = None
    while True:
        # Labels never contain commas (gum --selected splits on them), so the
        # cursor can return to the entry just edited instead of jumping to the top.
        labels = {f"{name} = {json.dumps(answers.get(name, effective(o))).replace(',', ';')}": name
                  for name, o in sorted(available.items())}
        entries = ["Done", *labels]
        current = next((label for label, name in labels.items() if name == last), "Done")
        selection = choose(f"{scope}: all user-facing my.* options", entries, current)
        if selection == "Done":
            return
        name = labels[selection]
        last = name
        option = available[name]
        if not option["supported"]:
            notice(f"Unsupported type {option['type']}: {option['description']}. Edit host configuration manually later.")
            continue
        current = answers.get(name, effective(option))
        if option["type"] == "bool":
            answers[name] = confirm(f"{name}: {option['description']}", bool(current))
        elif option["type"] == "str":
            answers[name] = ask(f"{name}: {option['description']}", current or "")
        else:
            text = ask(f"{name}: JSON list of strings", json.dumps(current or []))
            try:
                value = json.loads(text)
                if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
                    raise ValueError
                answers[name] = value
            except (ValueError, json.JSONDecodeError):
                notice("Expected a JSON list of strings; answer unchanged.")


def host_taken(repo, name):
    """True when the host exists in the selected revision's HEAD (or that cannot be proven)."""
    head = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=repo, capture_output=True)
    if head.returncode:
        return (repo / "hosts" / name).exists()
    return subprocess.run(["git", "cat-file", "-e", f"HEAD:hosts/{name}"], cwd=repo,
                          capture_output=True).returncode == 0


def reset_generated(repo, name):
    """Remove only a host this installer generated earlier, so a retry can regenerate it."""
    host = repo / "hosts" / name
    if not host.exists():
        return
    if host_taken(repo, name):
        raise ValueError("Host already exists")
    subprocess.run(["git", "rm", "-r", "-f", "--cached", "--quiet", "--ignore-unmatch", "--", f"hosts/{name}"],
                   cwd=repo, capture_output=True)
    shutil.rmtree(host)


def reset_all_generated(repo):
    """Remove every host generated by an earlier attempt, including one for a since-changed hostname.

    model.generate() always writes install.json first, so it marks installer-generated hosts;
    anything else not in HEAD (for example a hand-copied host) is left alone.
    """
    hosts = repo / "hosts"
    if not hosts.is_dir():
        return
    for host in sorted(hosts.iterdir()):
        if (host.is_dir() and not host.is_symlink() and (host / "install.json").is_file()
                and not host_taken(repo, host.name)):
            reset_generated(repo, host.name)


def default_answers(repo, revision, schema):
    notice("Evaluating defaults and detecting hardware...")
    m = {"api": API, "revision": revision, "hostname": "", "username": "michael", "disk": "",
         "encrypted": True, "fido2": False, "personalSecrets": False, "signing": True,
         "swapGiB": 0, "hibernate": False, "timezone": "Europe/Berlin", "locale": "en_US.UTF-8",
         "gitName": "Michael Finger", "gitEmail": "michael.finger@icytv.de",
         "stateVersion": nix_eval(repo, "installerStateVersion"),
         "system": {}, "home": {"my.hm.default.enable": True}, "hardware": detect_hardware()}
    # Only options present in this revision's schema are set; unknown names are never invented.
    names = {".".join(o["path"]) for o in schema if o["scope"] == "system"}
    m["system"] = {f"my.nixos.{name}.enable": True for name in SYSTEM_PRESET if f"my.nixos.{name}.enable" in names}
    home_names = {".".join(o["path"]) for o in schema if o["scope"] == "home"}
    m["home"].update({f"my.hm.{name}.enable": False for name in HOME_DISABLED if f"my.hm.{name}.enable" in home_names})
    return m


def wizard(repo, revision, schema, saved=None):
    # "Edit answers" after a failed stage keeps every earlier choice.
    m = copy.deepcopy(saved) if saved is not None else default_answers(repo, revision, schema)
    step = 0
    while True:
        notice(f"IcyOS Installer — step {step + 1}/6 — source {revision}")
        if step == 0:
            m["hostname"] = ask("New hostname (existing hosts cannot be overwritten)", m["hostname"])
            m["username"] = ask("Username", m["username"])
            m["timezone"] = ask("Timezone", m["timezone"])
            m["locale"] = ask("Locale", m["locale"])
            m["gitName"] = ask("Git name", m["gitName"])
            m["gitEmail"] = ask("Git email", m["gitEmail"])
            m["signing"] = confirm("Configure and verify your existing YubiKey OpenPGP signing subkey?", m["signing"])
        elif step == 1:
            data, protected, held = inventory(run)
            nodes, _ = flatten(data)
            options = {}
            for key, node in nodes.items():
                try:
                    check_target(data, key, protected, held)
                except ValueError:
                    continue
                path = stable_path(node)
                label = f"{path} | {node.get('model')} | serial={node.get('serial')} | {node['size'] / 1024**3:.1f} GiB"
                options[label] = path
            if not options:
                raise ValueError("No safe whole-disk installation target found")
            previous = next((label for label, path in options.items() if path == m["disk"]), None)
            m["disk"] = options[choose("Select disk (not formatted yet)", list(options), previous)]
            m["encrypted"] = confirm("Enable LUKS2 encryption?", m["encrypted"])
            m["fido2"] = m["encrypted"] and confirm("Enroll a YubiKey for PIN + touch disk unlocking?", m["fido2"])
            m["hibernate"] = confirm("Enable hibernation?", m["hibernate"])
            suggested = swap_suggestion(ram_gib(), m["hibernate"])
            while True:
                try:
                    size = int(ask(f"Btrfs swapfile GiB (guideline: {suggested}; 0 disables disk swap)", suggested))
                    if size < 0:
                        raise ValueError
                    m["swapGiB"] = size
                    break
                except ValueError:
                    notice("Enter a nonnegative integer.")
            for warning in swap_warnings(m["swapGiB"], ram_gib(), m["hibernate"]):
                notice("WARNING: " + warning)
        elif step == 2:
            for field, options in (("cpu", ["amd", "intel", "other"]), ("gpu", ["amd", "intel", "nvidia", "other"]),
                                   ("vm", ["none", "kvm", "oracle", "other"])):
                detected = m["hardware"][field]
                m["hardware"][field] = choose(f"{field} (detected: {detected}; NVIDIA default assumes a modern supported GPU)",
                                               [detected] + [x for x in options if x != detected])
            m["hardware"]["laptop"] = confirm("Laptop power-management defaults?", m["hardware"]["laptop"])
            desktop = choose("Desktop", ["Niri", "Hyprland", "Both", "None"])
            for scope, prefix in (("system", "my.nixos"), ("home", "my.hm")):
                m[scope][f"{prefix}.niri.enable"] = desktop in ("Niri", "Both")
                m[scope][f"{prefix}.hyprland.enable"] = desktop in ("Hyprland", "Both")
            m["system"]["my.nixos.greetd.enable"] = desktop != "None"
            m["personalSecrets"] = confirm("Personal setup? Requires encryption, git-crypt and age keys.", m["personalSecrets"])
            if m["personalSecrets"] and not m["encrypted"]:
                notice("Personal setup requires encryption. Enable it in Storage or use reduced setup.")
                step = 1
                continue
        elif step in (3, 4):
            edit_options(schema, "system" if step == 3 else "home", m["system" if step == 3 else "home"])
        else:
            validate(m, schema)
            if host_taken(repo, m["hostname"]):
                notice("Host already exists; choose a new hostname.")
                step = 0
                continue
            notice(json.dumps(m, indent=2))
        action = choose("Review navigation (nothing has been formatted)",
                        (["Continue", "Back", "Cancel"] if step else ["Continue", "Cancel"]))
        if action == "Cancel":
            raise KeyboardInterrupt
        step += -1 if action == "Back" else 1
        if step == 6:
            return m


def private_file(directory, name, contents):
    path = directory / name
    path.unlink(missing_ok=True)  # a retried stage recreates its own session file
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write(contents)
    return path


def relock(repo):
    """Return the secrets to committed ciphertext so `git-crypt unlock` sees a clean tree.

    Removing the filter sections first means git copies index blobs verbatim, which also
    works after the session key cache was deleted.
    """
    for section in ("filter.git-crypt", "diff.git-crypt"):
        subprocess.run(["git", "config", "--remove-section", section], cwd=repo, capture_output=True)
    # A snapshot without bookmarks has nothing to restore; never fail on it.
    names = [f"secrets/{name}" for name in BOOKMARKS
             if subprocess.run(["git", "ls-files", "--error-unmatch", "--", f"secrets/{name}"],
                               cwd=repo, capture_output=True).returncode == 0]
    if names:
        run(["git", "checkout", "--", *names], cwd=repo, show_errors=True)
    for name in names:
        with open(repo / name, "rb") as handle:
            if handle.read(len(CRYPT_MAGIC)) != CRYPT_MAGIC:
                raise ValueError("Bookmark ciphertext could not be restored; refusing to continue")


def prepare_personal(repo, private):
    def unlock(path):
        # Suppress command diagnostics so key paths never enter persistent output.
        with path.open("rb") as key:
            run(["git-crypt", "unlock", f"/proc/self/fd/{key.fileno()}"], cwd=repo, pass_fds=(key.fileno(),))
        return True

    def decrypts_all(path):
        for name in ("id_ed25519.age", "github-token.age", "pay-respects-api-key.age"):
            with open(os.devnull, "w") as sink:
                result = subprocess.run(["age", "--decrypt", "--identity", path, repo / "secrets" / name],
                                        stdout=sink, stderr=sink)
            if result.returncode:
                raise ValueError("Age identity cannot decrypt all personal credentials")
        return True

    relock(repo)  # a retry or resume starts from ciphertext; the key cache is never retained
    ask_file("Explicit git-crypt key file path (not retained)", unlock)
    for name in ("bookmarks-default.json", "bookmarks-yes.json"):
        json.loads((repo / "secrets" / name).read_text())
        encrypted_bookmark(repo, name)
    age_path = ask_file("Explicit age identity file path", decrypts_all)
    identity = private / "age-identity"
    identity.unlink(missing_ok=True)
    with age_path.open("rb") as src, identity.open("xb") as dst:
        os.chmod(identity, 0o600)
        shutil.copyfileobj(src, dst)
    if not confirm("Copy the age identity into your installed user's private .keys directory?"):
        raise ValueError("Personal setup needs the age identity after reboot. Rerun with personal setup disabled.")
    return identity


def fetch_public(private):
    certificate = private / "signing-public.asc"
    run(["curl", "--fail", "--silent", "--show-error", "--max-time", "60", "--proto", "=https", "--tlsv1.2", "--output", certificate,
         f"https://keys.openpgp.org/vks/v1/by-fingerprint/{PRIMARY}"], show_errors=True)
    gnupg = private / "gnupg"
    subprocess.run(["gpgconf", "--homedir", gnupg, "--kill", "all"], capture_output=True)
    gnupg.mkdir(mode=0o700, exist_ok=True)
    try:
        tty = os.ttyname(sys.stdin.fileno())
    except OSError:
        tty = "/dev/tty"
    env = os.environ | {"GNUPGHOME": str(gnupg), "GPG_TTY": tty}
    listing = run(["gpg", "--batch", "--with-colons", "--import-options", "show-only", "--import", certificate], env=env, show_errors=True)
    fingerprints = [line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:")]
    if not fingerprints or fingerprints[0] != PRIMARY or SIGNING not in fingerprints:
        raise ValueError("Keyserver certificate fingerprint/subkey mismatch")
    if not any(line.startswith("uid:") for line in listing.splitlines()):
        raise ValueError("Published public key has no verified identity. Complete the keys.openpgp.org verification email before signing setup.")
    run(["gpg", "--batch", "--import", certificate], env=env, show_errors=True)
    try:
        run(["gpg", "--card-status"], env=env, show_errors=True)
    except RuntimeError as exc:
        raise ValueError("No OpenPGP smartcard detected (gpg --card-status failed). Insert the YubiKey and retry.") from exc
    keys = run(["gpg", "--batch", "--with-colons", "--with-keygrip", "--list-secret-keys", PRIMARY], env=env, show_errors=True)
    card_signers = card_signing_fingerprints(keys)
    if SIGNING not in card_signers:
        found = ", ".join(card_signers) or "none"
        raise ValueError("Required signing subkey is not available as a smartcard-backed key. "
                         f"Expected {SIGNING}; card-backed signing subkeys found: {found}")
    challenge = private_file(private, "signing-check.txt", "IcyOS installer signing verification\n")
    run(["gpg", "--local-user", SIGNING + "!", "--detach-sign", challenge], env=env, capture=False, private=True)
    run(["gpg", "--verify", str(challenge) + ".sig", challenge], env=env, show_errors=True)
    return certificate


def card_signing_fingerprints(listing):
    """Public fingerprints of smartcard-backed subkeys, from gpg --with-colons output."""
    rows = listing.splitlines()
    found = []
    for i, line in enumerate(rows):
        fields = line.split(":")
        # Field 15 holds the card serial number for card-backed secret keys.
        if fields[0] != "ssb" or len(fields) <= 14 or fields[14] in ("", "+", "#"):
            continue
        fingerprint = next((row.split(":")[9] for row in rows[i + 1:i + 3] if row.startswith("fpr:")), None)
        if fingerprint:
            found.append(fingerprint)
    return found


def select_fido():
    devices = run(["fido2-token", "-L"]).splitlines()
    supported = {}
    for line in devices:
        path = line.split(":", 1)[0]
        if not path.startswith("/dev/hidraw"):
            continue
        details = run(["fido2-token", "-I", path])
        if "hmac-secret" in details:
            supported[line] = path
    if not supported:
        raise ValueError("No compatible FIDO2 hmac-secret token. Connect it and ensure FIDO2/PIN are configured; no token settings were changed.")
    return supported[choose("Select one FIDO2 token (separate from OpenPGP)", list(supported))]


def prepare_fido(m):
    while True:
        try:
            return select_fido()
        except (ValueError, RuntimeError) as exc:
            notice(str(exc))
            action = choose("Token preflight failed; disk has NOT been formatted.",
                            ["Retry", "Abort", "Continue passphrase + recovery only"])
            if action == "Abort":
                raise ValueError("Cancelled before formatting") from exc
            if action.startswith("Continue"):
                m["fido2"] = False
                return None


TARGET = Path("/mnt")
# Chroot store on the formatted target: the logical store stays /nix/store, the
# physical one is /mnt/nix/store (on the target's /nix subvolume).
TARGET_STORE = str(TARGET)
TARGET_BUILD_DIR = TARGET / "nix" / "var" / "nix" / "builds"
# Same substituter nixos-install uses: reuse paths already in the live store.
LIVE_SUBSTITUTER = "auto?trusted=1"
MIN_SYSTEM_GIB = 64


def build(repo, hostname, attribute, work, store=None, link_name=None):
    """Build `config.<attribute>`; the out-link in the workspace keeps it as a GC root.

    With store=TARGET_STORE everything downloaded or built lands on the target disk,
    never in the live ISO's RAM-backed store, and build directories live there too.
    """
    link = work / (link_name or attribute.rsplit(".", 1)[-1])
    notice(f"Building {attribute} for {hostname}{' on the target disk' if store else ''} (this can take a long time)...")
    run([*build_command(repo, hostname, attribute, link, store)], capture=False,
        env=target_build_env() if store else None)
    # A chroot-store out-link points at the logical /nix/store path, which need not exist live.
    return Path(os.readlink(link))


def build_command(repo, hostname, attribute, link, store=None):
    target = ["--store", store, "--extra-substituters", LIVE_SUBSTITUTER,
              "--option", "build-dir", str(TARGET_BUILD_DIR)] if store else []
    return ["nix", "build", "-L", "--no-write-lock-file", *target, "--out-link", link,
            f"{repo}#nixosConfigurations.{hostname}.config.{attribute}"]


def target_build_env():
    # Builders run in build-dir; TMPDIR covers nix's own temporary files (as nixos-install does).
    TARGET_BUILD_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(TARGET_BUILD_DIR, 0o755)  # nix requires o+x and forbids world-writable
    tmp = TARGET / "nix" / "var" / "nix" / "installer-tmp"
    tmp.mkdir(mode=0o700, parents=True, exist_ok=True)
    return os.environ | {"TMPDIR": str(tmp)}


def recovery_commands(repo, hostname, work):
    """Manual continuation after formatting; contains no secrets."""
    link = work / "toplevel"
    command = " ".join(f"'{part}'" if any(c in str(part) for c in "?#") else str(part)
                       for part in build_command(repo, hostname, "system.build.toplevel", link, TARGET_STORE))
    return [
        f"  TMPDIR={TARGET}/nix/var/nix/installer-tmp {command}",
        f"  nixos-install --root {TARGET} --system \"$(readlink {link})\" --no-root-passwd",
        f"  nixos-enter --root {TARGET} -c 'passwd <username>'",
    ]


def check_capacity(m, disk_bytes, source_bytes):
    # The system closure is built after formatting, so reserve a fixed minimum for it
    # plus swap, EFI and the source. A layout that cannot fit must not erase a disk.
    needed = (MIN_SYSTEM_GIB + m["swapGiB"] + 2) * 1024 ** 3 + source_bytes
    if needed > disk_bytes:
        raise ValueError(f"Target layout cannot fit: need approximately {needed / 1024**3:.1f} GiB including system, source, swap and EFI")


def copy_install_repository(repo, target):
    def omit_crypt_keys(directory, names):
        # Unlock retains a symmetric key under .git/git-crypt. Keep filters, but
        # require explicit external-key unlock again for later encrypted edits.
        return ["git-crypt"] if Path(directory) == repo / ".git" and "git-crypt" in names else []
    shutil.copytree(repo, target, symlinks=True, ignore=omit_crypt_keys)


def prepare_target_parent(target):
    target.parent.mkdir(parents=True, exist_ok=True)
    # Our private live-workspace umask must not make /etc or /etc/nixos
    # untraversable. Access restriction belongs on nix-files itself, below.
    os.chmod(target.parent.parent, 0o755)
    os.chmod(target.parent, 0o755)


def encrypted_bookmark(repo, name):
    try:
        content = subprocess.check_output(["git", "show", ":secrets/" + name], cwd=repo, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError as exc:
        raise ValueError(f"Encrypted {name} is missing from this snapshot. Build the ISO from a locked checkout (ciphertext), or use online mode.") from exc
    if not content.startswith(CRYPT_MAGIC):
        raise ValueError("Expected encrypted Git bookmark blob; refusing to persist plaintext")
    return content


def lock_installed_bookmarks(target):
    # The installed checkout must remain usable without retaining a symmetric
    # key. Restore ciphertext from the index and remove local unlock filters.
    for name in ("bookmarks-default.json", "bookmarks-yes.json"):
        (target / "secrets" / name).write_bytes(encrypted_bookmark(target, name))
    for section in ("filter.git-crypt", "diff.git-crypt"):
        subprocess.run(["git", "config", "--remove-section", section], cwd=target, capture_output=True)


def enroll(m, device, token, cryptenroll="systemd-cryptenroll"):
    # All enrollment output is terminal-only, especially the recovery key/QR code.
    run([cryptenroll, "--unlock-key-file=/run/icy-installer/luks-password", "--recovery-key", device], capture=False, private=True)
    cancelled = 0

    def dismissed():
        # Esc re-prompts, but a dead terminal must not spin forever.
        nonlocal cancelled
        cancelled += 1
        if cancelled >= CANCEL_LIMIT:
            raise RuntimeError("Prompt keeps failing; terminal may be gone. Stopped after formatting. "
                               "Use retained configuration and recovery instructions.")

    def cancelled_reset():
        nonlocal cancelled
        cancelled = 0

    while True:
        try:
            saved = confirm("Have you saved the recovery key separately from this encrypted disk?")
            cancelled_reset()
        except Cancelled:
            dismissed()
            saved = False  # Esc must not skip past the recovery key
        if saved:
            break
        notice("Save the recovery key shown above before continuing. It is deliberately not in the log.")

    def after_failure():
        """Ask until the operator picks a usable token or gives up FIDO2; None means continue without it."""
        while True:
            try:
                action = choose("Enrollment failed; disk is already formatted.",
                                ["Retry", "Abort", "Continue passphrase + recovery only"])
                cancelled_reset()
            except Cancelled:
                dismissed()
                continue  # an explicit choice is required after formatting
            if action == "Abort":
                raise RuntimeError("Stopped after formatting. Use retained configuration and recovery instructions.")
            if action.startswith("Continue"):
                return None
            try:
                return select_fido()
            except Cancelled:
                dismissed()
            except (ValueError, RuntimeError) as exc:
                notice(describe(exc))  # token problems return to the choice, never abort

    while m["fido2"]:
        try:
            run([cryptenroll, "--unlock-key-file=/run/icy-installer/luks-password",
                 f"--fido2-device={token}", "--fido2-with-client-pin=yes", "--fido2-with-user-presence=yes",
                 "--fido2-with-user-verification=no", device], capture=False, private=True)
            break
        except RuntimeError:
            token = after_failure()
            if token is None:
                m["fido2"] = False
    # TODO: offer an opt-in first-boot script to remove ONLY the initial LUKS
    # passphrase slot, after verifying independent FIDO2 and recovery unlock.
    # Never remove a token credential, recovery key or any slot automatically.


def execute_install(repo, host, m, work, private, identity, certificate, token, snapshot):
    if os.geteuid() != 0 or not Path("/sys/firmware/efi").exists():
        raise ValueError("Installation requires root and UEFI boot")
    data, protected, held = inventory(run)
    key = device_key(m["disk"])
    if check_target(data, key, protected, held) != snapshot:
        raise ValueError("Target disk identity/state changed since preflight")
    run(["lsblk", "--paths", "--output", "NAME,MODEL,SERIAL,SIZE,FSTYPE,MOUNTPOINTS", m["disk"]], capture=False)
    notice("DESTRUCTIVE STEP: all partitions/data on the selected disk will be destroyed.")
    if ask(f"Type the exact target path to erase: {m['disk']}") != m["disk"]:
        raise ValueError("Disk confirmation did not match")
    password = secret_twice("Installed user login password")
    if m["encrypted"]:
        private_file(private, "luks-password", secret_twice("LUKS fallback passphrase (not login/FIDO PIN)"))
    # Recheck immediately before the only destructive invocation.
    data, protected, held = inventory(run)
    if check_target(data, device_key(m["disk"]), protected, held) != snapshot:
        raise ValueError("Target changed after confirmation")
    check_storage_names(m)
    progress(work, "formatting-started")
    run([work / "diskoScript"], capture=False)
    progress(work, "formatted-and-mounted")
    if m["encrypted"]:
        # Resolve actual parent of the specific mapper, not an ambiguous global partition label.
        mapper = "/dev/mapper/icy-" + m["hostname"]
        parent = run(["lsblk", "--noheadings", "--raw", "--output", "PKNAME", mapper]).strip()
        device = parent if parent.startswith("/dev/") else "/dev/" + parent
        if not device.startswith("/dev/") or "\n" in device:
            raise ValueError("Cannot identify LUKS backing partition")
        run(["cryptsetup", "open", "--test-passphrase", "--key-file", private / "luks-password", device])
        # Use exactly the selected target's systemd, not an older ISO's enrollment format.
        cryptenroll = nix_eval(repo, f"nixosConfigurations.{m['hostname']}.config.systemd.package.outPath") + "/bin/systemd-cryptenroll"
        enroll(m, device, token, cryptenroll)
        write_json(host / "install.json", m)
    hardware = run(["nixos-generate-config", "--root", "/mnt", "--no-filesystems", "--show-hardware-config"])
    (host / "hardware-configuration.nix").write_text(hardware)
    if m["hibernate"] and m["swapGiB"]:
        offset = run(["btrfs", "inspect-internal", "map-swapfile", "-r", "/mnt/swap/swapfile"]).strip()
        if not offset.isdigit():
            raise ValueError("Invalid Btrfs resume offset")
        uuid = run(["findmnt", "--noheadings", "--output", "UUID", "--target", "/mnt/swap"]).strip()
        if not uuid:
            raise ValueError("Cannot identify swap filesystem")
        write_json(host / "resume.json", {"boot": {"resumeDevice": "/dev/mapper/icy-" + m["hostname"] if m["encrypted"] else "/dev/disk/by-uuid/" + uuid,
                                                   "kernelParams": ["resume_offset=" + offset]}})
    stage_files(repo, list(host.iterdir()))
    # Build only now, into the target's /nix: the live ISO store is a RAM-backed tmpfs.
    system = build(repo, m["hostname"], "system.build.toplevel", work, store=TARGET_STORE)
    progress(work, "final-system-built")
    target = Path("/mnt" + REPOSITORY)
    prepare_target_parent(target)
    if target.exists():
        raise ValueError("Target repository already exists; refusing to overwrite")
    notice("Copying the configuration repository to the target...")
    copy_install_repository(repo, target)
    if m["personalSecrets"]:
        lock_installed_bookmarks(target)
    run(["git", "config", "core.sharedRepository", "group"], cwd=target)
    # Keys must exist before Home Manager activation during installation.
    userhome = Path("/mnt/home") / m["username"]
    userhome.mkdir(parents=True, exist_ok=True)
    os.chmod(userhome.parent, 0o755)
    os.chmod(userhome, 0o700)
    shutil.chown(userhome, 1000, 100)
    if identity:
        keys = userhome / ".keys"
        keys.mkdir(mode=0o700)
        shutil.copyfile(identity, keys / "age-master.key")
        os.chmod(keys / "age-master.key", 0o600)
        # New normal user has explicit UID 1000 in generated configuration.
        shutil.chown(keys, 1000, 100)
        shutil.chown(keys / "age-master.key", 1000, 100)
    notice("Running nixos-install (the system is already in the target store; this sets up the boot loader)...")
    # --system only sets the target profile (nix-env --store /mnt) to a path already in /mnt/nix/store.
    run(["nixos-install", "--root", "/mnt", "--system", system, "--no-root-passwd"], capture=False)
    run(["nixos-enter", "--root", "/mnt", "-c", "chpasswd"], input=m["username"] + ":" + password + "\n")
    password = ""
    run(["nixos-enter", "--root", "/mnt", "-c", f"chown -R root:configurators {REPOSITORY}"])
    run(["nixos-enter", "--root", "/mnt", "-c", f"chmod -R u+rwX,g+rwX,o-rwx {REPOSITORY}"])
    run(["nixos-enter", "--root", "/mnt", "-c", f"find {REPOSITORY} -type d -exec chmod g+s '{{}}' +"])
    run(["nixos-enter", "--root", "/mnt", "-c", f"setfacl -R -m g:configurators:rwX,m::rwX {REPOSITORY}"])
    run(["nixos-enter", "--root", "/mnt", "-c", f"find {REPOSITORY} -type d -exec setfacl -m d:u::rwx,d:g::rwx,d:m::rwx,d:o::--- '{{}}' +"])
    if certificate:
        destination = userhome / "signing-public.asc"
        shutil.copyfile(certificate, destination)
        shutil.chown(destination, 1000, 100)
        user = m["username"]  # validated shell-safe username; no arbitrary shell input.
        run(["nixos-enter", "--root", "/mnt", "-c", f"su - {user} -c 'gpg --batch --import /home/{user}/signing-public.asc'"], capture=False)
        run(["nixos-enter", "--root", "/mnt", "-c", f"su - {user} -c 'gpg --card-status'"], capture=False, private=True)
    progress(work, "installed")
    recovery = Path("/mnt/var/log/icy-installer")
    recovery.mkdir(mode=0o700, parents=True, exist_ok=True)
    shutil.copyfile(work / "stages.log", recovery / "stages.log")
    notice("Installed. Verify boot, login, signing, disk unlock/recovery and hibernation before relying on this machine.")


def progress(work, stage):
    with (work / "stages.log").open("a") as stream:
        stream.write(stage + "\n")
    notice("Stage: " + stage)


RUNTIME = Path("/run/icy-installer")
SKIP = object()


def describe(exc):
    """Message safe to print: subprocess argument values and I/O file names never appear."""
    if isinstance(exc, (RuntimeError, ValueError)):
        return str(exc)
    return (getattr(exc, "strerror", None) or "I/O failed") + "; check available space and permissions."


def destructive_started(work):
    log = work / "stages.log"
    return log.is_file() and "formatting-started" in log.read_text().split()


def last_stage(work):
    log = work / "stages.log"
    lines = log.read_text().split() if log.is_file() else []
    return lines[-1] if lines else "none"


def save_session(work, revision, manifest=None, history=None):
    """Nonsecret answers only (validate() rejects anything else); keys are never stored."""
    write_json(work / "session.json", {"revision": revision, "manifest": manifest, "history": history})


def load_session(work, repo):
    path = work / "session.json"
    data = None
    if path.is_file():
        loaded = json.loads(path.read_text())
        if isinstance(loaded, dict) and isinstance(loaded.get("revision"), str):
            data = loaded
    if data is None:
        head = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=repo, capture_output=True, text=True)
        data = {"revision": head.stdout.strip() if head.returncode == 0 else snapshot_digest(repo), "manifest": None}
    if data.get("manifest") is not None and not isinstance(data["manifest"], dict):
        raise ValueError("Manifest must be a JSON object")
    if not isinstance(data.get("history"), bool):
        # Older sessions: a Git revision (not a 64-hex content digest) means real history.
        data["history"] = len(data["revision"]) != 64
    return data


def trusted_dir(path, private=True):
    """Owned by us, not a symlink, and (private) inaccessible or (not private) unwritable to others."""
    try:
        info = path.lstat()
    except OSError:
        return False
    mask = 0o077 if private else 0o022
    return stat.S_ISDIR(info.st_mode) and info.st_uid == os.geteuid() and not info.st_mode & mask


def find_workspaces(base=Path("/var/tmp")):
    def age(directory):
        log = directory / "stages.log"
        return (log if log.exists() else directory).stat().st_mtime
    found = [d for d in base.glob("icy-install-*")
             if trusted_dir(d) and trusted_dir(d / "repository")
             and (d / ".prepared").is_file() and (d / "repository" / "flake.nix").is_file()]
    return sorted(found, key=age, reverse=True)


def lock_workspace(work):
    """Hold an exclusive lock on the workspace for the whole run; the returned fd must stay open."""
    fd = os.open(work / ".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        raise ValueError("Another installer is using this workspace.") from None
    return fd


def pick_workspace(base=Path("/var/tmp")):
    found = find_workspaces(base)
    if not found:
        raise ValueError(f"No resumable installer workspace in {base}. Workspaces from older installer versions "
                         "(without a .prepared marker) cannot be resumed. Start without --resume.")
    if len(found) == 1:
        notice(f"Resuming {found[0].name} (last stage: {last_stage(found[0])})")
        return found[0]
    labels = {f"{d.name} | last stage: {last_stage(d)}": d for d in found}
    return labels[choose("Which installer workspace should be resumed? (newest first)", list(labels))]


def prepare_runtime(path=None):
    path = path or RUNTIME
    if path.exists():
        if not confirm(f"{path} exists from an interrupted run (it may hold session secrets). Remove it and continue? Say No if another installer is running."):
            raise ValueError(f"{path} still exists; stop the other installer or remove it, then retry.")
        shutil.rmtree(path)
    path.mkdir(mode=0o700)  # session-owned; removed again when this run ends
    return path


def attempt(work, label, func, skip=None):
    """Run one stage. A failure offers Retry / Edit answers / Abort instead of exiting.

    Once formatting has started nothing here is safe to repeat automatically, so the
    error is passed to the caller, which reports manual recovery.
    """
    while True:
        try:
            return func()
        except (RuntimeError, ValueError, OSError) as exc:
            notice(f"{label} failed: {describe(exc)}")  # notice() also writes the log
            if destructive_started(work):
                raise
            options = ["Retry", "Edit answers"] + ([skip] if skip else []) + ["Abort (continue later: run-installer --resume)"]
            picked = choose(f"{label} failed. The disk has not been formatted.", options)
            if picked == "Retry":
                continue
            if picked == "Edit answers":
                raise BackToWizard from exc
            if skip and picked == skip:
                return SKIP
            raise KeyboardInterrupt from exc


def generate_stage(repo, work, m, schema, hardware):
    reset_generated(repo, m["hostname"])  # refuses an upstream host of this name
    reset_all_generated(repo)  # only hosts this installer generated earlier
    host = generate(repo, m, schema, hardware)
    branch = "hosts/" + m["hostname"]
    known = subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}"],
                           cwd=repo, capture_output=True).returncode == 0
    run(["git", "switch", *([] if known else ["-c"]), branch], cwd=repo, show_errors=True)
    stage_files(repo, list(host.iterdir()))
    notice(f"Evaluating the configuration for {m['hostname']} (this can take a few minutes)...")
    nix_eval(repo, f"nixosConfigurations.{m['hostname']}.config.system.build.toplevel.drvPath")
    progress(work, "generated-and-evaluated")
    return host


def preflight_stage(repo, work, m):
    data, protected, held = inventory(run)
    snapshot = check_target(data, device_key(m["disk"]), protected, held)
    check_storage_names(m)
    source_bytes = sum(p.stat().st_size for p in repo.rglob("*") if p.is_file() and not p.is_symlink())
    check_capacity(m, snapshot[1], source_bytes)
    notice(f"Free live store: {shutil.disk_usage('/nix/store').free // 1024**3} GiB. "
           "Only the small disk-layout script is built now; the full system is built on the target after formatting.")
    # The live store is RAM-backed (tmpfs); the system closure must not be built here.
    build(repo, m["hostname"], "system.build.diskoScript", work)
    progress(work, "prebuilt")
    return snapshot


def install_stage(repo, host, m, work, private, identity, certificate, token):
    """Preflight and install together, so Retry (before formatting) re-checks the disk first."""
    snapshot = preflight_stage(repo, work, m)
    execute_install(repo, host, m, work, private, identity, certificate, token, snapshot)


def pipeline(args, work, repo, revision, schema, m, history):
    # Decrypted bookmarks must never linger, whether personal setup is now off or an
    # earlier attempt failed after unlocking.
    relock(repo)

    def check_selection():
        reset_generated(repo, m["hostname"])  # refuses an upstream host of this name
        reset_all_generated(repo)
        for warning in swap_warnings(m["swapGiB"], ram_gib(), m["hibernate"]):
            notice("WARNING: " + warning)
        has_history = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=repo, capture_output=True).returncode == 0
        if m["personalSecrets"] and not has_history:
            raise ValueError("Personal setup requires a Git repository with a valid HEAD")
        if m["personalSecrets"]:
            for name in BOOKMARKS:
                encrypted_bookmark(repo, name)
        if args.dry_run and m["personalSecrets"]:
            raise ValueError("Dry-run does not unlock secrets. Select reduced setup for a secret-free dry-run.")

    attempt(work, "Setup check", check_selection)
    hardware = attempt(work, "Hardware scan", lambda: scan_hardware(work))
    private = None
    identity = certificate = token = None
    try:
        if not args.dry_run:
            if os.geteuid() != 0 or not Path("/sys/firmware/efi").exists():
                raise ValueError("Run installation as root from a UEFI-booted ISO")
            private = attempt(work, "Runtime state", prepare_runtime)
            if m["personalSecrets"]:
                identity = attempt(work, "Personal secrets", lambda: prepare_personal(repo, private))
            if m["signing"]:
                certificate = attempt(work, "YubiKey signing check", lambda: fetch_public(private),
                                      skip="Continue without signing")
                if certificate is SKIP:
                    certificate, m["signing"] = None, False
            if m["fido2"]:
                token = prepare_fido(m)
            save_session(work, revision, m, history)
        host = attempt(work, "Generate configuration", lambda: generate_stage(repo, work, m, schema, hardware))
        if args.dry_run:
            notice(f"Dry-run complete: {host}. No disk or token changes performed.")
            return
        attempt(work, "Build and install",
                lambda: install_stage(repo, host, m, work, private, identity, certificate, token))
    finally:
        if private and private.is_dir():
            # Only session-owned private runtime state, never the source/target checkout.
            subprocess.run(["gpgconf", "--homedir", private / "gnupg", "--kill", "all"], capture_output=True)
            shutil.rmtree(private)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(os.environ.get("ICY_INSTALLER_SOURCE", HERE.parent)))
    parser.add_argument("--no-update", action="store_true", help="Explicitly use the local snapshot; do not fetch latest Git revision")
    parser.add_argument("--resume", action="store_true", help="Continue in an earlier /var/tmp/icy-install-* workspace (asks which if several)")
    parser.add_argument("--dry-run", action="store_true", help="Generate/evaluate only: never format, mount, enroll, or install")
    parser.add_argument("--manifest", type=Path, help="Use nonsecret choices from JSON instead of the wizard; still confirm erasure interactively")
    args = parser.parse_args()
    os.umask(0o077)
    global LOG
    work = repo = lock = hostname = None
    try:
        if args.resume:
            work = pick_workspace()
            lock = lock_workspace(work)
            LOG = work / "installer.log"
            repo = work / "repository"
            if destructive_started(work):
                raise ValueError("Formatting already started in that workspace; the installer never repeats it automatically. Recover manually.")
            session = load_session(work, repo)
            revision, history = session["revision"], session["history"]
            if history:
                head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True)
                if head.returncode or head.stdout.strip() != revision:
                    raise ValueError("Workspace HEAD no longer matches the saved revision; start without --resume")
            verify_repo(repo, revision, history)
            progress(work, "resumed")
        else:
            work = Path(tempfile.mkdtemp(prefix="icy-install-", dir="/var/tmp"))
            lock = lock_workspace(work)
            LOG = work / "installer.log"
            notice(f"Recoverable private workspace: {work}. It may contain decrypted configuration; protect it.")
            progress(work, "workspace-created")
            repo, revision, history = prepare(work, args.source.resolve(), not args.no_update)
            session = {"manifest": None}
            save_session(work, revision, history=history)
        notice(f"Selected immutable source: {revision}")
        notice("Evaluating the option schema (this can take a few minutes)...")
        schema = nix_eval(repo, "installerSchema.x86_64-linux")
        m = json.loads(args.manifest.read_text()) if args.manifest else session.get("manifest")
        if m is not None and not isinstance(m, dict):
            raise ValueError("Manifest must be a JSON object")
        edit = m is None
        if args.resume and m is not None and not args.manifest:
            picked = choose("Resume with the saved answers?", ["Continue with saved answers", "Edit answers", "Abort"])
            if picked == "Abort":
                raise KeyboardInterrupt
            edit = picked == "Edit answers"
        while True:
            try:
                if edit:
                    m = wizard(repo, revision, schema, saved=m)
                m["revision"] = revision
                validate(m, schema)
            except (KeyError, TypeError) as exc:
                raise ValueError("Manifest is missing or has malformed fields") from exc
            hostname = m["hostname"]
            save_session(work, revision, m, history)
            try:
                pipeline(args, work, repo, revision, schema, m, history)
                return 0
            except BackToWizard:
                edit = True
    except KeyboardInterrupt:
        if work is None:
            notice("Stopped before a workspace was selected. Nothing was formatted.")
        elif not destructive_started(work):
            notice("Stopped by operator. Nothing was formatted.")
            resume_hint(work, lock)
        else:
            formatted_hint(work, repo, hostname)
        log_hint()
        return 1
    except (RuntimeError, ValueError, OSError) as exc:
        # No tracebacks or subprocess argument dumps: secrets must not leak.
        notice(f"Stopped: {type(exc).__name__}. {describe(exc)}")
        if work is None:
            notice("Stopped before a workspace was selected. Nothing was formatted.")
        elif not destructive_started(work):
            notice("Nothing was formatted.")
            resume_hint(work, lock)
        else:
            formatted_hint(work, repo, hostname)
        log_hint()
        return 1
    finally:
        cleanup(repo, lock)
        LOG = None
    return 0


def formatted_hint(work, repo, hostname):
    """After formatting nothing is retried automatically; print (and log) manual recovery."""
    notice(f"Disk is formatted but the build/install did not finish (last stage: {last_stage(work)}). "
           "Do NOT rerun the installer's formatting, and do not use --resume.")
    if repo is None:
        return
    notice(f"Recovery, with the target filesystems mounted at {TARGET} (mount them again first if they are not):")
    for line in recovery_commands(repo, hostname or "<hostname>", work):
        notice(line)
    notice(f"Then copy {repo} to {TARGET}{REPOSITORY} if it is missing, and verify boot and disk unlock before relying on it.")


def resume_hint(work, lock):
    """Suggest --resume only for a workspace this run prepared and held, which --resume will offer."""
    if lock is not None and (work / ".prepared").is_file():
        notice(f"Workspace: {work}")
        notice("Continue later with: run-installer --resume")


def log_hint():
    if LOG is not None and LOG.is_file():
        notice(f"Log: {LOG}")
        notice(f"Copy it off this machine with: scp {LOG} user@host:")


def cleanup(repo, lock):
    """Each step runs even if an earlier one fails; the key cache goes first."""
    try:
        if repo is not None:
            cache = repo / ".git" / "git-crypt"
            try:
                if cache.is_dir():
                    shutil.rmtree(cache)  # Session-generated unlock cache, never retained.
            except OSError:
                notice("Could not remove the git-crypt key cache; delete .git/git-crypt in the workspace.")
    finally:
        try:
            if repo is not None and (repo / ".git").exists():
                try:
                    relock(repo)  # decrypted bookmarks never remain in the retained workspace
                except (RuntimeError, ValueError, OSError):
                    notice("Could not restore encrypted bookmark files; check the workspace before sharing it.")
        finally:
            if lock is not None:
                try:
                    os.close(lock)
                except OSError:
                    pass


if __name__ == "__main__":
    sys.exit(main())
