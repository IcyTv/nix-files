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
                                  Path("/w/toplevel"), main.TARGET_STORE)
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

    def test_retry_after_install_failure_reruns_preflight(self):
        args = type("Args", (), {"dry_run": False})()
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            calls = []
            with patch.object(main, "relock") as relock, patch.object(main, "reset_generated"), \
                 patch.object(main, "reset_all_generated"), patch.object(main, "ram_gib", return_value=16), \
                 patch.object(main.subprocess, "run", return_value=subprocess_result(0)), \
                 patch.object(main, "scan_hardware", return_value="hw"), patch.object(main.os, "geteuid", return_value=0), \
                 patch.object(Path, "exists", return_value=True), \
                 patch.object(main, "prepare_runtime", return_value=work / "private"), \
                 patch.object(main, "generate_stage", return_value=work / "host"), \
                 patch.object(main, "preflight_stage", side_effect=lambda *a: calls.append("preflight") or ("8:16",)), \
                 patch.object(main, "execute_install", side_effect=[RuntimeError("nixos-install failed (exit 1)"), None]) as install, \
                 patch.object(main, "choose", return_value="Retry"), patch.object(main, "notice"), \
                 patch.object(main, "save_session"):
                main.pipeline(args, work, work / "repository", "a" * 40, [], manifest(), True)
            relock.assert_called_once_with(work / "repository")
            self.assertEqual(calls, ["preflight", "preflight"])
            self.assertEqual(install.call_count, 2)

    def test_system_is_built_on_the_target_only_after_formatting(self):
        data = disks()
        identity = check_target(data, "8:16", {"8:1"}, set())
        events = []
        with tempfile.TemporaryDirectory() as tmp:
            work, host = Path(tmp) / "work", Path(tmp) / "host"
            work.mkdir()
            host.mkdir()

            def fake_build(repo, hostname, attribute, work_, store=None, link_name=None):
                events.append(("build", attribute, store))
                return Path("/nix/store/" + "s" * 32 + "-nixos-system")

            def fake_run(args, **kwargs):
                if args[0] == "nixos-install":
                    events.append(("nixos-install", str(args[args.index("--system") + 1])))
                    raise RuntimeError("nixos-install failed (exit 1)")
                return ""

            with patch.object(main.os, "geteuid", return_value=0), \
                 patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
                 patch.object(main, "device_key", return_value="8:16"), \
                 patch.object(main, "ask", return_value=manifest()["disk"]), \
                 patch.object(main, "secret_twice", return_value="pw"), \
                 patch.object(main, "progress", side_effect=lambda w, s: events.append(("stage", s))), \
                 patch.object(main, "run", side_effect=fake_run), patch.object(main, "build", side_effect=fake_build), \
                 patch.object(main, "stage_files"), patch.object(main, "prepare_target_parent"), \
                 patch.object(main, "copy_install_repository"), patch.object(main.shutil, "chown"), \
                 patch.object(main, "TARGET", Path(tmp) / "mnt"), \
                 patch.object(main, "REPOSITORY", "/etc/nixos/nix-files"), \
                 patch.object(main, "Path", side_effect=lambda p: Path(tmp) / str(p).lstrip("/") if str(p).startswith("/mnt") else Path(p)), \
                 patch.object(main, "notice"):
                with self.assertRaisesRegex(RuntimeError, "nixos-install failed"):
                    main.execute_install(Path("/repo"), host, manifest(), work, Path("/private"), None, None, None, identity)
        stages = [e for e in events if e[0] != "nixos-install"]
        self.assertEqual(stages, [("stage", "formatting-started"), ("stage", "formatted-and-mounted"),
                                  ("build", "system.build.toplevel", main.TARGET_STORE),
                                  ("stage", "final-system-built")])
        self.assertEqual(events[-1], ("nixos-install", "/nix/store/" + "s" * 32 + "-nixos-system"))

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
        with patch.object(main.os, "geteuid", return_value=0), patch.object(Path, "exists", return_value=True), \
             patch.object(main, "inventory", return_value=(data, {"8:1"}, set())), \
             patch.object(main, "device_key", return_value="8:16"), patch.object(main, "ask", side_effect=main.Cancelled), \
             patch.object(main, "progress") as progress, patch.object(main, "run", return_value="") as run, \
             patch.object(main, "notice"):
            with self.assertRaises(KeyboardInterrupt):
                main.execute_install(Path("/test"), Path("/test/host"), manifest(), Path("/work"), Path("/private"), None, None, None, identity)
        progress.assert_not_called()
        self.assertEqual([call.args[0][0] for call in run.call_args_list], ["lsblk"])

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
