#!/usr/bin/env python3
"""Clear bogus PT_GNU_STACK PF_X (executable-stack) flags on bundled ELF shared libraries.

Julia 1.10.8 Linux tarballs shipped a `libopenlibm.so` with `PT_GNU_STACK`
marked `RWE` (`PF_X = 0x1`). On Ubuntu 26.04+ (glibc >= 2.41), `dlopen` refuses
to load shared objects requesting an executable stack. Clearing `PF_X` in the
ELF `PT_GNU_STACK` program header matches `patchelf --clear-execstack` /
`execstack -c` without requiring external apt packages.

Usage:
  python3 scripts/clear_elf_execstack.py --self-test
  python3 scripts/clear_elf_execstack.py --julia-bindir /path/to/julia/bin
  python3 scripts/clear_elf_execstack.py FILE [FILE ...]
"""

from __future__ import annotations

import argparse
import pathlib
import struct
import sys
import tempfile

ELF_MAGIC = b"\x7fELF"
ELFCLASS32 = 1
ELFCLASS64 = 2
ELFDATA2LSB = 1
ELFDATA2MSB = 2
PT_GNU_STACK = 0x6474E551
PF_X = 0x1
PF_W = 0x2
PF_R = 0x4


def clear_elf_execstack(path: pathlib.Path) -> bool:
    """Clear PF_X on any PT_GNU_STACK segment in `path` (following symlinks).
    Returns True if a PT_GNU_STACK PF_X bit was cleared, False otherwise.
    """
    real = path.resolve()
    if not real.is_file():
        return False
    data = bytearray(real.read_bytes())
    if len(data) < 64 or data[:4] != ELF_MAGIC:
        return False

    ei_class = data[4]
    ei_data = data[5]
    if ei_data == ELFDATA2LSB:
        endian = "<"
    elif ei_data == ELFDATA2MSB:
        endian = ">"
    else:
        return False

    changed = False
    if ei_class == ELFCLASS64:
        e_phoff = struct.unpack_from(f"{endian}Q", data, 32)[0]
        e_phentsize, e_phnum = struct.unpack_from(f"{endian}HH", data, 54)
        if e_phentsize < 56 or e_phoff + e_phentsize * e_phnum > len(data):
            return False
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type, p_flags = struct.unpack_from(f"{endian}II", data, off)
            if p_type == PT_GNU_STACK and (p_flags & PF_X):
                struct.pack_into(f"{endian}I", data, off + 4, p_flags & ~PF_X)
                changed = True
    elif ei_class == ELFCLASS32:
        e_phoff = struct.unpack_from(f"{endian}I", data, 28)[0]
        e_phentsize, e_phnum = struct.unpack_from(f"{endian}HH", data, 42)
        if e_phentsize < 32 or e_phoff + e_phentsize * e_phnum > len(data):
            return False
        for i in range(e_phnum):
            off = e_phoff + i * e_phentsize
            p_type = struct.unpack_from(f"{endian}I", data, off)[0]
            p_flags = struct.unpack_from(f"{endian}I", data, off + 24)[0]
            if p_type == PT_GNU_STACK and (p_flags & PF_X):
                struct.pack_into(f"{endian}I", data, off + 24, p_flags & ~PF_X)
                changed = True
    else:
        return False

    if changed:
        real.write_bytes(bytes(data))
    return changed


def clear_julia_openlibm(bindir: pathlib.Path) -> list[str]:
    root = bindir.resolve().parent
    lib_dirs = [root / "lib" / "julia", root / "lib"]
    cleared: list[str] = []
    seen: set[pathlib.Path] = set()
    for d in lib_dirs:
        if not d.is_dir():
            continue
        for cand in sorted(d.glob("libopenlibm.so*")):
            real = cand.resolve()
            if real in seen:
                continue
            seen.add(real)
            if clear_elf_execstack(real):
                cleared.append(str(real))
    return cleared


def run_self_test() -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp = pathlib.Path(td)
        # Construct minimal valid 120-byte 64-bit little-endian ELF header + 1 PT_GNU_STACK Phdr
        buf = bytearray(120)
        buf[0:4] = ELF_MAGIC
        buf[4] = ELFCLASS64
        buf[5] = ELFDATA2LSB
        buf[6] = 1
        struct.pack_into("<Q", buf, 32, 64)       # e_phoff = 64
        struct.pack_into("<HH", buf, 54, 56, 1)   # e_phentsize = 56, e_phnum = 1
        struct.pack_into("<II", buf, 64, PT_GNU_STACK, PF_R | PF_W | PF_X)

        so_file = tmp / "libopenlibm.so.4.0"
        so_file.write_bytes(bytes(buf))
        lib_dir = tmp / "julia" / "lib" / "julia"
        bin_dir = tmp / "julia" / "bin"
        lib_dir.mkdir(parents=True)
        bin_dir.mkdir(parents=True)
        real_so = lib_dir / "libopenlibm.so.4.0"
        real_so.write_bytes(bytes(buf))
        (lib_dir / "libopenlibm.so").symlink_to("libopenlibm.so.4.0")

        cleared = clear_julia_openlibm(bin_dir)
        assert len(cleared) == 1, f"Expected 1 cleared library, got {cleared}"
        _, flags_after = struct.unpack_from("<II", real_so.read_bytes(), 64)
        assert flags_after == (PF_R | PF_W), f"Expected RW (6), got {flags_after}"
        # Idempotence check
        assert clear_julia_openlibm(bin_dir) == []
        # Non-ELF file safety check
        txt = tmp / "not_elf.txt"
        txt.write_text("plain text", encoding="utf-8")
        assert clear_elf_execstack(txt) is False
    print("clear_elf_execstack self-test passed")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Clear ELF PT_GNU_STACK PF_X on libopenlibm.so")
    parser.add_argument("--self-test", action="store_true", help="Run deterministic unit self-test")
    parser.add_argument("--julia-bindir", type=pathlib.Path, default=None, help="Julia Sys.BINDIR to scan")
    parser.add_argument("files", nargs="*", type=pathlib.Path, help="Explicit ELF shared libraries")
    args = parser.parse_args(argv)

    if args.self_test:
        run_self_test()
        return 0

    cleared: list[str] = []
    if args.julia_bindir is not None:
        cleared.extend(clear_julia_openlibm(args.julia_bindir))
    for f in args.files:
        if clear_elf_execstack(f):
            cleared.append(str(f.resolve()))
    if cleared:
        print("Cleared PT_GNU_STACK PF_X on:", ", ".join(cleared))
    else:
        print("No PT_GNU_STACK PF_X flags needed clearing.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
