#!/usr/bin/env python3
"""IcyOS coordinator. Only execute_install crosses the destructive boundary."""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from model import API, PRIMARY, SIGNING, REPOSITORY, check_storage_names, generate, swap_suggestion, swap_warnings, validate, write_json
from storage import check_target, device_key, flatten, inventory, stable_path

REMOTE = "https://github.com/IcyTv/nix-files.git"
HERE = Path(__file__).resolve().parent


def run(args, *, cwd=None, input=None, capture=True, env=None, private=False, show_errors=False, pass_fds=()):
    """Never include argument values in exceptions (some are sensitive paths)."""
    if private:
        # Bypass stdout/stderr redirection and tee: recovery output is terminal-only.
        with open("/dev/tty", "r+") as tty:
            result = subprocess.run([str(x) for x in args], cwd=cwd, text=True,
                                    stdin=tty, stdout=tty, stderr=tty, env=env, pass_fds=pass_fds)
    else:
        result = subprocess.run([str(x) for x in args], cwd=cwd, input=input, text=True,
                                stdout=subprocess.PIPE if capture else None,
                                stderr=subprocess.PIPE if capture else None, env=env, pass_fds=pass_fds)
    if result.returncode:
        if show_errors and result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        # Full diagnostics of Nix builds go directly to terminal, not to a persistent log.
        raise RuntimeError(f"{Path(args[0]).name} failed (exit {result.returncode})")
    return result.stdout if capture else ""


def choose(title, values):
    return run(["gum", "choose", "--header", title, "--", *values]).strip()


def ask(title, default=""):
    return run(["gum", "input", "--header", title, "--value", str(default)]).strip()


def confirm(title, default=False):
    return choose(title, ["Yes", "No"] if default else ["No", "Yes"]) == "Yes"


def notice(text):
    print(text, flush=True)


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
    return json.loads(run(["nix", "eval", "--no-write-lock-file", "--json", f"{repo}#{attr}"], show_errors=True))


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
            run(["git", "clone", "--no-checkout", REMOTE, repo], env=env)
            revision = run(["git", "rev-parse", "refs/remotes/origin/HEAD"], cwd=repo).strip()
            run(["git", "checkout", "--detach", revision], cwd=repo, env=env)
            history = True
        except RuntimeError:
            notice("Repository download failed. Using embedded/local snapshot; full installation still requires downloads.")
            repo = work / "snapshot"
    if not (repo / "flake.nix").exists():
        if not source.is_dir():
            raise ValueError("No usable installer snapshot")
        if (source / ".git").exists():
            # Restart from an explicitly chosen checkout without losing history
            # or copying .git/git-crypt's private symmetric-key cache.
            run(["git", "clone", "--no-hardlinks", "--no-checkout", source, repo], env=env)
            revision = run(["git", "rev-parse", "HEAD"], cwd=repo).strip()
            run(["git", "checkout", "--detach", revision], cwd=repo, env=env)
            history = True
        else:
            repo.mkdir()
            run(["git", "init", repo])
        allowed = {"flake.nix", "flake.lock", "rebuild.sh", "installer", "modules", "scripts", "secrets", "hosts", ".gitattributes", ".gitignore"}
        ignore_private = shutil.ignore_patterns("__pycache__", ".keys", "bookmarks-default.json", "bookmarks-yes.json")
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
        run(["git", "lfs", "install", "--local"], cwd=repo)
        # Scope initial snapshot staging to supplied configuration roots; never
        # enumerate incidental ignored tooling directories from a local clone.
        stage_files(repo, [repo / name for name in sorted(allowed) if (repo / name).exists()])
        if not history or run(["git", "status", "--porcelain"], cwd=repo).strip():
            revision = snapshot_digest(repo)
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
    run(["git", "lfs", "install", "--local"], cwd=repo)
    if history:
        run(["git", "remote", "set-url", "origin", REMOTE], cwd=repo)
        run(["git", "lfs", "pull"], cwd=repo, capture=False)
        run(["git", "lfs", "fsck"], cwd=repo, capture=False)
    # Snapshot repositories need an origin for later user pushes, without publishing anything now.
    if not run(["git", "remote"], cwd=repo).strip():
        run(["git", "remote", "add", "origin", REMOTE], cwd=repo)
    if len(revision) == 64:
        revision = snapshot_digest(repo)
    return repo, revision


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
    probe.mkdir()
    return run(["nixos-generate-config", "--root", probe, "--no-filesystems", "--show-hardware-config"])


