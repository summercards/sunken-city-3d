#!/usr/bin/env python3
"""诊断 glb 里的「重复面」与「共面重叠」。

闪动的直接原因通常是同一张面被画了两次（深度值完全相同 → 逐帧交替胜出）。
这里按「位置量化 + 顶点集」找出出现两次以上的三角形，按材质槽分组统计。

用法：
  python3 tools/diagnose_uw_flicker.py                       # 四个区块全查
  python3 tools/diagnose_uw_flicker.py neighborhood/units/house_00
"""
import collections
import json
import os
import struct
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models", "underwater")


def load_glb(path):
    raw = open(path, "rb").read()
    magic, version, _length = struct.unpack_from("<III", raw, 0)
    assert magic == 0x46546C67, "不是 glb"
    off = 12
    js = None
    bin_chunk = b""
    while off < len(raw):
        clen, ctype = struct.unpack_from("<II", raw, off)
        body = raw[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(body.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_chunk = body
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    return js, bin_chunk


COMP = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(js, blob, index):
    acc = js["accessors"][index]
    fmt, size = COMP[acc["componentType"]]
    n = NCOMP[acc["type"]]
    bv = js["bufferViews"][acc["bufferView"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    stride = bv.get("byteStride") or (size * n)
    out = np.empty((count, n), dtype=np.float64)
    for i in range(count):
        out[i] = struct.unpack_from("<" + fmt * n, blob, start + i * stride)
    return out


def analyse(path, quant=0.001):
    js, blob = load_glb(path)
    stats = []
    seen = collections.Counter()
    owner = {}
    for mi, mesh in enumerate(js.get("meshes", [])):
        for pi, prim in enumerate(mesh.get("primitives", [])):
            pos = accessor(js, blob, prim["attributes"]["POSITION"])
            idx = accessor(js, blob, prim["indices"]).reshape(-1).astype(np.int64) \
                if "indices" in prim else np.arange(len(pos))
            mat = js.get("materials", [])[prim["material"]] if "material" in prim else {}
            key_slot = (mat.get("name", "?"),)
            tri = idx.reshape(-1, 3)
            q = np.round(pos / quant).astype(np.int64)
            faces = 0
            for t in tri:
                a, b, c = q[t[0]], q[t[1]], q[t[2]]
                if (a == b).all() or (b == c).all() or (a == c).all():
                    continue
                faces += 1
                canon = tuple(sorted((tuple(a), tuple(b), tuple(c))))
                seen[canon] += 1
                owner.setdefault(canon, set()).add(key_slot[0])
            stats.append({"prim": "%d/%d" % (mi, pi), "material": key_slot[0],
                          "tris": int(len(tri)), "faces": faces})
    dup = sum(1 for k, v in seen.items() if v > 1)
    extra = sum(v - 1 for v in seen.values() if v > 1)
    cross = sum(1 for k, v in seen.items() if len(owner[k]) > 1)
    return {"file": path, "prims": len(stats), "unique_faces": len(seen),
            "dup_faces": dup, "extra_faces": extra, "cross_material": cross,
            "stats": stats}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    targets = []
    if args:
        for a in args:
            p = os.path.join(MODELS, a)
            if not p.endswith(".glb"):
                p += ".glb"
            targets.append(p)
    else:
        for region in ("basin", "neighborhood", "reef", "trench"):
            d = os.path.join(MODELS, region, "units")
            if not os.path.isdir(d):
                continue
            for f in sorted(os.listdir(d)):
                if f.endswith(".glb"):
                    targets.append(os.path.join(d, f))

    total_dup = 0
    total_extra = 0
    rows = []
    for p in targets:
        r = analyse(p)
        rows.append(r)
        total_dup += r["dup_faces"]
        total_extra += r["extra_faces"]
        flag = "  <-- 重复面" if r["dup_faces"] else ""
        print("%-52s prims %3d  面 %7d  唯一 %7d  重复 %6d (多画 %6d, 跨材质 %3d)%s" % (
            os.path.relpath(p, MODELS), r["prims"], sum(s["faces"] for s in r["stats"]),
            r["unique_faces"], r["dup_faces"], r["extra_faces"], r["cross_material"], flag))
    print("\n合计：重复面 %d 张，多画 %d 张" % (total_dup, total_extra))

    worst = sorted(rows, key=lambda r: -r["extra_faces"])[:3]
    for r in worst:
        if r["extra_faces"] == 0:
            continue
        print("\n%s 最重的槽：" % os.path.relpath(r["file"], MODELS))
        agg = collections.Counter()
        for s in r["stats"]:
            agg[s["material"]] += s["faces"]
        for name, n in agg.most_common(6):
            print("   %-28s %6d 面" % (name, n))


if __name__ == "__main__":
    main()
