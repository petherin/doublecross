#!/usr/bin/env python3
"""Makes single-architecture macOS export templates from Godot's universal one.

Godot ships only universal (Intel + Apple Silicon) Mac binaries, which makes
every Mac download carry both. A universal binary is just a header followed
by the two programs, so this cuts out the one we want and writes a template
zip for that architecture. Godot then exports (and ad-hoc signs) from it.

    python3 tools/thin_macos_template.py <godot macos.zip> <out dir>

Writes <out dir>/macos-arm64.zip and <out dir>/macos-x86_64.zip.
"""
import os
import struct
import sys
import zipfile

FAT_MAGIC = 0xCAFEBABE
CPU = {0x01000007: "x86_64", 0x0100000C: "arm64"}


def slices(data):
    """{arch: bytes} for each architecture in a universal Mach-O binary."""
    magic, count = struct.unpack(">II", data[:8])
    if magic != FAT_MAGIC:
        raise ValueError("not a universal binary")
    out = {}
    for i in range(count):
        cputype, _sub, offset, size, _align = struct.unpack(">iiIII", data[8 + i * 20: 28 + i * 20])
        arch = CPU.get(cputype & 0xFFFFFFFF)
        if arch:
            out[arch] = data[offset: offset + size]
    return out


def main(template, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    src = zipfile.ZipFile(template)
    for arch in ("arm64", "x86_64"):
        path = os.path.join(out_dir, f"macos-{arch}.zip")
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as dst:
            for info in src.infolist():
                data = src.read(info.filename)
                name = info.filename
                if name.endswith(".universal"):
                    data = slices(data)[arch]
                    name = name[: -len("universal")] + arch
                new = zipfile.ZipInfo(name, info.date_time)
                new.external_attr = info.external_attr
                new.compress_type = zipfile.ZIP_DEFLATED
                dst.writestr(new, data)
        print(arch, "template:", path, os.path.getsize(path) // 1048576, "MB")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
