import copy
import io
import json
import os
import shutil
import stat
import subprocess
from pathlib import Path
import sys
import tempfile
import time
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
        main.check_capacity(m, 128 * 1024 ** 3, 0)

    def test_impossible_layout_rejected_before_erasure(self):
        with self.assertRaisesRegex(ValueError, "cannot fit"):
            main.check_capacity(manifest() | {"swapGiB": 100}, 128 * 1024 ** 3, 0)

    def test_capacity_reserves_a_fixed_system_minimum(self):
        gib = 1024 ** 3
        m = manifest() | {"swapGiB": 4}
        main.check_capacity(m, (main.MIN_SYSTEM_GIB + 4 + 2) * gib, 0)
        with self.assertRaisesRegex(ValueError, "cannot fit"):
            main.check_capacity(m, (main.MIN_SYSTEM_GIB + 4 + 2) * gib, 1)
        with self.assertRaisesRegex(ValueError, "cannot fit"):
            main.check_capacity(m | {"swapGiB": 0}, 60 * gib, 0)

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
                 patch.object(main, "relock"), \
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
                repo, revision, history = main.prepare(work, source, update=False)
                self.assertEqual(revision, "a" * 40)
                self.assertTrue(history)
                self.assertTrue((work / ".prepared").is_file())
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
        with patch.object(main, "install_environment_ok", return_value=True), \
             patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
             patch.object(main, "device_key", return_value="8:16"), patch.object(main, "ask", return_value="wrong"), \
             patch.object(main, "run", return_value="") as run:
            with self.assertRaisesRegex(ValueError, "confirmation"):
                main.execute_install(Path("/test"), Path("/test/host"), manifest(), Path("/work"), Path("/private"), None, None, None, identity)
            self.assertEqual([call.args[0][0] for call in run.call_args_list], ["lsblk"])

    def test_changed_disk_rejected_before_confirmation(self):
        with patch.object(main, "install_environment_ok", return_value=True), \
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
            work = Path(tmp) / "work"
            repo = work / "repository"
            repo.mkdir(parents=True)
            (repo / "flake.nix").write_text("{}")
            main.save_session(work, "a" * 40, {"hostname": "falcon"}, history=True)
            self.assertEqual(main.load_session(work, repo),
                             {"revision": "a" * 40, "manifest": {"hostname": "falcon"}, "history": True})
            # Missing session.json: a snapshot without Git history falls back to its content digest.
            (work / "session.json").unlink()
            fallback = main.load_session(work, repo)
            self.assertEqual(fallback, {"revision": main.snapshot_digest(repo), "manifest": None, "history": False})
            # With a Git HEAD the fallback is that commit.
            with patch.object(main.subprocess, "run", return_value=subprocess_result(0, "b" * 40 + "\n")):
                self.assertEqual(main.load_session(work, repo),
                                 {"revision": "b" * 40, "manifest": None, "history": True})
            # A later save (with answers) keeps the snapshot flag instead of dropping it.
            main.save_session(work, "c" * 64, {"hostname": "falcon"}, False)
            self.assertIs(main.load_session(work, repo)["history"], False)
            (work / "session.json").write_text("not json at all")
            with self.assertRaises(ValueError):
                main.load_session(work, repo)
            (work / "session.json").write_text(json.dumps({"revision": "a" * 40, "manifest": ["not", "a", "dict"]}))
            with self.assertRaisesRegex(ValueError, "JSON object"):
                main.load_session(work, repo)

    def make_workspace(self, base, name, stamp=100):
        directory = base / name
        (directory / "repository").mkdir(parents=True, mode=0o700)
        directory.chmod(0o700)
        (directory / "repository").chmod(0o700)
        (directory / "repository" / "flake.nix").write_text("{}")
        (directory / ".prepared").touch()
        (directory / "stages.log").write_text("workspace-created\n")
        os.utime(directory / "stages.log", (stamp, stamp))
        return directory

    def test_find_workspaces_newest_first_and_requires_repository(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            self.make_workspace(base, "icy-install-old", 100)
            self.make_workspace(base, "icy-install-new", 200)
            (base / "icy-install-empty").mkdir(mode=0o700)
            (base / "icy-install-empty" / "stages.log").write_text("workspace-created\n")
            self.assertEqual([d.name for d in main.find_workspaces(base)], ["icy-install-new", "icy-install-old"])
            with patch.object(main, "choose", side_effect=lambda title, values, *a: values[0]):
                self.assertEqual(main.pick_workspace(base).name, "icy-install-new")
            with self.assertRaises(ValueError):
                main.pick_workspace(base / "missing")

    def test_find_workspaces_skips_untrusted_or_unprepared(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            self.make_workspace(base, "icy-install-good")
            (self.make_workspace(base, "icy-install-unprepared") / ".prepared").unlink()
            self.make_workspace(base, "icy-install-open").chmod(0o755)
            (self.make_workspace(base, "icy-install-openrepo") / "repository").chmod(0o750)
            real = self.make_workspace(Path(tmp) / "elsewhere", "target")
            (base / "icy-install-link").symlink_to(real)
            linked = self.make_workspace(base, "icy-install-linkedrepo")
            shutil.move(str(linked / "repository"), str(Path(tmp) / "elsewhere" / "repo"))
            (linked / "repository").symlink_to(Path(tmp) / "elsewhere" / "repo")
            # The run lock file must not hide a workspace.
            main.os.close(main.lock_workspace(base / "icy-install-good"))
            self.assertEqual([d.name for d in main.find_workspaces(base)], ["icy-install-good"])
            with patch.object(main.os, "geteuid", return_value=os.geteuid() + 1):
                self.assertEqual(main.find_workspaces(base), [])

    def test_workspace_lock_is_exclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            first = main.lock_workspace(work)
            try:
                # flock locks belong to the open file description, so a second open conflicts.
                with self.assertRaisesRegex(ValueError, "Another installer"):
                    main.lock_workspace(work)
            finally:
                os.close(first)
            os.close(main.lock_workspace(work))

    def test_gum_escape_is_cancelled_but_ctrl_c_interrupts(self):
        def outcome(code):
            with patch.object(main.os, "open", return_value=99), patch.object(main.os, "close"), \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(code)):
                try:
                    main.run_interactive(["gum", "choose"])
                except KeyboardInterrupt as exc:
                    return type(exc)
        self.assertIs(outcome(1), main.Cancelled)
        self.assertIs(outcome(130), KeyboardInterrupt)

    def test_cancelled_prompts_in_ask_file_mean_no(self):
        with tempfile.NamedTemporaryFile() as chosen:
            with patch.object(main, "ask_path", side_effect=[main.Cancelled, "", chosen.name]), \
                 patch.object(main, "confirm", side_effect=[main.Cancelled, False]) as asked, \
                 patch.object(main, "notice"):
                self.assertEqual(main.ask_file("Key"), Path(chosen.name))
                self.assertEqual(asked.call_count, 2)
            with patch.object(main, "ask_path", return_value=""), \
                 patch.object(main, "confirm", side_effect=KeyboardInterrupt), patch.object(main, "notice"):
                with self.assertRaises(KeyboardInterrupt) as exc:
                    main.ask_file("Key")
                self.assertNotIsInstance(exc.exception, main.Cancelled)

    def test_ask_file_rejection_message_is_described(self):
        with tempfile.NamedTemporaryFile() as chosen:
            def check(path):
                raise OSError(2, "No such file", "/secret/path")
            with patch.object(main, "ask_path", side_effect=[chosen.name, ""]), \
                 patch.object(main, "confirm", return_value=True), patch.object(main, "notice") as said:
                with self.assertRaises(KeyboardInterrupt):
                    main.ask_file("Key", check)
            self.assertNotIn("/secret/path", str(said.call_args_list))

    def test_enroll_escape_on_recovery_confirmation_reprompts(self):
        m = manifest() | {"encrypted": True, "fido2": True}
        with patch.object(main, "run", side_effect=["", RuntimeError("failed")]), \
             patch.object(main, "confirm", side_effect=[main.Cancelled, True]) as asked, \
             patch.object(main, "choose", side_effect=[main.Cancelled, "Continue passphrase + recovery only"]) as picked, \
             patch.object(main, "notice"):
            main.enroll(m, "/dev/test", "/dev/hidraw0")
        self.assertEqual(asked.call_count, 2)
        self.assertEqual(picked.call_count, 2)
        self.assertFalse(m["fido2"])
        with patch.object(main, "run", return_value=""), patch.object(main, "confirm", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                main.enroll(manifest(), "/dev/test", None)

    def test_preflight_builds_only_the_disk_script_in_the_live_store(self):
        data = [dict(d) for d in disks()]
        data[1]["size"] = 1024 ** 4
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            with patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
                 patch.object(main, "device_key", return_value="8:16"), patch.object(main, "notice"), \
                 patch.object(main, "build") as build, patch.object(main, "run") as run:
                main.preflight_stage(work, work, manifest())
            self.assertEqual([call.args[2] for call in build.call_args_list], ["system.build.diskoScript"])
            self.assertIsNone(build.call_args.kwargs.get("store"))
            run.assert_not_called()  # no closure-size query, no toplevel build
            self.assertEqual(main.last_stage(work), "prebuilt")

    def test_target_build_command_keeps_everything_on_the_target(self):
        argv = main.build_command(Path("/w/repository"), "falcon", "system.build.toplevel",
                                  Path("/w/toplevel"), main.target_store())
        self.assertEqual(argv[argv.index("--store") + 1], "/mnt")
        self.assertEqual(argv[argv.index("--extra-substituters") + 1], "auto?trusted=1")
        option = argv.index("--option")
        self.assertEqual(argv[option + 1:option + 3], ["build-dir", "/mnt/nix/var/nix/builds"])
        self.assertIn("-L", argv)
        self.assertEqual(argv[-1], "/w/repository#nixosConfigurations.falcon.config.system.build.toplevel")
        live = main.build_command(Path("/w/repository"), "falcon", "system.build.diskoScript", Path("/w/diskoScript"))
        self.assertNotIn("--store", live)

    def run_main(self, argv):
        # Patch print, not notice(), so the persistent log is still written.
        with patch.object(sys, "argv", ["run-installer", *argv]), patch.object(main.os, "umask"), \
             patch("builtins.print") as said:
            code = main.main()
        return code, [str(call.args[0]) for call in said.call_args_list if call.args]

    def test_resume_reverifies_repository_and_aborts_on_incompatible_api(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "repository").mkdir()
            with patch.object(main, "pick_workspace", return_value=work), \
                 patch.object(main, "load_session", return_value={"revision": "a" * 40, "manifest": None, "history": True}), \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(0, "a" * 40 + "\n")), \
                 patch.object(main, "verify_repo", side_effect=ValueError("incompatible with this installer API")) as verify, \
                 patch.object(main, "nix_eval") as evaluated:
                code, said = self.run_main(["--resume"])
            self.assertEqual(code, 1)
            verify.assert_called_once_with(work / "repository", "a" * 40, True)
            evaluated.assert_not_called()
            self.assertTrue(any("incompatible" in line for line in said))
            self.assertFalse(any("Formatting had started" in line for line in said))

    def test_resume_refuses_a_moved_head(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "repository").mkdir()
            with patch.object(main, "pick_workspace", return_value=work), \
                 patch.object(main, "load_session", return_value={"revision": "a" * 40, "manifest": None, "history": True}), \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(0, "b" * 40 + "\n")), \
                 patch.object(main, "verify_repo") as verify:
                code, said = self.run_main(["--resume"])
            self.assertEqual(code, 1)
            verify.assert_not_called()
            self.assertTrue(any("no longer matches the saved revision" in line for line in said))

    def test_failure_stop_relocks_and_reports_log_without_secret_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "repository" / ".git").mkdir(parents=True)
            (work / ".prepared").touch()
            secret = OSError(13, "Permission denied", "/secret/age-identity-path")
            with patch.object(main, "pick_workspace", return_value=work), \
                 patch.object(main, "load_session", return_value={"revision": "c" * 64, "manifest": None, "history": False}), \
                 patch.object(main, "verify_repo", side_effect=secret), \
                 patch.object(main, "relock") as relock:
                code, said = self.run_main(["--resume"])
            self.assertEqual(code, 1)
            relock.assert_called_once_with(work / "repository")
            log = work / "installer.log"
            self.assertEqual(log.stat().st_mode & 0o777, 0o600)
            self.assertIn(f"Log: {log}", said)
            self.assertIn(f"Copy it off this machine with: scp {log} user@host:", said)
            self.assertIn("Continue later with: run-installer --resume", said)
            self.assertIn("Permission denied", log.read_text())
            self.assertNotIn("/secret/age-identity-path", log.read_text())
            self.assertIsNone(main.LOG)

    def test_cleanup_steps_run_even_when_one_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repository"
            (repo / ".git" / "git-crypt" / "keys").mkdir(parents=True)
            order = []
            lock = main.lock_workspace(Path(tmp))
            with patch.object(main.shutil, "rmtree", side_effect=lambda p: (order.append("cache"), (_ for _ in ()).throw(OSError(1, "busy")))), \
                 patch.object(main, "relock", side_effect=lambda r: (order.append("relock"), (_ for _ in ()).throw(RuntimeError("git failed")))), \
                 patch.object(main, "notice"):
                main.cleanup(repo, lock)
            self.assertEqual(order, ["cache", "relock"])
            with self.assertRaises(OSError):
                os.close(lock)  # already closed by cleanup

    def test_sigint_exit_code_interrupts(self):
        import signal
        with patch.object(main.os, "open", return_value=99), patch.object(main.os, "close"), \
             patch.object(main.subprocess, "run", return_value=subprocess_result(-signal.SIGINT)):
            with self.assertRaises(KeyboardInterrupt) as exc:
                main.run_interactive(["bash", "-c", "read"])
        self.assertNotIsInstance(exc.exception, main.Cancelled)

    def test_ask_file_gives_up_on_a_dead_terminal(self):
        with patch.object(main, "ask_path", side_effect=main.Cancelled), \
             patch.object(main, "confirm", side_effect=main.Cancelled), patch.object(main, "notice"):
            with self.assertRaisesRegex(RuntimeError, "terminal may be gone"):
                main.ask_file("Key")

    def test_enroll_gives_up_on_a_dead_terminal(self):
        with patch.object(main, "run", return_value=""), \
             patch.object(main, "confirm", side_effect=main.Cancelled), patch.object(main, "notice"):
            with self.assertRaisesRegex(RuntimeError, "terminal may be gone. Stopped after formatting"):
                main.enroll(manifest() | {"encrypted": True}, "/dev/test", None)
        m = manifest() | {"encrypted": True, "fido2": True}
        with patch.object(main, "run", side_effect=["", RuntimeError("failed")]), \
             patch.object(main, "confirm", return_value=True), \
             patch.object(main, "choose", side_effect=main.Cancelled), patch.object(main, "notice"):
            with self.assertRaisesRegex(RuntimeError, "terminal may be gone"):
                main.enroll(m, "/dev/test", "/dev/hidraw0")

    def test_enroll_token_reselection_failure_returns_to_the_choice(self):
        m = manifest() | {"encrypted": True, "fido2": True}
        with patch.object(main, "run", side_effect=["", RuntimeError("failed"), ""]) as run, \
             patch.object(main, "confirm", return_value=True), \
             patch.object(main, "choose", side_effect=["Retry", "Retry", "Retry"]) as picked, \
             patch.object(main, "select_fido", side_effect=[ValueError("No compatible FIDO2"), main.Cancelled, "/dev/hidraw1"]), \
             patch.object(main, "notice"):
            main.enroll(m, "/dev/test", "/dev/hidraw0")
        self.assertTrue(m["fido2"])
        self.assertEqual(picked.call_count, 3)
        self.assertIn("--fido2-device=/dev/hidraw1", run.call_args.args[0])

    def test_signing_diagnostics_report_found_card_fingerprints(self):
        other = "F" * 40
        listing = (f"sec:u:255:22:{'1' * 16}:1:::::::::\nfpr:::::::::{main.PRIMARY}:\n"
                   f"ssb:u:255:22:{'2' * 16}:1::::::s:::D2760001240100000006:\nfpr:::::::::{other}:\n")
        public = f"pub:u:\nfpr:::::::::{main.PRIMARY}:\nfpr:::::::::{main.SIGNING}:\nuid:u::::::::Name:\n"

        def fake_run(args, **kwargs):
            if "show-only" in args:
                return public
            if "--list-secret-keys" in args:
                return listing
            return ""

        with tempfile.TemporaryDirectory() as tmp, patch.object(main, "run", side_effect=fake_run), \
             patch.object(main.subprocess, "run", return_value=subprocess_result(0)):
            with self.assertRaises(ValueError) as exc:
                main.fetch_public(Path(tmp))
        self.assertIn(f"Expected {main.SIGNING}", str(exc.exception))
        self.assertIn(other, str(exc.exception))
        self.assertNotIn("D2760001240100000006", str(exc.exception))

        def no_card(args, **kwargs):
            if "--card-status" in args:
                raise RuntimeError("gpg failed (exit 2)")
            return fake_run(args, **kwargs)

        with tempfile.TemporaryDirectory() as tmp, patch.object(main, "run", side_effect=no_card), \
             patch.object(main.subprocess, "run", return_value=subprocess_result(0)):
            with self.assertRaisesRegex(ValueError, "No OpenPGP smartcard detected"):
                main.fetch_public(Path(tmp))

    def test_failed_command_stderr_goes_to_the_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "installer.log"
            with patch.object(main, "LOG", log), patch("builtins.print"), \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(1)):
                with self.assertRaises(RuntimeError):
                    main.run(["nix", "eval"], show_errors=True)
                with self.assertRaises(RuntimeError):
                    main.run(["git-crypt", "unlock", "/secret/key"])  # hidden diagnostics stay hidden
            self.assertEqual(log.read_text(), "secret diagnostic\n")

    def test_log_line_survives_unencodable_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "installer.log"
            with patch.object(main, "LOG", log):
                main.log_line("bad \udcff surrogate")
                main.log_line("next")
            text = log.read_text(encoding="utf-8")
            self.assertIn("bad ? surrogate", text)
            self.assertIn("next", text)

    def test_clean_log_line_strips_progress_and_colour(self):
        self.assertEqual(main.clean_log_line(b"\x1b[1mcopying\x1b[0m 1/9\rcopying 9/9\n"), "copying 9/9")
        self.assertEqual(main.clean_log_line("error: \x1b[31mboom\x1b[0m\n"), "error: boom")

    def test_tee_stream_keeps_only_the_tail(self):
        source = io.BytesIO(b"".join(f"line {i}\n".encode() for i in range(1000)))
        sink = io.StringIO()
        kept = main.tee_stream(source, sink, limit=100)
        self.assertEqual(sink.getvalue().count("\n"), 1000)  # the terminal sees everything
        self.assertTrue(kept[0].startswith("[earlier output dropped"))
        self.assertEqual(kept[-1], "line 999")
        self.assertLessEqual(sum(len(line) + 1 for line in kept[1:]), 100)

    def test_teed_nix_stderr_reaches_terminal_and_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "installer.log"
            err = io.StringIO()
            script = "printf '{\"x\": 1}'; printf 'evaluating\\rerror: attribute missing\\n' >&2; exit 1"
            with patch.object(main, "LOG", log), patch.object(main.sys, "stderr", err):
                with self.assertRaisesRegex(RuntimeError, "sh failed \\(exit 1\\)"):
                    main.run(["sh", "-c", script], tee=True)
                self.assertEqual(main.run(["sh", "-c", "printf '{\"x\": 1}'; echo progress >&2"], tee=True), '{"x": 1}')
            self.assertIn("error: attribute missing", err.getvalue())
            text = log.read_text()
            self.assertIn("--- sh output ---\nerror: attribute missing", text)
            self.assertNotIn("evaluating", text)
            self.assertIn("progress", text)

    def test_nix_commands_tee_but_private_runs_never_do(self):
        with patch.object(main, "run", return_value="1") as run:
            main.nix_eval(Path("/repo"), "installerApi")
            self.assertTrue(run.call_args.kwargs["tee"])
        with tempfile.TemporaryDirectory() as tmp, patch.object(main, "LOG", Path(tmp) / "installer.log"), \
             patch.object(main, "run_teed") as teed, patch.object(main.os, "open", return_value=99), \
             patch.object(main.os, "close"), patch.object(main.subprocess, "run", return_value=subprocess_result(0)):
            main.run(["systemd-cryptenroll", "--recovery-key"], capture=False, private=True, tee=True)
            teed.assert_not_called()

    def test_retry_after_install_failure_reruns_preflight(self):
        args = type("Args", (), {"dry_run": False})()
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            calls = []
            with patch.object(main, "relock") as relock, patch.object(main, "reset_generated"), \
                 patch.object(main, "reset_all_generated"), patch.object(main, "ram_gib", return_value=16), \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(0)), \
                 patch.object(main, "scan_hardware", return_value="hw"), \
                 patch.object(main, "install_environment_ok", return_value=True), \
                 patch.object(main, "prepare_runtime", return_value=work / "private"), \
                 patch.object(main, "generate_stage", return_value=work / "host"), \
                 patch.object(main, "preflight_stage", side_effect=lambda *a: calls.append("preflight") or (("8:16",), None)), \
                 patch.object(main, "execute_install", side_effect=[RuntimeError("nixos-install failed (exit 1)"), None]) as install, \
                 patch.object(main, "choose", return_value="Retry"), patch.object(main, "notice"), \
                 patch.object(main, "save_session"):
                main.pipeline(args, work, work / "repository", "a" * 40, [], manifest(), True)
            relock.assert_called_once_with(work / "repository")
            self.assertEqual(calls, ["preflight", "preflight"])
            self.assertEqual(install.call_count, 2)

    @staticmethod
    def next_luks(left):
        value = left.pop(0) if len(left) > 1 else left[0]
        if isinstance(value, Exception):
            raise value
        return value

    def run_execute_install(self, tmp, m, nixos_install_fails=0, choices=(), luks=("/dev/sdb2",), umask_log=None):
        """execute_install with every external effect faked; TARGET is a temporary directory."""
        data = disks()
        identity = check_target(data, "8:16", {"8:1"}, set())
        events = []
        root = Path(tmp)
        work, host, repo, target = root / "work", root / "repository" / "hosts" / m["hostname"], root / "repository", root / "mnt"
        work.mkdir()
        (work / "stages.log").write_text("workspace-created\n")
        host.mkdir(parents=True)
        (root / "private").mkdir()
        failures = [nixos_install_fails]
        luks_left = list(luks)

        def fake_build(repo_, hostname, attribute, work_, store=None, link_name=None):
            events.append(("build", attribute, store))
            return Path("/nix/store/" + "s" * 32 + "-nixos-system")

        def fake_run(args, **kwargs):
            name = Path(str(args[0])).name
            if umask_log is not None and name in ("diskoScript", "nixos-install"):
                umask_log.append((name, kwargs.get("umask")))
            if name == "diskoScript":
                events.append(("disko",))
            elif name == "nixos-generate-config":
                events.append(("hardware",))
                return "{ }"
            elif name == "cryptsetup":
                events.append(("cryptsetup",))
            elif name == "systemd-cryptenroll":
                events.append(("cryptenroll", str(args[0])))
            elif name == "nixos-install":
                events.append(("nixos-install", str(args[args.index("--system") + 1])))
                if failures[0]:
                    failures[0] -= 1
                    raise RuntimeError("nixos-install failed (exit 1)")
            return ""

        with patch.object(main, "install_environment_ok", return_value=True), \
             patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
             patch.object(main, "device_key", return_value="8:16"), \
             patch.object(main, "ask", return_value=main.ERASE_PHRASE), \
             patch.object(main, "secret_twice", return_value="pw"), \
             patch.object(main, "confirm", return_value=True), \
             patch.object(main, "luks_backing_device",
                          side_effect=lambda *a: events.append(("resolve",)) or self.next_luks(luks_left)), \
             patch.object(main, "choose", side_effect=list(choices)) as picked, \
             patch.object(main, "progress", side_effect=lambda w, s: events.append(("stage", s))), \
             patch.object(main, "last_stage", return_value="target-prepared"), \
             patch.object(main, "run", side_effect=fake_run), patch.object(main, "build", side_effect=fake_build), \
             patch.object(main, "stage_files", side_effect=lambda r, files: events.append(("stage_files",))), \
             patch.object(main, "copy_install_repository", side_effect=lambda r, t: t.mkdir(parents=True)), \
             patch.object(main.shutil, "chown"), patch.object(main, "TARGET", target), \
             patch.object(main, "notice"):
            try:
                main.execute_install(repo, host, m, work, root / "private", None, None, "/dev/hidraw0", identity,
                                     "/nix/store/" + "y" * 32 + "-systemd/bin/systemd-cryptenroll")
                error = None
            except RuntimeError as exc:
                error = exc
        return events, error, picked

    def test_system_is_built_on_the_target_only_after_formatting(self):
        with tempfile.TemporaryDirectory() as tmp:
            events, error, _ = self.run_execute_install(tmp, manifest())
        self.assertIsNone(error)
        order = [e[0] if e[0] != "stage" else e[1] for e in events]
        self.assertEqual(order[:order.index("build")], ["formatting-started", "disko", "formatted-and-mounted",
                                                       "hardware", "stage_files", "hardware-configured",
                                                       "target-prepared"])
        self.assertEqual(events[order.index("build")], ("build", "system.build.toplevel", str(Path(tmp) / "mnt")))
        self.assertEqual(order[order.index("build") + 1:order.index("build") + 4],
                         ["final-system-built", "nixos-install", "system-installed"])
        self.assertEqual(order[-1], "installed")

    def test_fix_mount_modes_makes_mount_roots_traversable(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "mnt"
            for sub in ("", "nix", "home", "boot"):
                (target / sub).mkdir(parents=True, exist_ok=True)
                os.chmod(target / sub, 0o700)
            with patch.object(main, "TARGET", target):
                main.fix_mount_modes()
            self.assertEqual(stat.S_IMODE((target).stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE((target / "nix").stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE((target / "home").stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE((target / "boot").stat().st_mode), 0o700)

    def test_fix_mount_modes_skips_symlinks_and_missing_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "mnt"
            elsewhere = Path(tmp) / "elsewhere"
            target.mkdir()
            elsewhere.mkdir()
            os.chmod(elsewhere, 0o700)
            (target / "nix").symlink_to(elsewhere)
            with patch.object(main, "TARGET", target):
                main.fix_mount_modes()
            self.assertEqual(stat.S_IMODE(elsewhere.stat().st_mode), 0o700)

    def test_disko_and_nixos_install_run_with_umask_022_and_modes_are_fixed(self):
        calls = []
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(main, "fix_mount_modes", side_effect=lambda: calls.append("fix")):
                events, error, _ = self.run_execute_install(tmp, manifest(), umask_log=calls)
        self.assertIsNone(error)
        self.assertEqual([c for c in calls if c != "fix"], [("diskoScript", 0o022), ("nixos-install", 0o022)])
        self.assertEqual(calls.count("fix"), 2)
        self.assertLess(calls.index(("diskoScript", 0o022)), calls.index("fix"))

    def test_encrypted_install_enrolls_with_the_prebuilt_target_systemd_before_building(self):
        m = manifest() | {"encrypted": True, "fido2": True}
        with tempfile.TemporaryDirectory() as tmp:
            events, error, _ = self.run_execute_install(tmp, m)
        self.assertIsNone(error)
        order = [e[0] if e[0] != "stage" else e[1] for e in events]
        self.assertLess(order.index("formatted-and-mounted"), order.index("cryptenroll"))
        self.assertLess(order.index("cryptenroll"), order.index("hardware"))
        self.assertLess(order.index("hardware"), order.index("build"))
        self.assertTrue(all(e[1].startswith("/nix/store/" + "y" * 32) for e in events if e[0] == "cryptenroll"))

    def test_post_format_build_retry_never_reformats(self):
        with tempfile.TemporaryDirectory() as tmp:
            events, error, picked = self.run_execute_install(tmp, manifest(), nixos_install_fails=1,
                                                             choices=["Retry build"])
        self.assertIsNone(error)
        self.assertEqual([e[0] for e in events].count("disko"), 1)
        self.assertEqual([e[0] for e in events].count("build"), 2)
        self.assertEqual([e[0] for e in events].count("nixos-install"), 2)
        self.assertEqual(picked.call_args.args[1], ["Retry build", "Stop"])

    def test_post_format_build_stop_raises(self):
        with tempfile.TemporaryDirectory() as tmp:
            events, error, _ = self.run_execute_install(tmp, manifest(), nixos_install_fails=1, choices=["Stop"])
        self.assertRegex(str(error), "Stopped after formatting")
        self.assertEqual([e[0] for e in events].count("disko"), 1)
        self.assertNotIn(("stage", "system-installed"), events)

    def test_post_format_build_prompt_is_capped(self):
        with tempfile.TemporaryDirectory() as tmp:
            events, error, _ = self.run_execute_install(tmp, manifest(), nixos_install_fails=1,
                                                        choices=[main.Cancelled] * main.CANCEL_LIMIT)
        self.assertRegex(str(error), "terminal may be gone")

    def test_encrypted_install_requires_a_prebuilt_cryptenroll(self):
        with patch.object(main, "install_environment_ok", return_value=True), patch.object(main, "run") as run:
            with self.assertRaisesRegex(ValueError, "cryptenroll was not prepared"):
                main.execute_install(Path("/repo"), Path("/repo/host"), manifest() | {"encrypted": True}, Path("/work"),
                                     Path("/private"), None, None, None, ("x",))
            run.assert_not_called()

    def test_target_build_dirs_get_exact_modes_and_are_removed_narrowly(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(main, "TARGET", Path(tmp) / "mnt"):
            (Path(tmp) / "mnt").mkdir()
            old = os.umask(0o077)
            try:
                env = main.target_build_env()
            finally:
                os.umask(old)
            for path in (Path(tmp) / "mnt" / "nix", Path(tmp) / "mnt" / "nix" / "var",
                         Path(tmp) / "mnt" / "nix" / "var" / "nix", main.target_build_dir()):
                self.assertEqual(path.stat().st_mode & 0o777, 0o755, path)
            self.assertEqual(main.target_tmp_dir().stat().st_mode & 0o777, 0o700)
            self.assertEqual(env["TMPDIR"], str(main.target_tmp_dir()))
            keep = Path(tmp) / "mnt" / "nix" / "var" / "nix" / "db"
            keep.mkdir()
            with patch.object(main, "notice"):
                main.remove_target_temp_dirs()
            self.assertFalse(main.target_build_dir().exists())
            self.assertFalse(main.target_tmp_dir().exists())
            self.assertTrue(keep.is_dir())
            outside = Path(tmp) / "outside"
            outside.mkdir()
            main.target_build_dir().symlink_to(outside)
            with patch.object(main, "notice"):
                main.remove_target_temp_dirs()
            self.assertTrue(outside.is_dir())

    def test_target_build_runs_with_umask_022_and_tee(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(main, "TARGET", Path(tmp) / "mnt"):
            (Path(tmp) / "mnt").mkdir()
            link = Path(tmp) / "toplevel"
            link.symlink_to("/nix/store/" + "s" * 32 + "-system")
            with patch.object(main, "run") as run, patch.object(main, "notice"):
                result = main.build(Path("/repo"), "falcon", "system.build.toplevel", Path(tmp), store=main.target_store())
            self.assertEqual(result, Path("/nix/store/" + "s" * 32 + "-system"))
            self.assertEqual(run.call_args.kwargs["umask"], 0o022)
            self.assertTrue(run.call_args.kwargs["tee"])
            self.assertEqual(run.call_args.kwargs["env"]["TMPDIR"], str(main.target_tmp_dir()))

    def test_umask_applies_to_the_child_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            old = os.umask(0o077)
            try:
                main.run(["sh", "-c", f"umask > {tmp}/mask"], umask=0o022)
                self.assertEqual(os.umask(0o077), 0o077)
            finally:
                os.umask(old)
            self.assertEqual((Path(tmp) / "mask").read_text().strip(), "0022")

    def test_recovery_text_depends_on_stage(self):
        repo, work = Path("/var/tmp/w/repository"), Path("/var/tmp/w")
        early = "\n".join(main.recovery_commands(repo, "falcon", work, "formatted-and-mounted"))
        self.assertIn("nixos-generate-config --root /mnt --no-filesystems --show-hardware-config > "
                      "/var/tmp/w/repository/hosts/falcon/hardware-configuration.nix", early)
        self.assertIn("git -C /var/tmp/w/repository add hosts/falcon", early)
        self.assertIn("mkdir -m 0755 -p /mnt/nix/var/nix/builds", early)
        self.assertIn("(umask 022; TMPDIR=/mnt/nix/var/nix/installer-tmp nix build", early)
        self.assertIn("copying the repository", early)
        late = "\n".join(main.recovery_commands(repo, "falcon", work, "final-system-built"))
        self.assertNotIn("nixos-generate-config", late)
        self.assertNotIn("copying the repository to", late)
        self.assertIn("group ownership", late)
        for text in (early, late):
            self.assertNotIn("pw", text.replace("passwd", ""))

    def test_final_message_follows_last_stage(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            for stage, expected in (("installed", "Installation finished but a final step failed"),
                                    ("system-installed", "The system is installed and bootable"),
                                    ("target-prepared", "Disk is formatted but the build/install did not finish")):
                (work / "stages.log").write_text(f"formatting-started\n{stage}\n")
                with patch.object(main, "notice") as said:
                    main.formatted_hint(work, work / "repository", manifest())
                self.assertIn(expected, said.call_args_list[0].args[0])

    def test_eof_at_a_secret_prompt_is_cancelled_and_never_confirms_erasure(self):
        with patch.object(main.getpass, "getpass", side_effect=EOFError):
            with self.assertRaises(main.Cancelled):
                main.secret_twice("Password")
        data = disks()
        identity = check_target(data, "8:16", {"8:1"}, set())
        with patch.object(main, "install_environment_ok", return_value=True), \
             patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
             patch.object(main, "device_key", return_value="8:16"), patch.object(main, "ask", return_value=main.ERASE_PHRASE), \
             patch.object(main.getpass, "getpass", side_effect=EOFError), \
             patch.object(main, "progress") as progress, patch.object(main, "run", return_value="") as run, \
             patch.object(main, "notice"):
            with self.assertRaises(KeyboardInterrupt):
                main.execute_install(Path("/test"), Path("/test/host"), manifest(), Path("/work"), Path("/private"),
                                     None, None, None, identity)
        progress.assert_not_called()
        self.assertEqual([call.args[0][0] for call in run.call_args_list], ["lsblk"])

    def test_cryptenroll_missing_binary_returns_to_the_choice(self):
        m = manifest() | {"encrypted": True, "fido2": True}
        with patch.object(main, "run", side_effect=["", FileNotFoundError(2, "No such file")]), \
             patch.object(main, "confirm", return_value=True), \
             patch.object(main, "choose", return_value="Continue passphrase + recovery only") as picked, \
             patch.object(main, "notice"):
            main.enroll(m, "/dev/test", "/dev/hidraw0", "/nix/store/x/bin/systemd-cryptenroll")
        self.assertFalse(m["fido2"])
        picked.assert_called_once()

    def test_preflight_builds_target_systemd_only_when_encrypted(self):
        data = [dict(d) for d in disks()]
        data[1]["size"] = 1024 ** 4
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            for encrypted in (False, True):
                with patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
                     patch.object(main, "device_key", return_value="8:16"), patch.object(main, "notice"), \
                     patch.object(main, "build"), \
                     patch.object(main, "run", return_value="/nix/store/" + "y" * 32 + "-systemd\n") as run:
                    _, cryptenroll = main.preflight_stage(work, work, manifest() | {"encrypted": encrypted})
                if encrypted:
                    self.assertEqual(cryptenroll, "/nix/store/" + "y" * 32 + "-systemd/bin/systemd-cryptenroll")
                    argv = run.call_args.args[0]
                    self.assertIn("--print-out-paths", argv)
                    self.assertTrue(argv[-1].endswith("#nixosConfigurations.test-falcon.config.systemd.package^out"))
                else:
                    self.assertIsNone(cryptenroll)
                    run.assert_not_called()

    def test_failure_after_formatting_offers_no_retry_and_prints_recovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "repository" / ".git").mkdir(parents=True)
            (work / "stages.log").write_text("workspace-created\nformatting-started\nformatted-and-mounted\n")

            def failing_stage():
                raise RuntimeError("nix failed (exit 1)")

            with patch.object(main, "choose") as pick, patch.object(main, "notice"):
                with self.assertRaises(RuntimeError):
                    main.attempt(work, "Build and install", failing_stage)
                pick.assert_not_called()
            with patch.object(main.tempfile, "mkdtemp", return_value=str(work)), \
                 patch.object(main, "prepare", return_value=(work / "repository", "a" * 40, True)), \
                 patch.object(main, "nix_eval", side_effect=RuntimeError("nix failed (exit 1)")), \
                 patch.object(main, "relock"):
                code, said = self.run_main([])
            self.assertEqual(code, 1)
            text = "\n".join(said)
            self.assertIn("Disk is formatted but the build/install did not finish", text)
            self.assertIn("Do NOT rerun the installer's formatting", text)
            self.assertIn("--store /mnt", text)
            self.assertIn("nixos-install --root /mnt --system", text)
            self.assertNotIn("run-installer --resume", text)
            self.assertNotIn("Retry", text)
            self.assertIn("Disk is formatted but the build/install did not finish", (work / "installer.log").read_text())

    def test_cancelled_disk_confirmation_aborts_before_formatting(self):
        data = disks()
        identity = check_target(data, "8:16", {"8:1"}, set())
        with patch.object(main, "install_environment_ok", return_value=True), \
             patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
             patch.object(main, "device_key", return_value="8:16"), patch.object(main, "ask", side_effect=main.Cancelled), \
             patch.object(main, "progress") as progress, patch.object(main, "run", return_value="") as run, \
             patch.object(main, "notice"):
            with self.assertRaises(KeyboardInterrupt):
                main.execute_install(Path("/test"), Path("/test/host"), manifest(), Path("/work"), Path("/private"), None, None, None, identity)
        progress.assert_not_called()
        self.assertEqual([call.args[0][0] for call in run.call_args_list], ["lsblk"])

    def erase_with(self, answer):
        """execute_install up to the erase prompt; returns (error, progress mock, notice/ask order)."""
        data = disks()
        identity = check_target(data, "8:16", {"8:1"}, set())
        order = []
        ask = {"side_effect": answer} if isinstance(answer, type) or isinstance(answer, Exception) \
            else {"side_effect": lambda title: order.append(("ask", title)) or answer}
        with patch.object(main, "install_environment_ok", return_value=True), \
             patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
             patch.object(main, "device_key", return_value="8:16"), patch.object(main, "ask", **ask), \
             patch.object(main, "secret_twice", side_effect=main.Cancelled), \
             patch.object(main, "progress") as progress, patch.object(main, "run", return_value="") as run, \
             patch.object(main, "notice", side_effect=lambda text: order.append(("notice", text))):
            try:
                main.execute_install(Path("/test"), Path("/test/host"), manifest(), Path("/work"), Path("/private"),
                                     None, None, None, identity)
                error = None
            except (ValueError, KeyboardInterrupt) as exc:
                error = exc
        self.assertEqual([call.args[0][0] for call in run.call_args_list], ["lsblk"])
        return error, progress, order

    def test_erase_needs_the_exact_phrase(self):
        error, progress, order = self.erase_with("  " + main.ERASE_PHRASE + "\n")
        # The phrase passed; the next prompt (password) was cancelled, still before formatting.
        self.assertIsInstance(error, main.Cancelled)
        progress.assert_not_called()
        asked = [i for i, e in enumerate(order) if e[0] == "ask"][0]
        self.assertIn(main.ERASE_PHRASE, order[asked][1])
        before = [e[1] for e in order[:asked] if e[0] == "notice"]
        self.assertIn("ALL partitions and data on this disk will be destroyed.", before)
        self.assertTrue(any(manifest()["disk"] in text for text in before))

    def test_erase_rejects_anything_but_the_phrase(self):
        for answer in ("", manifest()["disk"], "yes", main.ERASE_PHRASE.lower(), main.ERASE_PHRASE[:-1],
                       main.Cancelled, EOFError(), KeyboardInterrupt):
            error, progress, _ = self.erase_with(answer)
            self.assertIsNotNone(error, answer)
            if isinstance(error, ValueError):
                self.assertRegex(str(error), "Erase confirmation did not match")
            progress.assert_not_called()

    def test_block_device_rejects_invalid_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            regular = Path(tmp) / "file"
            regular.write_text("")
            for value in ("", "/dev/", "/dev", "sdb2", "/dev/does-not-exist-icy", str(regular), "/dev/null",
                          "/dev/sda\n/dev/sdb"):
                self.assertIsNone(main.block_device(value), value)
        with patch.object(main.os, "stat", return_value=os.stat_result((stat.S_IFBLK | 0o660,) + (0,) * 9)):
            self.assertEqual(main.block_device("/dev/sdb2"), "/dev/sdb2")

    def test_luks_device_prefers_partuuid_and_cross_checks_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            host = Path(tmp)
            (host / "storage.json").write_text(json.dumps({"partitionUUIDs": {"root": "u-1"}}))
            status = subprocess_result(0, "  type:    LUKS2\n  device:  /dev/sdb2\n")
            blocks = {"/dev/sdb2", "/dev/sdc2"}
            with patch.object(main, "block_device", side_effect=lambda p: p.strip() if p.strip() in blocks else None), \
                 patch.object(main.os.path, "realpath", side_effect=lambda p: "/dev/sdb2" if "by-partuuid" in p else p), \
                 patch.object(main.subprocess, "run", return_value=status), patch.object(main, "run") as run:
                self.assertEqual(main.luks_backing_device(manifest(), host), "/dev/sdb2")
                run.assert_not_called()
                status.stdout = "  device:  /dev/sdc2\n"
                with self.assertRaisesRegex(ValueError, "disagree"):
                    main.luks_backing_device(manifest(), host)
            # No by-partuuid and no status: lsblk --paths is the fallback; '/dev/' alone is rejected.
            (host / "storage.json").unlink()
            with patch.object(main, "block_device", side_effect=lambda p: p if p in blocks else None), \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(1)), \
                 patch.object(main, "run", return_value="/dev/sdc2\n") as run:
                self.assertEqual(main.luks_backing_device(manifest(), host), "/dev/sdc2")
                self.assertIn("--paths", run.call_args.args[0])
                run.return_value = "/dev/\n"
                with self.assertRaisesRegex(ValueError, "Cannot identify the LUKS partition"):
                    main.luks_backing_device(manifest(), host)

    def test_luks_check_retries_without_reformatting(self):
        m = manifest() | {"encrypted": True, "fido2": False}
        with tempfile.TemporaryDirectory() as tmp:
            events, error, picked = self.run_execute_install(
                tmp, m, choices=["Retry"], luks=[ValueError("Cannot identify the LUKS partition"), "/dev/sdb2"])
        self.assertIsNone(error)
        names = [e[0] for e in events]
        self.assertEqual(names.count("disko"), 1)
        self.assertEqual(names.count("resolve"), 2)
        self.assertEqual(names.count("cryptsetup"), 1)
        self.assertEqual(picked.call_args.args[1], ["Retry", "Stop"])
        self.assertLess(names.index("cryptsetup"), names.index("cryptenroll"))

    def test_luks_check_stop_raises_before_enrollment(self):
        m = manifest() | {"encrypted": True, "fido2": False}
        with tempfile.TemporaryDirectory() as tmp:
            events, error, _ = self.run_execute_install(tmp, m, choices=["Stop"], luks=[ValueError("bad")])
        self.assertRegex(str(error), "LUKS enrollment did not run")
        names = [e[0] for e in events]
        self.assertEqual(names.count("disko"), 1)
        self.assertNotIn("cryptenroll", names)

    def test_test_passphrase_shows_and_logs_cryptsetup_errors(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "installer.log"
            err = io.StringIO()
            failed = subprocess_result(4)
            failed.stderr = "Device /dev/ does not exist or access denied.\n"
            with patch.object(main, "LOG", log), patch.object(main.sys, "stderr", err), \
                 patch.object(main, "luks_backing_device", return_value="/dev/sdb2"), \
                 patch.object(main.subprocess, "run", return_value=failed), patch.object(main, "notice"), \
                 patch.object(main, "choose", return_value="Stop"):
                with self.assertRaisesRegex(RuntimeError, "LUKS enrollment did not run"):
                    main.check_luks(manifest(), Path(tmp), Path(tmp))
            self.assertIn("does not exist", err.getvalue())
            self.assertIn("does not exist", log.read_text())

    def test_recovery_includes_luks_enrollment_until_enrolled(self):
        m = manifest() | {"encrypted": True, "fido2": True}
        repo, work = Path("/var/tmp/w/repository"), Path("/var/tmp/w-missing")
        early = "\n".join(main.recovery_commands(repo, m["hostname"], work, "formatted-and-mounted", m))
        self.assertIn(f"cryptsetup status icy-{m['hostname']}", early)
        self.assertIn("cryptsetup open --test-passphrase --key-file", early)
        self.assertIn("systemd-cryptenroll --unlock-key-file=<that file> --recovery-key", early)
        self.assertIn("--fido2-with-client-pin=yes --fido2-with-user-presence=yes", early)
        self.assertIn("NO recovery key", early)
        late = "\n".join(main.recovery_commands(repo, m["hostname"], work, "luks-enrolled", m))
        self.assertNotIn("--recovery-key", late)
        plain = "\n".join(main.recovery_commands(repo, m["hostname"], work, "formatted-and-mounted",
                                                 manifest()))
        self.assertNotIn("cryptsetup", plain)
        with tempfile.TemporaryDirectory() as tmp:
            saved = "/nix/store/" + "y" * 32 + "-systemd/bin/systemd-cryptenroll"
            (Path(tmp) / "cryptenroll-path").write_text(saved + "\n")
            text = "\n".join(main.recovery_commands(repo, m["hostname"], Path(tmp), "formatted-and-mounted", m))
            self.assertIn(saved + " --unlock-key-file=<that file> --recovery-key", text)

    def test_no_resume_hint_without_prepared_workspace(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            with patch.object(main.tempfile, "mkdtemp", return_value=str(work)), \
                 patch.object(main, "prepare", side_effect=RuntimeError("clone failed")):
                code, said = self.run_main([])
            self.assertEqual(code, 1)
            self.assertIn("Nothing was formatted.", said)
            self.assertFalse(any("--resume" in line for line in said))

    def test_malformed_manifest_is_a_clean_value_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / "repository").mkdir()
            malformed = json.dumps(manifest() | {"hostname": 5})  # validate() would raise TypeError
            for content, message in (("[1, 2]", "JSON object"), (malformed, "missing or has malformed")):
                (work / "manifest.json").write_text(content)
                with self.subTest(content=content), patch.object(main, "pick_workspace", return_value=work), \
                     patch.object(main, "load_session", return_value={"revision": "a" * 40, "manifest": None, "history": False}), \
                     patch.object(main, "verify_repo"), patch.object(main, "nix_eval", return_value=[]):
                    code, said = self.run_main(["--resume", "--manifest", str(work / "manifest.json")])
                    self.assertEqual(code, 1)
                    self.assertTrue(any(message in line for line in said))

    def test_error_before_workspace_does_not_claim_formatting(self):
        with patch.object(main, "pick_workspace", side_effect=ValueError("No earlier installer workspace")):
            code, said = self.run_main(["--resume"])
        self.assertEqual(code, 1)
        self.assertIn("Stopped before a workspace was selected. Nothing was formatted.", said)
        self.assertFalse(any("Formatting had started" in line for line in said))
        with patch.object(main, "pick_workspace", side_effect=KeyboardInterrupt):
            code, said = self.run_main(["--resume"])
        self.assertIn("Stopped before a workspace was selected. Nothing was formatted.", said)
        self.assertFalse(any("formatting started" in line for line in said))

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
        with patch.object(main, "notice"), patch.object(main, "ask", side_effect=lambda t, d="": d) as asked, \
             patch.object(main, "confirm", side_effect=lambda t, d=False: d), \
             patch.object(main, "inventory", side_effect=ValueError("stop here")):
            with self.assertRaisesRegex(ValueError, "stop here"):
                with patch.object(main, "choose", return_value="Continue"):
                    main.wizard(Path("/repo"), saved["revision"], [], saved=saved)
        hostname_prompt = asked.call_args_list[0]
        self.assertIn("hostname", hostname_prompt.args[0])
        self.assertEqual(hostname_prompt.args[1], "kept-host")
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

    def test_relock_restores_ciphertext_through_an_active_filter(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self.repo_with_host(tmp)
            (repo / "secrets").mkdir()
            (repo / ".gitattributes").write_text("secrets/bookmarks-*.json filter=git-crypt diff=git-crypt\n")
            # Stand-in for git-crypt: smudge strips the magic header, clean adds it back.
            self.git(repo, "config", "filter.git-crypt.smudge", "tail -c +11")
            self.git(repo, "config", "filter.git-crypt.clean", "sh -c 'printf \"\\000GITCRYPT\\000\"; cat'")
            for name in main.BOOKMARKS:
                (repo / "secrets" / name).write_text('["plaintext"]')
            self.git(repo, "add", "-A")
            self.git(repo, "commit", "-qm", "secrets")
            for name in main.BOOKMARKS:
                (repo / "secrets" / name).unlink()
            self.git(repo, "checkout", "--", "secrets")
            self.assertEqual((repo / "secrets" / main.BOOKMARKS[0]).read_text(), '["plaintext"]')
            main.relock(repo)
            for name in main.BOOKMARKS:
                self.assertEqual((repo / "secrets" / name).read_bytes(), b"\0GITCRYPT\0" + b'["plaintext"]')
            self.assertNotIn("git-crypt", self.git(repo, "config", "--list"))

    def stat_clean_plaintext_repo(self, root):
        """Index blob = ciphertext, working file = plaintext, and git's stat cache calls it clean.

        Mirrors the real failure: after `git-crypt unlock` the index records the smudged
        plaintext's size/mtime, so `git checkout -- file` is a no-op once the filter is gone.
        """
        repo = self.repo_with_host(root)
        (repo / "secrets").mkdir()
        (repo / ".gitattributes").write_text("secrets/bookmarks-*.json filter=git-crypt diff=git-crypt\n")
        cipher = b"\0GITCRYPT\0" + b'["plaintext"]'
        (repo / "secrets" / main.BOOKMARKS[0]).write_bytes(cipher)
        self.git(repo, "add", "-A")  # no filter configured yet: stored verbatim
        self.git(repo, "commit", "-qm", "ciphertext")
        self.git(repo, "config", "filter.git-crypt.smudge", "tail -c +11")
        self.git(repo, "config", "filter.git-crypt.clean", "sh -c 'printf \"\\000GITCRYPT\\000\"; cat'")
        path = repo / "secrets" / main.BOOKMARKS[0]
        path.unlink()
        self.git(repo, "checkout", "--", "secrets")  # "unlock": smudge writes plaintext, index records its stat
        os.utime(path, (1_000_000_000, 1_000_000_000))
        self.git(repo, "update-index", "--refresh")  # clean filter matches the blob: stat cache now trusts plaintext
        time.sleep(1.1)  # avoid racy-git re-checks, like the real (delayed) run
        self.assertEqual(path.read_bytes(), b'["plaintext"]')
        self.assertEqual(self.git(repo, "cat-file", "blob", f":secrets/{main.BOOKMARKS[0]}").encode()[:10], b"\0GITCRYPT\0")
        for section in ("filter.git-crypt", "diff.git-crypt"):
            subprocess.run(["git", "config", "--remove-section", section], cwd=repo, capture_output=True)
        return repo, path, cipher

    def test_checkout_alone_leaves_stat_clean_plaintext(self):
        # Documents why relock must not rely on `git checkout --`.
        with tempfile.TemporaryDirectory() as tmp:
            repo, path, _ = self.stat_clean_plaintext_repo(tmp)
            self.git(repo, "checkout", "--", f"secrets/{main.BOOKMARKS[0]}")
            self.assertEqual(path.read_bytes(), b'["plaintext"]')

    def test_relock_restores_stat_clean_plaintext(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo, path, cipher = self.stat_clean_plaintext_repo(tmp)
            main.relock(repo)
            self.assertEqual(path.read_bytes(), cipher)
            self.assertEqual(self.git(repo, "status", "--porcelain", "--", "secrets").strip(), "")

    def test_cleanup_relocks_stat_clean_plaintext(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo, path, cipher = self.stat_clean_plaintext_repo(tmp)
            with patch.object(main, "notice"):
                main.cleanup(repo, None)
            self.assertEqual(path.read_bytes(), cipher)

    @unittest.skipUnless(shutil.which("git-crypt"), "git-crypt not on PATH; the simulated stat-clean tests cover relock")
    def test_relock_after_real_git_crypt_unlock(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            origin = root / "origin"
            origin.mkdir()
            subprocess.run(["git", "init", "-q", str(origin)], check=True)
            self.git(origin, "config", "user.name", "t")
            self.git(origin, "config", "user.email", "t@t")
            subprocess.run(["git-crypt", "init"], cwd=origin, check=True, capture_output=True)
            (origin / ".gitattributes").write_text("secrets/bookmarks-*.json filter=git-crypt diff=git-crypt\n")
            (origin / "secrets").mkdir()
            (origin / "secrets" / main.BOOKMARKS[0]).write_text('["plaintext"]')
            (origin / "hosts").mkdir()
            (origin / "hosts" / ".keep").write_text("")
            self.git(origin, "add", "-A")
            self.git(origin, "commit", "-qm", "encrypted")
            key = root / "key"
            subprocess.run(["git-crypt", "export-key", str(key)], cwd=origin, check=True)
            repo = root / "clone"
            subprocess.run(["git", "clone", "-q", str(origin), str(repo)], check=True)
            path = repo / "secrets" / main.BOOKMARKS[0]
            self.assertTrue(path.read_bytes().startswith(main.CRYPT_MAGIC))
            subprocess.run(["git-crypt", "unlock", str(key)], cwd=repo, check=True, capture_output=True)
            time.sleep(1.1)
            (repo / "hosts" / "h").mkdir()
            (repo / "hosts" / "h" / "install.json").write_text("{}")
            self.git(repo, "switch", "-qc", "hosts/h")
            self.git(repo, "add", "--", "hosts/h")
            self.git(repo, "status")
            time.sleep(1.1)
            self.assertEqual(path.read_text(), '["plaintext"]')
            shutil.rmtree(repo / ".git" / "git-crypt")  # cleanup() removes the key cache first
            main.relock(repo)
            self.assertTrue(path.read_bytes().startswith(main.CRYPT_MAGIC))

    def test_relock_refuses_plaintext_in_the_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self.repo_with_host(tmp)
            (repo / "secrets").mkdir()
            (repo / "secrets" / main.BOOKMARKS[0]).write_text('["plaintext"]')
            self.git(repo, "add", "-A")
            self.git(repo, "commit", "-qm", "plaintext")
            with self.assertRaisesRegex(ValueError, "ciphertext could not be restored"):
                main.relock(repo)

    def test_hand_copied_host_without_installer_marker_is_kept(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self.repo_with_host(tmp)
            (repo / "hosts" / "manual").mkdir()
            (repo / "hosts" / "manual" / "configuration.nix").write_text("{}")
            main.reset_all_generated(repo)
            self.assertTrue((repo / "hosts" / "manual" / "configuration.nix").exists())

    def test_stale_host_from_an_earlier_hostname_is_reset(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self.repo_with_host(tmp)
            for name in ("old-name", "new-name"):
                (repo / "hosts" / name).mkdir()
                (repo / "hosts" / name / "install.json").write_text("{}")
            self.git(repo, "add", "-A")
            main.reset_all_generated(repo)
            self.assertFalse((repo / "hosts" / "old-name").exists())
            self.assertFalse((repo / "hosts" / "new-name").exists())
            self.assertTrue((repo / "hosts" / "upstream" / "x.nix").exists())
            self.assertNotIn("old-name", self.git(repo, "ls-files"))

    def test_relock_without_personal_setup_keeps_ciphertext_and_skips_missing_bookmarks(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self.repo_with_host(tmp)
            main.relock(repo)  # snapshot without any bookmark files
            (repo / "secrets").mkdir()
            cipher = b"\0GITCRYPT\0" + b"y" * 20
            (repo / "secrets" / main.BOOKMARKS[0]).write_bytes(cipher)
            self.git(repo, "add", "-A")
            self.git(repo, "commit", "-qm", "one bookmark")
            main.relock(repo)
            self.assertEqual((repo / "secrets" / main.BOOKMARKS[0]).read_bytes(), cipher)
            self.assertFalse((repo / "secrets" / main.BOOKMARKS[1]).exists())
            self.assertEqual(self.git(repo, "status", "--porcelain").strip(), "")

    def test_resume_snapshot_revision_is_the_new_head(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = self.repo_with_host(tmp)
            (source / "flake.nix").write_text("{}")
            self.git(source, "add", "-A")
            self.git(source, "commit", "-qm", "flake")
            original = self.git(source, "rev-parse", "HEAD").strip()
            (source / "flake.nix").write_text("{ edited = true; }")  # uncommitted local change
            work = Path(tmp) / "work"
            work.mkdir()
            real_run = main.run

            def run_without_lfs(args, **kwargs):  # git-lfs is not available in the check sandbox
                return "" if list(args[:2]) == ["git", "lfs"] else real_run(args, **kwargs)

            with patch.object(main, "verify_repo") as verify, patch.object(main, "notice"), \
                 patch.object(main, "run", side_effect=run_without_lfs):
                repo, revision, history = main.prepare(work, source, update=False)
            head = self.git(repo, "rev-parse", "HEAD").strip()
            self.assertTrue(history)
            self.assertNotEqual(head, original)
            self.assertEqual(revision, head)
            self.assertEqual(verify.call_args.args, (repo, head, True))
            self.assertTrue((work / ".prepared").is_file())


def subprocess_result(code, stdout=""):
    from subprocess import CompletedProcess
    return CompletedProcess([], code, stdout=stdout, stderr="secret diagnostic")


if __name__ == "__main__":
    unittest.main()
