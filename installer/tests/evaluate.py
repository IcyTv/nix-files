"""Read-only Nix proof against generated hosts in an isolated snapshot; no disk commands."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model import generate, partition_uuid, write_json
from test_installer import manifest

source = Path(__file__).resolve().parents[2]
workspace = Path(tempfile.mkdtemp(prefix="icy-eval-", dir="/tmp/opencode"))
repo = workspace / "repository"
shutil.copytree(source, repo, ignore=shutil.ignore_patterns(".git", ".opencode", "__pycache__", "result", "wallpapers", "bookmarks-default.json", "bookmarks-yes.json"))
(repo / "wallpapers").mkdir()


def evaluate(attr, apply=None):
    command = ["nix", "eval", "--offline", "--no-write-lock-file", "--json", f"path:{repo}#{attr}"]
    if apply:
        command += ["--apply", apply]
    return json.loads(subprocess.check_output(command, text=True))


schema = evaluate("installerSchema.x86_64-linux")
print(f"Discovered {len(schema)} options; all current types supported: {all(o['supported'] for o in schema)}", flush=True)
assert not any(any(p in o["path"] for p in ("core", "disko", "installer")) for o in schema)
for name, changes in [
    ("plain", {}),
    ("encrypted", {"encrypted": True}),
    ("fido", {"encrypted": True, "fido2": True}),
    ("zero-hibernate", {"swapGiB": 0, "hibernate": True}),
    ("resume", {"encrypted": True, "hibernate": True}),
    ("alternate-user", {"username": "alice"}),
    ("hardware-override", {"hardware": {"cpu": "other", "gpu": "other", "vm": "none", "laptop": False}}),
    ("preset-overrides", {"home": {"my.hm.default.enable": True, "my.hm.niri.enable": False, "my.hm.firefox.enable": True},
                          "system": {"my.nixos.stylix.enable": True}}),
]:
    m = manifest() | {"hostname": "test-" + name} | changes
    host = generate(repo, m, schema, '{lib, ...}: { nixpkgs.hostPlatform = "x86_64-linux"; boot.initrd.availableKernelModules = ["ahci"]; hardware.cpu.amd.updateMicrocode = lib.mkDefault true; }')
    if name == "resume":
        write_json(host / "resume.json", {"boot": {"resumeDevice": "/dev/mapper/icy-" + m["hostname"], "kernelParams": ["resume_offset=1234"]}})
    base = f"nixosConfigurations.{m['hostname']}.config"
    drv = evaluate(base + ".system.build.toplevel.drvPath")
    swap = evaluate(base + ".swapDevices", 'map (s: { inherit (s) device; size = s.size or null; })')
    assert all(entry["size"] is None for entry in swap)
    assert bool(swap) == (m["swapGiB"] > 0)
    assert evaluate(base + ".icy.repository") == "/etc/nixos/nix-files"
    assert set(evaluate(base + f".users.users.{m['username']}.extraGroups")) >= {"wheel", "configurators"}
    assert evaluate(base + ".disko.devices.disk.main.content.partitions.root.uuid") == partition_uuid(m, "root")
    if name == "plain":
        write_json(host / "install.json", m | {"hostname": "renamed", "revision": "b" * 40})
        assert evaluate(base + ".disko.devices.disk.main.content.partitions.root.uuid") == partition_uuid(m, "root")
        write_json(host / "install.json", m)
    if name == "alternate-user":
        assert evaluate(base + ".home-manager.users.alice.home.homeDirectory") == "/home/alice"
    if name == "hardware-override":
        assert evaluate(base + ".hardware.cpu.amd.updateMicrocode") is False
    if name == "resume":
        assert evaluate(base + ".systemd.services.systemd-hibernate.serviceConfig.ExecStartPre")
    if name == "preset-overrides":
        assert evaluate(base + ".home-manager.users.michael.my.hm.niri.enable") is False
        assert evaluate(base + ".home-manager.users.michael.age.secrets") == {}
    if m["fido2"]:
        assert "fido2-device=auto" in evaluate(base + f".boot.initrd.luks.devices.icy-{m['hostname']}.crypttabExtraOpts")
    print(f"PASS {name}: {drv}", flush=True)
print(f"Generated configurations retained for inspection: {repo}", flush=True)