def edit_options(schema, scope, answers):
    available = {".".join(o["path"]): o for o in schema if o["scope"] == scope and o["writable"]}
    def effective(option):
        if scope == "home" and answers.get("my.hm.default.enable", False):
            return option.get("presetDefault", option["default"])
        return option["default"]
    while True:
        entries = ["Done"] + [f"{name} = {json.dumps(answers.get(name, effective(o)))}"
                              for name, o in sorted(available.items())]
        selection = choose(f"{scope}: all user-facing my.* options", entries)
        if selection == "Done":
            return
        name = selection.split(" = ", 1)[0]
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


def wizard(repo, revision, schema):
    m = {"api": API, "revision": revision, "hostname": "", "username": "michael", "disk": "",
         "encrypted": True, "fido2": False, "personalSecrets": False, "signing": True,
         "swapGiB": 0, "hibernate": False, "timezone": "Europe/Berlin", "locale": "en_US.UTF-8",
         "gitName": "Michael Finger", "gitEmail": "michael.finger@icytv.de",
         "stateVersion": nix_eval(repo, "installerStateVersion"),
         "system": {}, "home": {"my.hm.default.enable": True}, "hardware": detect_hardware()}
    system_preset = ["bluetooth", "greetd", "limine", "niri", "printing", "rebuild", "stylix", "tools", "zsh"]
    names = {".".join(o["path"]) for o in schema if o["scope"] == "system"}
    m["system"] = {f"my.nixos.{name}.enable": True for name in system_preset if f"my.nixos.{name}.enable" in names}
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
            m["disk"] = options[choose("Select disk (not formatted yet)", list(options))]
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
            if (repo / "hosts" / m["hostname"]).exists():
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
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w") as stream:
        stream.write(contents)
    return path


def prepare_personal(repo, private):
    crypt = Path(ask("Explicit git-crypt key file path (not retained)"))
    # Suppress command diagnostics so key paths never enter persistent output.
    with crypt.open("rb") as key:
        run(["git-crypt", "unlock", f"/proc/self/fd/{key.fileno()}"], cwd=repo, pass_fds=(key.fileno(),))
    for name in ("bookmarks-default.json", "bookmarks-yes.json"):
        json.loads((repo / "secrets" / name).read_text())
        encrypted_bookmark(repo, name)
    age_path = Path(ask("Explicit age identity file path"))
    identity = private / "age-identity"
    with age_path.open("rb") as src, identity.open("xb") as dst:
        os.chmod(identity, 0o600)
        shutil.copyfileobj(src, dst)
    for name in ("id_ed25519.age", "github-token.age", "pay-respects-api-key.age"):
        with open(os.devnull, "w") as sink:
            result = subprocess.run(["age", "--decrypt", "--identity", identity, repo / "secrets" / name],
                                    stdout=sink, stderr=sink)
        if result.returncode:
            raise ValueError("Age identity cannot decrypt all personal credentials")
    if not confirm("Copy the age identity into your installed user's private .keys directory?"):
        raise ValueError("Personal setup needs the age identity after reboot. Rerun with personal setup disabled.")
    return identity


