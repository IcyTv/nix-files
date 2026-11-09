"""Nonsecret installation data, validation and host generation (no disk operations)."""
import json
import hashlib
import math
import re
from pathlib import Path

API = 1
PRIMARY = "B8A3D43103569F0F76BAF11AE57AD43DEE514B7B"
SIGNING = "433D8E22007D3A9762D54780ED06A3B7C8B9C6B0"
REPOSITORY = "/etc/nixos/nix-files"


def partition_uuid(m, kind):
    h = hashlib.sha256(f"{m['hostname']}:{m['revision']}:{kind}".encode()).hexdigest()
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def check_storage_names(m):
    import os
    paths = ["/dev/disk/by-partuuid/" + partition_uuid(m, kind) for kind in ("efi", "root")]
    if m["encrypted"]:
        paths.append("/dev/mapper/icy-" + m["hostname"])
    if any(os.path.lexists(path) for path in paths):
        raise ValueError("Planned partition UUID or mapper name already exists. Use manual recovery, never automatic reformatting.")


def swap_suggestion(ram_gib, hibernate=False):
    """Whole GiB, rounded up. Above 64 GiB hibernation is workload-dependent."""
    if ram_gib <= 2:
        size = ram_gib * (3 if hibernate else 2)
    elif ram_gib <= 8:
        size = ram_gib * (2 if hibernate else 1)
    else:
        size = ram_gib * 1.5 if hibernate else 4
    return math.ceil(size)


def swap_warnings(size, ram, hibernate):
    warnings = []
    if size < swap_suggestion(ram, hibernate):
        warnings.append("Swap is below the sizing guideline; memory exhaustion or hibernation failure is possible.")
    if hibernate and size == 0:
        warnings.append("Hibernation selected with no disk swap: hibernation will not work.")
    if hibernate and ram > 64:
        warnings.append("Above 64 GiB RAM, hibernation sizing is workload-dependent and can be slow.")
    if hibernate:
        warnings.append("Hibernation depends on free swap and kernel support, not capacity alone; lockdown can prohibit it.")
    return warnings


def put(tree, path, value):
    for name in path[:-1]:
        tree = tree.setdefault(name, {})
    tree[path[-1]] = value


def validate(m, schema):
    if not isinstance(m, dict):
        raise ValueError("Manifest must be a JSON object")
    required = {"api", "revision", "hostname", "username", "disk", "encrypted", "fido2",
                "personalSecrets", "signing", "swapGiB", "hibernate", "timezone", "locale",
                "gitName", "gitEmail", "stateVersion", "system", "home", "hardware"}
    if set(m) != required or m["api"] != API:
        raise ValueError("Unexpected manifest fields or API. Credentials must never enter the manifest.")
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,62}", m["hostname"]) or m["hostname"] == "iso":
        raise ValueError("Invalid/reserved hostname")
    if not re.fullmatch(r"[a-z_][a-z0-9_-]{0,30}", m["username"]) or m["username"] in {"root", "nixos", "nobody"}:
        raise ValueError("Invalid/reserved username")
    if not re.fullmatch(r"[0-9a-f]{40,64}", m["revision"]):
        raise ValueError("Revision must be an immutable Git commit")
    if not isinstance(m["disk"], str) or not re.fullmatch(r"/dev/[A-Za-z0-9_./:+-]+", m["disk"]) or "/../" in m["disk"]:
        raise ValueError("Disk must be an absolute /dev path")
    for field in ("encrypted", "fido2", "personalSecrets", "signing", "hibernate"):
        if type(m[field]) is not bool:
            raise ValueError(f"{field} must be boolean")
    if type(m["swapGiB"]) is not int or not 0 <= m["swapGiB"] <= 1048576:
        raise ValueError("Invalid swap size")
    if (m["personalSecrets"] or m["fido2"]) and not m["encrypted"]:
        raise ValueError("Personal secrets and FIDO2 require LUKS2")
    for field in ("timezone", "locale", "gitName", "gitEmail", "stateVersion"):
        if not isinstance(m[field], str) or not m[field] or any(c in m[field] for c in "\n\r\0"):
            raise ValueError(f"Invalid {field}")
    if not re.fullmatch(r"\d\d\.\d\d", m["stateVersion"]):
        raise ValueError("Invalid initial state version")
    if not isinstance(m["hardware"], dict) or set(m["hardware"]) != {"cpu", "gpu", "vm", "laptop"}:
        raise ValueError("Invalid hardware choices")
    if m["hardware"]["cpu"] not in ("amd", "intel", "other") or m["hardware"]["gpu"] not in ("amd", "intel", "nvidia", "other"):
        raise ValueError("Invalid CPU/GPU choice")
    if m["hardware"]["vm"] not in ("none", "kvm", "oracle", "other") or type(m["hardware"]["laptop"]) is not bool:
        raise ValueError("Invalid hardware defaults")
    for scope in ("system", "home"):
        if not isinstance(m[scope], dict):
            raise ValueError("Option answers must be a map")
        available = {".".join(o["path"]): o for o in schema if o["scope"] == scope and o["writable"] and o["supported"]}
        for name, value in m[scope].items():
            if name not in available:
                raise ValueError(f"Unknown/noneditable option: {scope}:{name}")
            typ = available[name]["type"]
            valid = (type(value) is bool if typ == "bool" else isinstance(value, str) if typ == "str"
                     else isinstance(value, list) and all(isinstance(x, str) for x in value))
            if not valid:
                raise ValueError(f"Wrong type: {name}")


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def generate(repo, m, schema, hardware_text):
    """Generate once. Never overwrite an existing host, even in dry-run."""
    validate(m, schema)
    host = Path(repo) / "hosts" / m["hostname"]
    host.mkdir(mode=0o700)  # Existing hosts are user work.
    write_json(host / "install.json", m)
    # Physical identities are installation facts, not recomputed preferences.
    # Later hostname/source edits must never redirect filesystems to new UUIDs.
    write_json(host / "storage.json", {"partitionUUIDs": {kind: partition_uuid(m, kind) for kind in ("efi", "root")},
                                       "mapper": "icy-" + m["hostname"]})
    for scope in ("system", "home"):
        answers = {}
        for name, value in m[scope].items():
            put(answers, name.split("."), value)
        write_json(host / f"{scope}-options.json", answers)
    (host / "hardware-configuration.nix").write_text(hardware_text)
    write_json(host / "resume.json", {})
    for name in ("configuration.nix", "home.nix", "disk-config.nix", "hardware-options.nix"):
        (host / name).write_text((Path(__file__).parent / "templates" / name).read_text())
    return host
