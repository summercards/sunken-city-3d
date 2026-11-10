#!/usr/bin/env python3
"""霓虹花园左楼「检修梯 + 浮台」走域的生成器（SEA-NAV-R23）。

为什么要生成而不是手写：
  这条通路是 5 段梯段（斜坡）+ 5 个平台（平面）+ 1 段补桥，展开成三角形是
  60 个顶点、180 个浮点数。手抄一遍坐标必然出错，而且模型一改版就没人敢动。
  尺寸全部来自实测（tools/probe_stair_chain.gd 的输出），模型改了重跑本脚本即可。

为什么不用 DerivedWalkArea：
  · 选层（select=nearest）会把 12 个高度不同的平台混成一层，压平后角色浮空；
  · band 模式 + flatten_slopes=false 会输出 body_radius=0 的精确网格，
    那样它不进共享的 Recast 烘焙，而是自己成为一张 region，和屋顶面的
    连接只靠 1 cm 的 edge_connection_margin，实测容易断开。

写进 .tscn 的位置见 MARK_BEGIN / MARK_END；重复运行是幂等的。
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "godot/scenes/facilities/neon_garden_quarter.tscn"

# 楼体局部坐标（= LeftBuilding 局部；写进场景的 WalkArea 节点 position 与楼体一致）
LANE_A = (-6.90, -4.87)      # 折返梯的 A 道（原始朝向）
LANE_B = (-4.90, -2.87)      # 折返梯的 B 道（转 180°）
LANDING_X = (-7.09, -2.69)   # 平台宽度，跨两条道
Z_FAR = (-8.90, -6.90)       # 远侧平台（靠 z 负方向）
Z_NEAR = (-2.98, -0.98)      # 近侧平台（靠船位那一侧）
Z_RUN = (-6.90, -2.98)       # 梯段进深

ROOF_Y = 30.80               # 屋顶走域的实际平面高度（世界 15.23）
BRIDGE_Z = (-2.62, -0.98)    # 与屋顶 WalkLeftRoof 最靠楼梯的那条矩形对齐

# 水面以上从近船侧的 20.40 起算：(平台 y, 平台在 z 的哪一侧, 上一段梯段走哪条道)
CHAIN = [
    (20.40, "near", None),
    (22.95, "far", "A"),
    (25.50, "near", "B"),
    (28.05, "far", "A"),
    (30.60, "near", "B"),
]

MARK_BEGIN = "; >>> neon-stair-walk"
MARK_END = "; <<< neon-stair-walk"


def fmt(value: float) -> str:
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def vec(x: float, y: float, z: float) -> str:
    return f"Vector3({fmt(x)}, {fmt(y)}, {fmt(z)})"


def quad(p0, p1, p2, p3) -> list:
    """四边形按周长顺序给四个角，切成两个三角形（绕序由 surface_faces() 兜底）。"""
    return [[p0, p1, p2], [p0, p2, p3]]


def build_triangles() -> list:
    tris: list = []
    z_of = {"near": Z_NEAR, "far": Z_FAR}
    previous = None
    for y, side, lane in CHAIN:
        z0, z1 = z_of[side]
        if previous is not None:
            # 上一级平台 → 本级平台之间是一段梯段
            y_lo, y_hi = previous[0], y
            if lane == "A":
                x0, x1 = LANE_A
                # A 道朝 -z 上行：低端在近侧 z=-2.98，高端在远侧 z=-6.90
                tris += quad((x0, y_lo, Z_RUN[1]), (x1, y_lo, Z_RUN[1]),
                             (x1, y_hi, Z_RUN[0]), (x0, y_hi, Z_RUN[0]))
            else:
                x0, x1 = LANE_B
                # B 道朝 +z 上行：低端在远侧 z=-6.90，高端在近侧 z=-2.98
                tris += quad((x0, y_lo, Z_RUN[0]), (x1, y_lo, Z_RUN[0]),
                             (x1, y_hi, Z_RUN[1]), (x0, y_hi, Z_RUN[1]))
        x0, x1 = LANDING_X
        tris += quad((x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1))
        previous = (y, side)
    # 补桥：平台东缘 → 屋顶平面。前 0.39 m 抬到屋面高度，之后与屋面共面，
    # 这样屋顶矩形的西边缘两侧都有支撑，GroundSpace 不会在那里立一道隐形墙。
    z0, z1 = BRIDGE_Z
    tris += quad((-2.69, 30.60, z0), (-2.69, 30.60, z1),
                 (-2.30, ROOF_Y, z1), (-2.30, ROOF_Y, z0))
    tris += quad((-2.30, ROOF_Y, z0), (-2.30, ROOF_Y, z1),
                 (-1.19, ROOF_Y, z1), (-1.19, ROOF_Y, z0))
    return tris


def block() -> str:
    tris = build_triangles()
    flat = ", ".join(c for tri in tris for p in tri for c in (fmt(p[0]), fmt(p[1]), fmt(p[2])))
    lines = [
        MARK_BEGIN + "（由 godot/tools/build_neon_stair_walk.py 生成，勿手改）",
        ";",
        "; 霓虹花园左楼屋顶的上下通路。这栋楼东侧本来就带一架 12 段双跑折返检修梯，",
        "; 模型里从楼基一路做到局部 30.60，但场景里从来没有可走面 —— 玩家只能靠下船",
        "; 瞬移到屋顶。这里把「水面以上、且靠船的那一侧」那一段派生为走域：",
        "; 5 段梯段（斜坡三角形）+ 5 个平台（平面三角形）+ 1 段搭到屋面的补桥。",
        ";",
        "; 坐标 = LeftBuilding 局部。本节点 position 与楼体一致，所以局部坐标直接可用。",
        "; 梯段每段升 2.55 m、进深 3.92 m（≈33°，低于 GroundSpace 的 agent_max_slope 46°）；",
        "; 平台每 2.55 m 一级，在 z=-8.90..-6.90（远）与 z=-2.98..-0.98（近）之间折返。",
        ";",
        "; 为什么从 20.40 起算：更低的两个平台（世界 2.28 / -0.27）在 z=-8.90 那一侧，",
        "; 离船位 8.7 米，中间还隔着建筑本体；近船侧这一段由「浮台 + 直梯」衔接。",
        "[node name=\"WalkLeftStair\" type=\"Node3D\" parent=\"WalkAreas\"]",
        "script = ExtResource(\"walk\")",
        "position = Vector3(-15.813068389892578, 0.30000001192092896, 0.6180000305175781)",
        "area_id = \"neon_garden_left_stair\"",
        "zone_id = \"neon_garden_quarter\"",
        "surface_y = 15.03",
        "span_min = 4.6",
        "span_max = 15.2",
        "surface_triangles = PackedVector3Array(" + flat + ")",
        "",
        "; 检修梯脚下的浮台：船就停在它旁边（BoatPark 世界 112.79 / 66.20），",
        "; 直梯从这里 1.12 m 升到第一级可用平台 4.83 m。",
        "[node name=\"WalkLeftFloat\" type=\"Node3D\" parent=\"WalkAreas\"]",
        "script = ExtResource(\"walk\")",
        "position = Vector3(-15.813068389892578, 0.30000001192092896, 0.6180000305175781)",
        "area_id = \"neon_garden_left_float\"",
        "zone_id = \"neon_garden_quarter\"",
        "surface_y = 1.12",
        "span_min = 0.9",
        "span_max = 1.35",
        "rects = [Rect2(-8.4, -3.4, 2.2, 1.8)]",
        MARK_END,
    ]
    return "\n".join(lines) + "\n"


VISUAL_BEGIN = "; >>> neon-stair-foot-visual"
VISUAL_END = "; <<< neon-stair-foot-visual"


def visual_block() -> str:
    """浮台造型 + 直梯造型 + 上下两个交互点。"""
    lines = [
        VISUAL_BEGIN + "（由 godot/tools/build_neon_stair_walk.py 生成，勿手改）",
        "[node name=\"StairFoot\" parent=\"Visual\" instance=ExtResource(\"stair_foot\")]",
        "metadata/visual_only = true",
        "position = Vector3(-23.113068389892578, 16.99, -1.8820000305175781)",
        "",
        "; 直梯的两端各一个交互点。climb_ladder 只吃 Y —— 角色沿自己脚下那根竖线升降，",
        "; 所以两个点的 X/Z 就是「攀爬竖线」。它比梯子造型（楼体局部 x -7.05）往里收了",
        "; 0.2 米：站上来的人要落在平台内侧，不能半个身子悬在平台外。",
        "[node name=\"Ladders\" type=\"Node3D\" parent=\".\"]",
        "",
        "[node name=\"StairFootBottom\" type=\"Node3D\" parent=\"Ladders\"]",
        "position = Vector3(-22.663068389892578, 16.99, -1.6720000305175781)",
        "script = ExtResource(\"site_ladder\")",
        "focus_offset = Vector3(0, 0.9, 0)",
        "ladder_label = \"检修梯\"",
        "",
        "[node name=\"StairFootTop\" type=\"Node3D\" parent=\"Ladders\"]",
        "position = Vector3(-22.663068389892578, 20.7, -1.6720000305175781)",
        "script = ExtResource(\"site_ladder\")",
        "focus_offset = Vector3(0, 0.9, 0)",
        "direction = \"down\"",
        "ladder_label = \"检修梯\"",
        VISUAL_END,
    ]
    return "\n".join(lines) + "\n"


def replace_region(text: str, begin: str, end: str, payload: str) -> str:
    pattern = re.compile(r"^" + re.escape(begin) + r".*?^" + re.escape(end) + r".*?$\n?",
                         re.S | re.M)
    if pattern.search(text):
        return pattern.sub(lambda _m: payload, text, count=1)
    raise SystemExit(f"场景里找不到标记 {begin}")


def main() -> None:
    text = SCENE.read_text(encoding="utf-8")
    # 两个生成块的位置：走域插在 RoofNpcStations 之前，造型插在 Blockers 之前
    if MARK_BEGIN not in text:
        anchor = "[node name=\"RoofNpcStations\""
        index = text.index(anchor)
        text = text[:index] + block() + "\n" + text[index:]
    else:
        text = replace_region(text, MARK_BEGIN, MARK_END, block())
    if VISUAL_BEGIN not in text:
        anchor = "[node name=\"Blockers\""
        index = text.index(anchor)
        text = text[:index] + visual_block() + "\n" + text[index:]
    else:
        text = replace_region(text, VISUAL_BEGIN, VISUAL_END, visual_block())
    # 新增两个 ext_resource（放在最后一个 ext_resource 之后）
    if 'path="res://src/interaction/site_ladder_interactable.gd"' not in text:
        last = None
        for match in re.finditer(r"^\[ext_resource [^\n]*$\n", text, re.M):
            last = match
        addition = ("[ext_resource type=\"Script\" path=\"res://src/interaction/site_ladder_interactable.gd\""
                    " id=\"site_ladder\"]\n"
                    "[ext_resource type=\"PackedScene\" "
                    "path=\"res://scenes/components/facilities/neon_garden_quarter/stair_foot.tscn\""
                    " id=\"stair_foot\"]\n")
        text = text[:last.end()] + addition + text[last.end():]
    SCENE.write_text(text, encoding="utf-8", newline="\n")
    print(f"[stair-walk] 写入 {SCENE.relative_to(ROOT)}："
          f"{len(build_triangles())} 个三角形")


if __name__ == "__main__":
    main()
