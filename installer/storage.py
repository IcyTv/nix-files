"""Fail-closed target selection. Collection is read-only; validation is pure."""
import json
import os
import subprocess
from pathlib import Path


def flatten(devices):
    result = {}
    edges = {}

    def walk(node, parent=None):
        key = node["maj:min"]
        result[key] = node
        edges.setdefault(key, set())
        if parent:
            edges[key].add(parent)
            edges[parent].add(key)
        for child in node.get("children", []):
            walk(child, key)

    for device in devices:
        walk(device)
    return result, edges


def component(edges, key):
    seen, todo = set(), [key]
    while todo:
        item = todo.pop()
        if item not in seen:
            seen.add(item)
            todo.extend(edges.get(item, ()))
    return seen


def check_target(devices, key, protected, held):
    nodes, edges = flatten(devices)
    backing_disks = {k for p in protected for k in component(edges, p)
                     if k in nodes and nodes[k]["type"] in ("disk", "rom")}
    if not backing_disks:
        raise ValueError("Cannot identify mounted/boot backing devices; refusing to format")
    if key not in nodes or nodes[key]["type"] != "disk":
        raise ValueError("Target must be a whole physical/virtual disk, not a partition or mapper")
    target = nodes[key]
    if target.get("ro") or not target.get("size"):
        raise ValueError("Read-only or empty disk")
    related = component(edges, key)
    if related & protected:
        raise ValueError("Target contains a mounted filesystem, swap, or boot-medium backing device")
    if related & held:
        raise ValueError("Target has active holders or open raw-device users")
    if any(any(p for p in nodes[k].get("mountpoints", []) or []) for k in related):
        raise ValueError("Target or a related device is mounted/in use")
    if any(nodes[k].get("type") in ("crypt", "lvm", "raid0", "raid1", "raid5", "raid6", "raid10", "mpath") for k in related):
        raise ValueError("Active layered storage on target")
    return tuple(target.get(k) for k in ("maj:min", "size", "serial", "wwn", "name"))


def raw_device_open(path):
    # psmisc fuser's parser does not accept a standalone '--' separator.
    # Inventory supplies absolute /dev paths, never option-shaped input.
    result = subprocess.run(["fuser", "-s", path], capture_output=True)
    if result.returncode not in (0, 1) or result.stderr:
        raise ValueError("Cannot prove target devices have no raw-device users")
    return result.returncode == 0


def inventory(run):
    data = json.loads(run(["lsblk", "--json", "--paths", "--bytes", "--output",
                           "NAME,TYPE,SIZE,MODEL,SERIAL,WWN,RO,MOUNTPOINTS,MAJ:MIN"]))["blockdevices"]
    nodes, _ = flatten(data)
    mounts = json.loads(run(["findmnt", "--json", "--list", "--output", "SOURCE,TARGET,MAJ:MIN"]))["filesystems"]
    if any(m["target"] == "/mnt" or m["target"].startswith("/mnt/") for m in mounts):
        raise ValueError("/mnt is already in use; manual recovery is required, not automatic formatting")
    protected = {m["maj:min"] for m in mounts if m["maj:min"] in nodes}
    for mount in mounts:
        source = mount["source"].split("[", 1)[0]
        if source.startswith("/dev/"):
            protected.add(device_key(source))
    loops = json.loads(run(["losetup", "--json", "--list", "--output", "NAME,BACK-FILE"]))["loopdevices"]
    loop_backing = {}
    for loop in loops:
        backing = loop.get("back-file")
        if not backing or not Path(backing).exists():
            raise ValueError("Cannot resolve loop backing storage safely")
        source = run(["findmnt", "--noheadings", "--output", "SOURCE", "--target", backing]).strip().split("[", 1)[0]
        loop_backing[device_key(loop["name"])] = device_key(source) if source.startswith("/dev/") else None
    todo, visited = list(protected), set()
    while todo:
        mm = todo.pop()
        if mm in visited:
            continue
        visited.add(mm)
        if nodes.get(mm, {}).get("type") == "loop":
            parent = loop_backing.get(mm)
            if not parent:
                raise ValueError("Mounted loop backing has no identifiable block storage (copy-to-RAM boot is unsupported)")
            protected.add(parent)
            todo.append(parent)
    for line in Path("/proc/swaps").read_text().splitlines()[1:]:
        swap = line.split()[0]
        st = os.stat(swap)
        dev = st.st_rdev if swap.startswith("/dev/") else st.st_dev
        protected.add(f"{os.major(dev)}:{os.minor(dev)}")
    held = {mm for mm in nodes if any((Path("/sys/dev/block") / mm / "holders").iterdir())}
    held.update(mm for mm, node in nodes.items() if node["type"] in ("disk", "part")
                and mm not in protected and raw_device_open(node["name"]))
    return data, protected, held


def device_key(path):
    import stat
    st = os.stat(path)
    if not stat.S_ISBLK(st.st_mode):
        raise ValueError("Not a block device")
    return f"{os.major(st.st_rdev)}:{os.minor(st.st_rdev)}"


def stable_path(node):
    import re
    name = os.path.realpath(node["name"])
    for path in sorted(Path("/dev/disk/by-id").glob("*")):
        if os.path.realpath(path) == name and "-part" not in path.name and re.fullmatch(r"/dev/[A-Za-z0-9_./:+-]+", str(path)):
            return str(path)
    return name