def fetch_public(private):
    certificate = private / "signing-public.asc"
    run(["curl", "--fail", "--silent", "--show-error", "--max-time", "60", "--proto", "=https", "--tlsv1.2", "--output", certificate,
         f"https://keys.openpgp.org/vks/v1/by-fingerprint/{PRIMARY}"])
    gnupg = private / "gnupg"
    gnupg.mkdir(mode=0o700)
    env = os.environ | {"GNUPGHOME": str(gnupg), "GPG_TTY": os.ttyname(sys.stdin.fileno())}
    listing = run(["gpg", "--batch", "--with-colons", "--import-options", "show-only", "--import", certificate], env=env)
    fingerprints = [line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:")]
    if not fingerprints or fingerprints[0] != PRIMARY or SIGNING not in fingerprints:
        raise ValueError("Keyserver certificate fingerprint/subkey mismatch")
    if not any(line.startswith("uid:") for line in listing.splitlines()):
        raise ValueError("Published public key has no verified identity. Complete the keys.openpgp.org verification email before signing setup.")
    run(["gpg", "--batch", "--import", certificate], env=env)
    run(["gpg", "--card-status"], env=env)
    keys = run(["gpg", "--batch", "--with-colons", "--with-keygrip", "--list-secret-keys", PRIMARY], env=env)
    rows = keys.splitlines()
    card_signer = False
    for i, line in enumerate(rows):
        fields = line.split(":")
        if fields[0] == "ssb" and len(fields) > 14 and fields[14] not in ("", "+", "#"):
            card_signer |= any(row.startswith("fpr:") and row.split(":")[9] == SIGNING for row in rows[i+1:i+3])
    if not card_signer:
        raise ValueError("Required signing subkey is not available as a smartcard-backed key")
    challenge = private_file(private, "signing-check.txt", "IcyOS installer signing verification\n")
    run(["gpg", "--local-user", SIGNING + "!", "--detach-sign", challenge], env=env, capture=False, private=True)
    run(["gpg", "--verify", str(challenge) + ".sig", challenge], env=env)
    return certificate


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


def build(repo, hostname, attribute, work):
    # Explicit output link retains the prebuilt closure until workspace cleanup.
    link = work / attribute
    run(["nix", "build", "--no-write-lock-file", "--out-link", link,
         f"{repo}#nixosConfigurations.{hostname}.config.system.build.{attribute}"], capture=False)
    return link.resolve()


def check_capacity(m, disk_bytes, closure_bytes, source_bytes):
    # Conservative uncompressed footprint plus EFI and Btrfs/installation slack.
    # Undersized swap only warns; a layout that cannot fit must not erase a disk.
    needed = (m["swapGiB"] + 2) * 1024 ** 3 + closure_bytes + source_bytes
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
    content = subprocess.check_output(["git", "show", ":secrets/" + name], cwd=repo)
    if not content.startswith(b"\0GITCRYPT\0"):
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
    while not confirm("Have you saved the recovery key separately from this encrypted disk?"):
        notice("Save the recovery key shown above before continuing. It is deliberately not in the log.")
    if m["fido2"]:
        while True:
            try:
                run([cryptenroll, "--unlock-key-file=/run/icy-installer/luks-password",
                     f"--fido2-device={token}", "--fido2-with-client-pin=yes", "--fido2-with-user-presence=yes",
                     "--fido2-with-user-verification=no", device], capture=False, private=True)
                break
            except RuntimeError:
                action = choose("Enrollment failed; disk is already formatted.", ["Retry", "Abort", "Continue passphrase + recovery only"])
                if action == "Abort":
                    raise RuntimeError("Stopped after formatting. Use retained configuration and recovery instructions.")
                if action.startswith("Continue"):
                    m["fido2"] = False
                    break
                token = select_fido()
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
    build(repo, m["hostname"], "toplevel", work)
    progress(work, "final-system-built")
    target = Path("/mnt" + REPOSITORY)
    prepare_target_parent(target)
    if target.exists():
        raise ValueError("Target repository already exists; refusing to overwrite")
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
    run(["nixos-install", "--root", "/mnt", "--system", (work / "toplevel").resolve(), "--no-root-passwd"], capture=False)
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(os.environ.get("ICY_INSTALLER_SOURCE", HERE.parent)))
    parser.add_argument("--no-update", action="store_true", help="Explicitly use the local snapshot; do not fetch latest Git revision")
    parser.add_argument("--dry-run", action="store_true", help="Generate/evaluate only: never format, mount, enroll, or install")
    parser.add_argument("--manifest", type=Path, help="Use nonsecret choices from JSON instead of the wizard; still confirm erasure interactively")
    args = parser.parse_args()
    os.umask(0o077)
    work = Path(tempfile.mkdtemp(prefix="icy-install-", dir="/var/tmp"))
    notice(f"Recoverable private workspace: {work}. It may contain decrypted configuration; protect it.")
    progress(work, "workspace-created")
    private = None
    repo = None
    try:
        repo, revision = prepare(work, args.source.resolve(), not args.no_update)
        notice(f"Selected immutable source: {revision}")
        schema = nix_eval(repo, "installerSchema.x86_64-linux")
        m = json.loads(args.manifest.read_text()) if args.manifest else wizard(repo, revision, schema)
        m["revision"] = revision
        validate(m, schema)
        if (repo / "hosts" / m["hostname"]).exists():
            raise ValueError("Host already exists")
        for warning in swap_warnings(m["swapGiB"], ram_gib(), m["hibernate"]):
            notice("WARNING: " + warning)
        # Snapshot source intentionally lacks unlocked bookmarks and Git crypt state.
        has_history = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=repo, capture_output=True).returncode == 0
        if m["personalSecrets"] and not has_history:
            raise ValueError("Personal setup requires a real repository clone with git-crypt metadata")
        hardware = scan_hardware(work)
        # In dry-run, no key prompts/imports or hardware-token operations.
        identity = certificate = token = None
        if not args.dry_run:
            if os.geteuid() != 0 or not Path("/sys/firmware/efi").exists():
                raise ValueError("Run installation as root from a UEFI-booted ISO")
            runtime = Path("/run/icy-installer")
            runtime.mkdir(mode=0o700)  # Existing state requires explicit operator cleanup.
            private = runtime  # Only clean up after successful creation by this run.
            if m["personalSecrets"]:
                identity = prepare_personal(repo, private)
            if m["signing"]:
                certificate = fetch_public(private)
            if m["fido2"]:
                token = prepare_fido(m)
        elif m["personalSecrets"]:
            raise ValueError("Dry-run does not unlock secrets. Select reduced setup for a secret-free dry-run.")
        host = generate(repo, m, schema, hardware)
        run(["git", "switch", "-c", "hosts/" + m["hostname"]], cwd=repo)
        stage_files(repo, list(host.iterdir()))
        nix_eval(repo, f"nixosConfigurations.{m['hostname']}.config.system.build.toplevel.drvPath")
        progress(work, "generated-and-evaluated")
        if args.dry_run:
            notice(f"Dry-run complete: {host}. No disk or token changes performed.")
            return
        data, protected, held = inventory(run)
        snapshot = check_target(data, device_key(m["disk"]), protected, held)
        check_storage_names(m)
        notice(f"Free live store: {shutil.disk_usage('/nix/store').free // 1024**3} GiB; workspace: {shutil.disk_usage(work).free // 1024**3} GiB. Build completes before formatting.")
        build(repo, m["hostname"], "toplevel", work)
        build(repo, m["hostname"], "diskoScript", work)
        sizes = json.loads(run(["nix", "path-info", "--json", "--closure-size", (work / "toplevel").resolve()]))
        record = sizes[0] if isinstance(sizes, list) else next(iter(sizes.values()))
        source_bytes = sum(p.stat().st_size for p in repo.rglob("*") if p.is_file() and not p.is_symlink())
        check_capacity(m, snapshot[1], record["closureSize"], source_bytes)
        progress(work, "prebuilt")
        execute_install(repo, host, m, work, private, identity, certificate, token, snapshot)
    except KeyboardInterrupt:
        notice("Cancelled. No automatic retry will occur; inspect stages.log before recovery.")
    except (RuntimeError, ValueError, OSError) as exc:
        # No tracebacks or subprocess argument dumps: secrets must not leak.
        notice(f"Stopped: {type(exc).__name__}. {exc if isinstance(exc, (RuntimeError, ValueError)) else 'I/O failed; check available space and permissions.'}")
        notice(f"Configuration/stages retained in {work}. Never rerun formatting as automatic recovery.")
        return 1
    finally:
        if repo is not None:
            cache = repo / ".git" / "git-crypt"
            if cache.is_dir():
                shutil.rmtree(cache)  # Session-generated unlock cache, never retained.
        if private and private.is_dir():
            # Only session-owned private runtime state, never the source/target checkout.
            subprocess.run(["gpgconf", "--homedir", private / "gnupg", "--kill", "all"], capture_output=True)
            shutil.rmtree(private)
    return 0


if __name__ == "__main__":
    sys.exit(main())
