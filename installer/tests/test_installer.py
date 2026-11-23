import copy
import json
import os
import shutil
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main
from model import generate, swap_suggestion, swap_warnings, validate
from storage import check_target, raw_device_open


def manifest():
    return dict(api=1, revision="a" * 40, hostname="test-falcon", username="michael",
                disk="/dev/disk/by-id/test", encrypted=False, fido2=False,
                personalSecrets=False, signing=False, swapGiB=4, hibernate=False,
                timezone="Europe/Berlin", locale="en_US.UTF-8", gitName="Michael Finger",
                gitEmail="michael.finger@icytv.de", stateVersion="26.05", system={}, home={},
                hardware=dict(cpu="amd", gpu="other", vm="kvm", laptop=False))


def disks():
    def node(mm, name, typ="disk", **extra):
        return {"maj:min": mm, "name": name, "type": typ, "size": 100000, "ro": False,
                "serial": name, "wwn": None, "mountpoints": [], **extra}
    return [node("8:0", "/dev/sda", children=[node("8:1", "/dev/sda1", "part", mountpoints=["/iso"])]),
            node("8:16", "/dev/sdb", children=[node("8:17", "/dev/sdb1", "part")])]


class ModelTests(unittest.TestCase):
    def test_swap_boundaries(self):
        for ram, normal, hibernate in [(1, 2, 3), (2, 4, 6), (8, 8, 16), (16, 4, 24), (64, 4, 96), (128, 4, 192)]:
            self.assertEqual(swap_suggestion(ram), normal)
            self.assertEqual(swap_suggestion(ram, True), hibernate)

    def test_zero_hibernation_only_warns(self):
        m = manifest() | {"swapGiB": 0, "hibernate": True}
        validate(m, [])
        self.assertTrue(any("will not work" in w for w in swap_warnings(0, 32, True)))
        main.check_capacity(m, 64 * 1024 ** 3, 8 * 1024 ** 3, 0)

    def test_impossible_layout_rejected_before_erasure(self):
        with self.assertRaisesRegex(ValueError, "cannot fit"):
            main.check_capacity(manifest() | {"swapGiB": 100}, 64 * 1024 ** 3, 0, 0)

    def test_keys_and_injection_rejected(self):
        for changes in ({"password": "secret"}, {"hostname": "../../eagle"}, {"username": "root"},
                        {"username": "m;false"}, {"swapGiB": True}, {"personalSecrets": True},
                        {"fido2": True}, {"disk": "/dev/$(touch bad)"}, {"disk": "/dev/../etc/passwd"},
                        {"revision": "main"}, {"system": {"boot.loader.grub.enable": True}}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(manifest() | changes, [])

    def test_option_types(self):
        schema = [dict(scope="home", path=["my", "hm", "git", "excludes"], type="listOf", supported=True, writable=True)]
        validate(manifest() | {"home": {"my.hm.git.excludes": ["a", '"${malicious}"']}}, schema)
        with self.assertRaises(ValueError):
            validate(manifest() | {"home": {"my.hm.git.excludes": "not a list"}}, schema)

    def test_generation_is_data_safe_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            (repo / "hosts").mkdir()
            m = manifest() | {"gitName": '"${builtins.abort "bad"}"'}
            host = generate(repo, m, [], '{...}: {nixpkgs.hostPlatform = "x86_64-linux";}')
            self.assertEqual(json.loads((host / "install.json").read_text()), m)
            self.assertIn("fromJSON", (host / "configuration.nix").read_text())
            with self.assertRaises(FileExistsError):
                generate(repo, m, [], "{}")


class SafetyTests(unittest.TestCase):
    def test_shared_checkout_parent_is_traversable_despite_private_umask(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "etc" / "nixos" / "nix-files"
            old = os.umask(0o077)
            try:
                main.prepare_target_parent(target)
            finally:
                os.umask(old)
            self.assertEqual(target.parent.stat().st_mode & 0o777, 0o755)
            self.assertEqual(target.parent.parent.stat().st_mode & 0o777, 0o755)

    @unittest.skipUnless(shutil.which("fuser"), "native fuser not on PATH")
    def test_native_fuser_detects_open_file(self):
        with tempfile.NamedTemporaryFile() as opened:
            self.assertTrue(raw_device_open(opened.name))

    def test_raw_device_users_and_probe_errors(self):
        from subprocess import CompletedProcess
        for code, expected in ((0, True), (1, False)):
            with patch("storage.subprocess.run", return_value=CompletedProcess([], code, b"", b"")):
                self.assertEqual(raw_device_open("/dev/test"), expected)
        with patch("storage.subprocess.run", return_value=CompletedProcess([], 2, b"", b"failure")):
            with self.assertRaises(ValueError):
                raw_device_open("/dev/test")
    def test_original_git_crypt_key_path_is_not_in_argv(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo, private = root / "repo", root / "private"
            (repo / "secrets").mkdir(parents=True)
            private.mkdir()
            for name in ("bookmarks-default.json", "bookmarks-yes.json"):
                (repo / "secrets" / name).write_text("[]")
            key, age = root / "external-sensitive-name", root / "external-age"
            key.write_bytes(b"test fixture")
            age.write_text("test fixture")
            missing = str(root / "typo")
            # Mistyped paths re-prompt instead of aborting the installer.
            with patch.object(main, "ask_path", side_effect=[missing, str(key), missing, str(age)]) as prompts, \
                 patch.object(main, "run", return_value="") as run, \
                 patch.object(main, "encrypted_bookmark", return_value=b"\0GITCRYPT\0"), \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(0)), \
                 patch.object(main, "confirm", return_value=False):
                with self.assertRaises(ValueError):
                    main.prepare_personal(repo, private)
                argv = run.call_args.args[0]
                self.assertTrue(argv[2].startswith("/proc/self/fd/"))
                self.assertNotIn(str(key), argv)
                self.assertTrue(run.call_args.kwargs["pass_fds"])
                self.assertEqual(prompts.call_count, 4)

    def test_personal_blob_must_already_be_encrypted(self):
        with patch.object(main.subprocess, "check_output", return_value=b"plaintext"):
            with self.assertRaisesRegex(ValueError, "encrypted Git bookmark"):
                main.encrypted_bookmark(Path("/repo"), "bookmarks-default.json")

    def test_local_restart_preserves_history_without_staging_tooling(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, work = Path(tmp) / "source", Path(tmp) / "work"
            (source / ".git").mkdir(parents=True)
            (source / "installer").mkdir()
            (source / "installer" / "main.py").write_text("snapshot")
            (source / "flake.nix").write_text("{}")
            work.mkdir()

            def fake_run(args, **kwargs):
                if args[:2] == ["git", "clone"]:
                    repo = args[-1]
                    (repo / ".git").mkdir(parents=True)
                    (repo / ".opencode").mkdir()
                    (repo / ".opencode" / "ignored.lock").write_text("ignored tooling")
                if args[:2] == ["git", "rev-parse"]:
                    return "a" * 40
                if args == ["git", "remote"]:
                    return "origin\n"
                return ""

            with patch.object(main, "run", side_effect=fake_run) as run, \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(0)), \
                 patch.object(main, "nix_eval", return_value=1), patch.object(main, "engine_digest", return_value="same"):
                repo, revision = main.prepare(work, source, update=False)
                self.assertEqual(revision, "a" * 40)
                staging = [call.args[0] for call in run.call_args_list if call.args[0][:2] == ["git", "add"]]
                self.assertTrue(staging)
                self.assertFalse(any(".opencode" in str(command) for command in staging))

    def test_nix_references_are_git_aware_not_path_inputs(self):
        with patch.object(main, "run", return_value="1") as run:
            self.assertEqual(main.nix_eval(Path("/private/repository"), "installerApi"), 1)
            self.assertIn("/private/repository#installerApi", run.call_args.args[0])
            self.assertNotIn("path:", " ".join(run.call_args.args[0]))

    def test_snapshot_digest_excludes_private_git_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            (repo / "flake.nix").write_text("{}")
            before = main.snapshot_digest(repo)
            cache = repo / ".git" / "git-crypt" / "keys"
            cache.mkdir(parents=True)
            (cache / "default").write_text("private material")
            self.assertEqual(main.snapshot_digest(repo), before)

    def test_git_crypt_private_cache_not_copied_to_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, target = Path(tmp) / "source", Path(tmp) / "target"
            cache = source / ".git" / "git-crypt" / "keys"
            cache.mkdir(parents=True)
            (cache / "default").write_text("private key")
            (source / ".git" / "HEAD").write_text("ref: refs/heads/main\n")
            main.copy_install_repository(source, target)
            self.assertFalse((target / ".git" / "git-crypt").exists())
            self.assertTrue((target / ".git" / "HEAD").is_file())

    def test_optical_boot_medium_is_valid_protection(self):
        data = disks()
        data[0]["type"] = "rom"
        self.assertEqual(check_target(data, "8:16", {"8:0"}, set())[0], "8:16")

    def test_loop_only_protection_is_not_enough(self):
        data = disks()
        data[0]["type"] = "loop"
        data[0]["children"] = []
        with self.assertRaises(ValueError):
            check_target(data, "8:16", {"8:0"}, set())

    def test_store_snapshot_is_writable_without_changing_source(self):
        import shutil
        with tempfile.TemporaryDirectory() as tmp:
            source, dest = Path(tmp) / "source", Path(tmp) / "copy"
            source.mkdir()
            (source / "hosts").mkdir(mode=0o555)
            shutil.copytree(source, dest)
            main.writable_snapshot(dest)
            (dest / "hosts" / "new-host").mkdir()
            self.assertEqual((source / "hosts").stat().st_mode & 0o777, 0o555)
            (source / "hosts").chmod(0o755)

    def test_hardware_scan_does_not_probe_live_btrfs_root(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(main, "run", return_value="hardware") as run:
            self.assertEqual(main.scan_hardware(Path(tmp)), "hardware")
            self.assertEqual(run.call_args.args[0], ["nixos-generate-config", "--root", Path(tmp) / "hardware-probe",
                                                    "--no-filesystems", "--show-hardware-config"])

    def test_unused_disk_accepted(self):
        self.assertEqual(check_target(disks(), "8:16", {"8:1"}, set())[0], "8:16")

    def test_boot_disk_rejected(self):
        with self.assertRaises(ValueError):
            check_target(disks(), "8:0", {"8:1"}, set())

    def test_unknown_boot_medium_rejected(self):
        for protected in (set(), {"99:99"}):
            with self.assertRaises(ValueError):
                check_target(disks(), "8:16", protected, set())

    def test_swap_and_loop_backing_rejected(self):
        with self.assertRaises(ValueError):
            check_target(disks(), "8:16", {"8:1", "8:17"}, set())

    def test_holders_and_readonly_rejected(self):
        with self.assertRaises(ValueError):
            check_target(disks(), "8:16", {"8:1"}, {"8:17"})
        data = disks()
        data[1]["ro"] = True
        with self.assertRaises(ValueError):
            check_target(data, "8:16", {"8:1"}, set())

    def test_partition_not_disk(self):
        with self.assertRaises(ValueError):
            check_target(disks(), "8:17", {"8:1"}, set())

    def test_mounted_child_rejected(self):
        data = disks()
        data[1]["children"][0]["mountpoints"] = ["/home"]
        with self.assertRaises(ValueError):
            check_target(data, "8:16", {"8:1"}, set())

    def test_exact_confirmation_before_any_destructive_command(self):
        data = disks()
        identity = check_target(data, "8:16", {"8:1"}, set())
        with patch.object(main.os, "geteuid", return_value=0), patch.object(Path, "exists", return_value=True), \
             patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
             patch.object(main, "device_key", return_value="8:16"), patch.object(main, "ask", return_value="wrong"), \
             patch.object(main, "run", return_value="") as run:
            with self.assertRaisesRegex(ValueError, "confirmation"):
                main.execute_install(Path("/test"), Path("/test/host"), manifest(), Path("/work"), Path("/private"), None, None, None, identity)
            self.assertEqual([call.args[0][0] for call in run.call_args_list], ["lsblk"])

    def test_changed_disk_rejected_before_confirmation(self):
        with patch.object(main.os, "geteuid", return_value=0), patch.object(Path, "exists", return_value=True), \
             patch.object(main, "inventory", return_value=(disks(), {"8:1"}, set())), \
             patch.object(main, "device_key", return_value="8:16"), patch.object(main, "run") as run:
            with self.assertRaisesRegex(ValueError, "changed"):
                main.execute_install(Path("/test"), Path("/test/host"), manifest(), Path("/work"), Path("/private"), None, None, None, ("different",))
            run.assert_not_called()

    def test_enrollment_downgrade_requires_explicit_choice(self):
        m = manifest() | {"encrypted": True, "fido2": True}
        with patch.object(main, "run", side_effect=["", RuntimeError("failed")]) as run, \
             patch.object(main, "confirm", return_value=True), \
             patch.object(main, "choose", return_value="Continue passphrase + recovery only"):
            main.enroll(m, "/dev/test", "/dev/hidraw0")
            self.assertFalse(m["fido2"])
            self.assertTrue(all(not call.kwargs.get("capture", True) for call in run.call_args_list))
            self.assertFalse(any("wipe-slot" in str(call) for call in run.call_args_list))

    def test_no_secret_command_arguments_in_errors(self):
        with patch.object(main.subprocess, "run", return_value=subprocess_result(1)):
            with self.assertRaisesRegex(RuntimeError, "git-crypt failed") as exc:
                main.run(["git-crypt", "unlock", "/secret/keypath"])
            self.assertNotIn("keypath", str(exc.exception))

    def test_stage_scope(self):
        with patch.object(main, "run") as run:
            main.stage_files(Path("/repo"), [Path("/repo/hosts/falcon/configuration.nix")])
            self.assertEqual(run.call_args.args[0], ["git", "add", "--", "hosts/falcon/configuration.nix"])


class ResumeAndRetryTests(unittest.TestCase):
    def test_failed_stage_offers_retry_then_succeeds(self):
        calls = []

        def stage():
            calls.append(1)
            if len(calls) == 1:
                raise RuntimeError("gpg failed (exit 2)")
            return "ok"

        with tempfile.TemporaryDirectory() as tmp, patch.object(main, "choose", return_value="Retry") as pick:
            self.assertEqual(main.attempt(Path(tmp), "Signing", stage), "ok")
            self.assertEqual(len(calls), 2)
            self.assertIn("Retry", pick.call_args.args[1])

    def test_failed_stage_can_edit_answers_skip_or_abort(self):
        def stage():
            raise ValueError("boom")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            with patch.object(main, "choose", return_value="Edit answers"):
                with self.assertRaises(main.BackToWizard):
                    main.attempt(work, "Signing", stage)
            with patch.object(main, "choose", return_value="Skip it"):
                self.assertIs(main.attempt(work, "Signing", stage, skip="Skip it"), main.SKIP)
            with patch.object(main, "choose", return_value="Abort (continue later: run-installer --resume)"):
                with self.assertRaises(KeyboardInterrupt):
                    main.attempt(work, "Signing", stage)

    def test_no_retry_prompt_once_formatting_started(self):
        def stage():
            raise RuntimeError("late failure")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "stages.log").write_text("workspace-created\nformatting-started\n")
            with patch.object(main, "choose") as pick:
                with self.assertRaisesRegex(RuntimeError, "late failure"):
                    main.attempt(work, "Installation", stage)
                pick.assert_not_called()

    def test_session_round_trip_and_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            main.save_session(work, "a" * 40, {"hostname": "falcon"})
            self.assertEqual(main.load_session(work, work), {"revision": "a" * 40, "manifest": {"hostname": "falcon"}})
            (work / "session.json").write_text("not json at all")
            with self.assertRaises(ValueError):
                main.load_session(work, work)

    def test_find_workspaces_newest_first_and_requires_repository(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            for name, stamp in (("icy-install-old", 100), ("icy-install-new", 200), ("icy-install-empty", 300)):
                directory = base / name
                if name != "icy-install-empty":
                    (directory / "repository").mkdir(parents=True)
                    (directory / "repository" / "flake.nix").write_text("{}")
                else:
                    directory.mkdir()
                (directory / "stages.log").write_text("workspace-created\n")
                os.utime(directory / "stages.log", (stamp, stamp))
            self.assertEqual([d.name for d in main.find_workspaces(base)], ["icy-install-new", "icy-install-old"])
            with patch.object(main, "choose", side_effect=lambda title, values, *a: values[0]):
                self.assertEqual(main.pick_workspace(base).name, "icy-install-new")
            with self.assertRaises(ValueError):
                main.pick_workspace(base / "missing")

    def test_formatting_workspace_cannot_be_resumed(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "stages.log").write_text("formatting-started\n")
            self.assertTrue(main.destructive_started(work))
            (work / "stages.log").write_text("workspace-created\ngenerated-and-evaluated\n")
            self.assertFalse(main.destructive_started(work))

    def test_choose_keeps_cursor_on_current_entry(self):
        with patch.object(main, "run_interactive", return_value="b") as run:
            main.choose("title", ["a", "b", "c"], "b")
            argv = run.call_args.args[0]
            self.assertEqual(argv[argv.index("--selected") + 1], "b")
            main.choose("title", ["a", "b", "c"], "x,y")
            self.assertNotIn("--selected", run.call_args.args[0])
            main.choose("title", ["a", "b", "c"])
            self.assertNotIn("--selected", run.call_args.args[0])

    def test_option_editor_returns_to_edited_entry(self):
        schema = [{"scope": "system", "path": ["my", "nixos", name, "enable"], "writable": True,
                   "supported": True, "type": "bool", "default": False, "description": "d"} for name in ("a", "b", "c")]
        answers = {}
        cursors = []

        def fake_choose(title, entries, current=None):
            cursors.append(current)
            return "Done" if len(cursors) == 2 else next(e for e in entries if e.startswith("my.nixos.b.enable"))

        with patch.object(main, "choose", side_effect=fake_choose), patch.object(main, "confirm", return_value=True):
            main.edit_options(schema, "system", answers)
        self.assertEqual(answers, {"my.nixos.b.enable": True})
        self.assertEqual(cursors[0], "Done")
        self.assertTrue(cursors[1].startswith("my.nixos.b.enable"))

    def test_preset_defaults_follow_requested_choices(self):
        for name in ("ananicy", "console-font", "docker", "geoclue", "keyd", "keymap", "plymouth", "subniri", "sudo-rs"):
            self.assertIn(name, main.SYSTEM_PRESET)
        self.assertEqual(sorted(main.HOME_DISABLED), ["ai", "anyrun", "games", "unifiedremote"])

    def test_wizard_applies_preset_defaults_only_for_known_options(self):
        schema = [{"scope": "system", "path": ["my", "nixos", name, "enable"], "writable": True, "supported": True,
                   "type": "bool", "default": False, "description": ""} for name in ("docker", "zsh")]
        schema += [{"scope": "home", "path": ["my", "hm", name, "enable"], "writable": True, "supported": True,
                    "type": "bool", "default": False, "description": ""} for name in ("ai", "kitty")]
        with patch.object(main, "nix_eval", return_value="26.05"), \
             patch.object(main, "detect_hardware", return_value=dict(cpu="amd", gpu="amd", vm="none", laptop=False)):
            m = main.default_answers(Path("/repo"), "a" * 40, schema)
        self.assertEqual(m["system"], {"my.nixos.docker.enable": True, "my.nixos.zsh.enable": True})
        self.assertEqual(m["home"], {"my.hm.default.enable": True, "my.hm.ai.enable": False})

    def test_wizard_saved_answers_are_kept_not_reset(self):
        saved = manifest()
        saved["hostname"] = "kept-host"
        with patch.object(main, "notice"), patch.object(main, "ask", side_effect=lambda t, d="": d), \
             patch.object(main, "confirm", side_effect=lambda t, d=False: d), \
             patch.object(main, "inventory", side_effect=ValueError("stop here")):
            with self.assertRaisesRegex(ValueError, "stop here"):
                with patch.object(main, "choose", return_value="Continue"):
                    main.wizard(Path("/repo"), saved["revision"], [], saved=saved)
        self.assertEqual(saved["hostname"], "kept-host")


class GitBackedTests(unittest.TestCase):
    """Real git; no network, no key material, nothing outside a temporary directory."""

    def git(self, cwd, *args):
        import subprocess
        return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", *args],
                              cwd=cwd, check=True, capture_output=True, text=True).stdout

    def repo_with_host(self, root):
        import subprocess
        repo = Path(root) / "repo"
        (repo / "hosts" / "upstream").mkdir(parents=True)
        (repo / "hosts" / "upstream" / "x.nix").write_text("{}")
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        self.git(repo, "add", "-A")
        self.git(repo, "commit", "-qm", "base")
        return repo

    def test_regenerating_our_own_host_is_allowed_but_upstream_hosts_are_not(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self.repo_with_host(tmp)
            (repo / "hosts" / "mine").mkdir()
            (repo / "hosts" / "mine" / "install.json").write_text("{}")
            self.git(repo, "add", "-A")
            self.assertFalse(main.host_taken(repo, "mine"))
            self.assertTrue(main.host_taken(repo, "upstream"))
            main.reset_generated(repo, "mine")
            self.assertFalse((repo / "hosts" / "mine").exists())
            with self.assertRaisesRegex(ValueError, "already exists"):
                main.reset_generated(repo, "upstream")
            self.assertTrue((repo / "hosts" / "upstream" / "x.nix").exists())

    def test_relock_restores_ciphertext_from_the_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self.repo_with_host(tmp)
            (repo / "secrets").mkdir()
            cipher = b"\0GITCRYPT\0" + b"x" * 20
            for name in main.BOOKMARKS:
                (repo / "secrets" / name).write_bytes(cipher)
            self.git(repo, "add", "-A")
            self.git(repo, "commit", "-qm", "secrets")
            for name in main.BOOKMARKS:
                (repo / "secrets" / name).write_text('["plaintext"]')
            main.relock(repo)
            for name in main.BOOKMARKS:
                self.assertEqual((repo / "secrets" / name).read_bytes(), cipher)
            self.assertEqual(self.git(repo, "status", "--porcelain").strip(), "")


def subprocess_result(code):
    from subprocess import CompletedProcess
    return CompletedProcess([], code, stdout="", stderr="secret diagnostic")


if __name__ == "__main__":
    unittest.main()
