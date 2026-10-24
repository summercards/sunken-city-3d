#!/usr/bin/env python3
"""从 Godot 导出模板 tpz 里用 HTTP Range 只抓 web 模板，避免下载 1.2GB 整包。"""
import sys, os, struct, zlib, urllib.request, time

URL = sys.argv[1]
OUT = sys.argv[2]
NEED = [n for n in sys.argv[3:]] or ["web_release.zip"]


def head_len(url):
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=60) as r:
        return int(r.headers["Content-Length"]), r.geturl()


def get_range(url, start, end):
    req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def main():
    real = None
    total, real = head_len(URL)
    url = real or URL
    print(f"total={total} url={url}")

    tail_len = 65536
    tail = get_range(url, max(0, total - tail_len), total - 1)
    i = tail.rfind(b"PK\x05\x06")
    if i < 0:
        raise SystemExit("EOCD not found")
    cd_size, cd_off = struct.unpack("<II", tail[i + 12:i + 20])
    print(f"cd_size={cd_size} cd_off={cd_off}")
    cd = get_range(url, cd_off, cd_off + cd_size - 1)

    entries = {}
    p = 0
    while p < len(cd) and cd[p:p + 4] == b"PK\x01\x02":
        method, = struct.unpack("<H", cd[p + 10:p + 12])
        csize, usize = struct.unpack("<II", cd[p + 20:p + 28])
        nlen, elen, clen = struct.unpack("<HHH", cd[p + 28:p + 34])
        lho, = struct.unpack("<I", cd[p + 42:p + 46])
        name = cd[p + 46:p + 46 + nlen].decode("utf-8", "replace")
        entries[name] = (method, csize, usize, lho)
        p += 46 + nlen + elen + clen

    print(f"entries={len(entries)}")
    for n in sorted(entries):
        if "web" in n.lower() or n.endswith(".txt"):
            print("  ", n, entries[n][2])

    os.makedirs(OUT, exist_ok=True)
    for want in NEED:
        hit = None
        for n in entries:
            if n == want or n.endswith("/" + want):
                hit = n
                break
        if not hit:
            print("missing", want)
            continue
        method, csize, usize, lho = entries[hit]
        hdr = get_range(url, lho, lho + 29)
        assert hdr[:4] == b"PK\x03\x04"
        nlen, elen = struct.unpack("<HH", hdr[26:30])
        data_start = lho + 30 + nlen + elen
        t0 = time.time()
        raw = get_range(url, data_start, data_start + csize - 1)
        blob = zlib.decompress(raw, -15) if method == 8 else raw
        dst = os.path.join(OUT, os.path.basename(hit))
        with open(dst, "wb") as f:
            f.write(blob)
        print(f"saved {dst} {len(blob)/1e6:.1f}MB in {time.time()-t0:.1f}s")


main()
