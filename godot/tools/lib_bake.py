#!/usr/bin/env python3
"""烘焙数据读写库（供 build_zones.py / build_plants.py 共用）。

烘焙源：`assets/baked/`，由 tools/export_from_web.cjs 从网页版导出。
  scene.json      meta / textures / geoms / batches / lines
  geoms.bin       顶点属性（pos3 + normal3 + uv2 + color3 紧凑排布）
  geoms_idx.bin   索引
  instances.bin   每个实例 12 个变换 float + 4 个 RGBA float

实例矩阵布局（与 web 导出一致）：
  0..2 basis.x   3 = origin.x
  4..6 basis.y   7 = origin.y
  8..10 basis.z 11 = origin.z
 12..15 RGBA
"""
import json
import math
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAKED = os.path.join(ROOT, "assets", "baked")

# 植物叶片几何：网页版用 IcosahedronGeometry(1, 0/1) 做叶与花，都是这些顶点数。
LEAF_GEOMS = {1020, 1024, 111}


def read_f32(path):
    raw = open(path, "rb").read()
    return struct.unpack("<%df" % (len(raw) // 4), raw)


def read_i32(path):
    raw = open(path, "rb").read()
    return struct.unpack("<%di" % (len(raw) // 4), raw)


def f32_bytes(values):
    return struct.pack("<%df" % len(values), *values)


class Bake:
    def __init__(self, baked_dir=BAKED):
        self.dir = baked_dir
        self.scene = json.load(open(os.path.join(baked_dir, "scene.json")))
        self.geo = read_f32(os.path.join(baked_dir, "geoms.bin"))
        self.idx = read_i32(os.path.join(baked_dir, "geoms_idx.bin"))
        self.inst = read_f32(os.path.join(baked_dir, "instances.bin"))
        self.water = self.scene["meta"]["waterLevel"]
        self.geom_stats = [self._geom_stats(g) for g in self.scene["geoms"]]

    def _geom_stats(self, g):
        o, n = g["pOff"], g["vcount"]
        mn = [1e9] * 3
        mx = [-1e9] * 3
        for i in range(n):
            for k in range(3):
                v = self.geo[o + i * 3 + k]
                if v < mn[k]:
                    mn[k] = v
                if v > mx[k]:
                    mx[k] = v
        return {
            "min": mn,
            "max": mx,
            "size": [mx[k] - mn[k] for k in range(3)],
            "vcount": n,
            "icount": g["icount"],
        }

    def instances(self):
        """逐实例产出 (batch_index, instance_index_in_batch, offset)。"""
        for bi, b in enumerate(self.scene["batches"]):
            if b["geom"] < 0:
                continue
            for k in range(b["count"]):
                yield bi, k, (b["instOff"] + k) * 16

    def inst_pos(self, off):
        return (self.inst[off + 3], self.inst[off + 7], self.inst[off + 11])

    def inst_color(self, off):
        return (self.inst[off + 12], self.inst[off + 13], self.inst[off + 14], self.inst[off + 15])

    def inst_matrix(self, off):
        """3x4 矩阵，按「列」连续存放：bx3, ox, by3, oy, bz3, oz。

        这正好也是 Godot MultiMesh 缓冲区的顺序（网页版烘焙直接灌进去就能用），
        所以解析时必须按列取，不能按 3x3 基 + 原点切。
        """
        m = self.inst[off:off + 12]
        return (
            (m[0], m[1], m[2]),
            (m[4], m[5], m[6]),
            (m[8], m[9], m[10]),
            (m[3], m[7], m[11]),
        )

    def geom_verts(self, gi):
        g = self.scene["geoms"][gi]
        o = g["pOff"]
        n = g["vcount"]
        out = []
        has_n = g["nOff"] >= 0
        no = g["nOff"]
        for i in range(n):
            p = (self.geo[o + i * 3], self.geo[o + i * 3 + 1], self.geo[o + i * 3 + 2])
            nrm = (0.0, 1.0, 0.0)
            if has_n:
                nrm = (self.geo[no + i * 3], self.geo[no + i * 3 + 1], self.geo[no + i * 3 + 2])
            out.append((p, nrm))
        return out

    def geom_indices(self, gi):
        g = self.scene["geoms"][gi]
        if g["icount"] > 0:
            return list(self.idx[g["iOff"]:g["iOff"] + g["icount"]])
        return list(range(g["vcount"]))


def write_instances(path, slices):
    """slices: 平铺的 float 列表（每实例 16 个）。"""
    with open(path, "wb") as f:
        f.write(f32_bytes(slices))


def transform_point(m, p):
    (x0, x1, x2), (y0, y1, y2), (z0, z1, z2), (ox, oy, oz) = m
    return (
        x0 * p[0] + y0 * p[1] + z0 * p[2] + ox,
        x1 * p[0] + y1 * p[1] + z1 * p[2] + oy,
        x2 * p[0] + y2 * p[1] + z2 * p[2] + oz,
    )


def transform_dir(m, d):
    (x0, x1, x2), (y0, y1, y2), (z0, z1, z2), _ = m
    nx = x0 * d[0] + y0 * d[1] + z0 * d[2]
    ny = x1 * d[0] + y1 * d[1] + z1 * d[2]
    nz = x2 * d[0] + y2 * d[1] + z2 * d[2]
    ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / ln, ny / ln, nz / ln)


def rects_of(zone):
    """zones.json 的 walk.rects 已经是世界坐标，返回 (x0,z0,x1,z1) 列表。"""
    out = []
    for w in zone.get("walk", []):
        for r in w["rects"]:
            out.append((r[0], r[2], r[1], r[3]))
    return out


def distance_to_zone(px, pz, zone):
    best = 1e9
    for (x0, z0, x1, z1) in rects_of(zone):
        dx = max(0.0, max(x0 - px, px - x1))
        dz = max(0.0, max(z0 - pz, pz - z1))
        best = min(best, math.hypot(dx, dz))
    return best


def assign_zone(px, pz, zones, pad=6.0):
    """把世界坐标点归到最近的区块；超出 pad 的算环境。"""
    best_id = None
    best_d = 1e9
    for zone in zones:
        d = distance_to_zone(px, pz, zone)
        if d < best_d:
            best_d = d
            best_id = zone["id"]
    return best_id if best_d <= pad else None
