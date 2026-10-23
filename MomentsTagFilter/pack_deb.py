#!/usr/bin/env python3
# pack_deb.py — 用已编译好的 dylib 打包成 .deb（纯 Python，任何系统可用，无需 dpkg）
#
# 用法:
#   python pack_deb.py --dylib MomentsTagFilter.dylib --out MomentsTagFilter_1.0.0.deb
#
# 布局 (rootful 方案):
#   /Library/MobileSubstrate/DynamicLibraries/MomentsTagFilter.dylib
#   /Library/MobileSubstrate/DynamicLibraries/MomentsTagFilter.plist
# rootless 方案请加 --rootless，前缀改为 /var/jb。
#
# 注意: 本脚本只负责"套壳打包"。dylib 必须已在 macOS/Linux + Theos + iOS SDK 下
# 编译为 arm64/arm64e Mach-O，并用 ldid/codesign 签过 entitlements，才能在越狱设备加载。

import argparse, io, os, tarfile, time, gzip, struct

HERE = os.path.dirname(os.path.abspath(__file__))

CONTROL = open(os.path.join(HERE, "control"), "rb").read()
PLIST = open(os.path.join(HERE, "MomentsTagFilter.plist"), "rb").read()


def tar_gz(members):
    """members: list of (name, bytes, mode)"""
    raw = io.BytesIO()
    t = tarfile.open(fileobj=raw, mode="w")
    for name, data, mode in members:
        ti = tarfile.TarInfo(name)
        ti.size = len(data)
        ti.mode = mode
        ti.mtime = int(time.time())
        ti.uid = ti.gid = 0
        t.addfile(ti, io.BytesIO(data))
    t.close()
    gz = io.BytesIO()
    with gzip.GzipFile(fileobj=gz, mode="wb", mtime=0) as g:
        g.write(raw.getvalue())
    return gz.getvalue()


def ar_entry(name, data):
    name = (name + "/").ljust(16)[:16]
    hdr = name.encode()
    hdr += str(int(time.time())).ljust(12).encode()[:12]
    hdr += b"0     "   # uid
    hdr += b"0     "   # gid
    hdr += b"100644  " # mode
    hdr += str(len(data)).ljust(10).encode()[:10]
    hdr += b"`\n"
    out = hdr + data
    if len(data) % 2:
        out += b"\n"
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dylib", required=True)
    ap.add_argument("--out", default="MomentsTagFilter.deb")
    ap.add_argument("--rootless", action="store_true")
    a = ap.parse_args()

    prefix = "./var/jb" if a.rootless else "."
    dl = prefix + "/Library/MobileSubstrate/DynamicLibraries"

    dylib = open(a.dylib, "rb").read()
    control_tar = tar_gz([("./control", CONTROL, 0o644)])
    data_tar = tar_gz([
        (dl + "/MomentsTagFilter.dylib", dylib, 0o755),
        (dl + "/MomentsTagFilter.plist", PLIST, 0o644),
    ])

    deb = b"!<arch>\n"
    deb += ar_entry("debian-binary", b"2.0\n")
    deb += ar_entry("control.tar.gz", control_tar)
    deb += ar_entry("data.tar.gz", data_tar)
    open(a.out, "wb").write(deb)
    print("wrote", a.out, len(deb), "bytes")


if __name__ == "__main__":
    main()
