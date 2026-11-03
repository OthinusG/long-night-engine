#!/usr/bin/env python3
"""Injects custom ICO into Godot Windows PE executable (.exe).

Replaces GODOT_ICON in RT_GROUP_ICON and individual images in RT_ICON.
"""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile


def inject_icon(exe_path: str, ico_path: str) -> None:
    if not os.path.isfile(exe_path):
        raise FileNotFoundError(f"EXE not found: {exe_path}")
    if not os.path.isfile(ico_path):
        raise FileNotFoundError(f"ICO not found: {ico_path}")

    with open(ico_path, "rb") as f:
        ico_data = f.read()

    reserved, itype, count = struct.unpack("<HHH", ico_data[:6])
    if itype != 1 or count == 0:
        raise ValueError(f"Invalid ICO file: type={itype}, count={count}")

    grp_header = bytearray(struct.pack("<HHH", 0, 1, count))
    icons = []

    offset = 6
    for i in range(count):
        w, h, colors, res, planes, bpp, bytes_in_res, img_offset = struct.unpack(
            "<BBBBHHII", ico_data[offset : offset + 16]
        )
        offset += 16
        img_data = ico_data[img_offset : img_offset + bytes_in_res]
        icon_id = i + 1
        # GRPICONDIRENTRY is 14 bytes: dwImageOffset is replaced by nID (2 bytes)
        grp_entry = struct.pack(
            "<BBBBHHIH", w, h, colors, res, planes, bpp, bytes_in_res, icon_id
        )
        grp_header.extend(grp_entry)
        icons.append((icon_id, img_data))

    temp_dir = tempfile.mkdtemp(prefix="godot_icon_inject_")
    try:
        grp_path = os.path.join(temp_dir, "group_icon.bin")
        with open(grp_path, "wb") as f:
            f.write(grp_header)

        cmd = [
            sys.executable,
            "-m",
            "pe_tools.peresed",
            "--ignore-trailer",
            "-R",
            "RT_GROUP_ICON",
            "GODOT_ICON",
            "1033",
            grp_path,
        ]
        for icon_id, img_data in icons:
            ipath = os.path.join(temp_dir, f"icon_{icon_id}.bin")
            with open(ipath, "wb") as f:
                f.write(img_data)
            cmd.extend(["-R", "RT_ICON", f"#{icon_id}", "1033", ipath])

        cmd.append(exe_path)

        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            print(f"peresed stdout: {res.stdout}", file=sys.stderr)
            print(f"peresed stderr: {res.stderr}", file=sys.stderr)
            raise RuntimeError(f"peresed failed with code {res.returncode}")

        print(f"Successfully injected {count} icon sizes into {exe_path}")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Inject icon into Windows PE executable")
    parser.add_argument("exe", help="Path to .exe file")
    parser.add_argument("ico", help="Path to .ico file")
    args = parser.parse_args()
    inject_icon(args.exe, args.ico)


if __name__ == "__main__":
    main()
