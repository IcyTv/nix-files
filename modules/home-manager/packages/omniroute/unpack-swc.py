"""Materialize pinned SWC carriers before Nix ELF repair, retaining SHA-512 checks.

Format and verification mirror SWC v1.16.13's swc_native_addon/src/format.rs:
https://github.com/swc-project/swc/blob/v1.16.13/crates/swc_native_addon/src/format.rs
The enclosing npm archives are independently pinned by npmDepsHash. Raw addons
are a supported SWC representation; its own loader can replace carriers with raw
images. Nix subsequently repairs native dependencies and makes output immutable.
"""

import hashlib
import io
import struct
import subprocess
import sys
from pathlib import Path

from elftools.elf.elffile import ELFFile


def require_target(elf):
    if (
        elf.elfclass != 64
        or not elf.little_endian
        or elf["e_machine"] != "EM_X86_64"
        or elf["e_type"] != "ET_DYN"
    ):
        raise ValueError("SWC addon is not an x86_64 little-endian ELF shared object")


def unpack(path):
    with path.open("rb") as source:
        elf = ELFFile(source)
        require_target(elf)
        section = elf.get_section_by_name(".swc_native")
        if section is None:
            print(f"{path}: already an uncompressed native addon")
            return
        payload = section.data()

    if len(payload) < 96:
        raise ValueError("truncated SWC payload header")
    magic, version, size, target, packed_size, raw_size, digest = struct.unpack(
        "<8sHHB3xQQ64s", payload[:96]
    )
    if (magic, version, size, target, payload[13:16]) != (
        b"SWCNZSTD", 1, 96, 5, b"\0\0\0"
    ):
        raise ValueError("unsupported SWC payload format or target")
    if not (0 < packed_size <= 2**31 and 0 < raw_size <= 2**31):
        raise ValueError("invalid SWC payload lengths")
    if len(payload) != size + packed_size or payload[size : size + 4] != b"\x28\xb5\x2f\xfd":
        raise ValueError("invalid SWC compressed payload")

    raw = subprocess.run(
        ["zstd", "--decompress", "--stdout", "--quiet"],
        input=payload[size:], capture_output=True, check=True,
    ).stdout
    if len(raw) != raw_size or hashlib.sha512(raw).digest() != digest:
        raise ValueError("SWC payload length or SHA-512 verification failed")
    require_target(ELFFile(io.BytesIO(raw)))
    # Never overwrite the carrier until the complete decoded image is verified.
    path.write_bytes(raw)
    print(f"{path}: verified and materialized SHA-512 {digest.hex()}")


if __name__ == "__main__":
    for filename in sys.argv[1:]:
        unpack(Path(filename))
