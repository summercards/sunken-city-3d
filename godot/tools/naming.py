#!/usr/bin/env python3
"""命名规范的唯一来源：区块 id ↔ 文件夹名 ↔ 场景节点名。

改这里等于改规范，build_zones.py / build_plants.py 与文档必须同步。
规范正文见 docs/资产与命名规范.md。
"""

# id -> (文件夹/文件名用, 场景节点名, 中文名)
ZONES = {
    "zone1": ("zone1_home_harbor", "Zone1HomeHarbor", "sea"),
    "zone2": ("zone2_yokohama_station", "Zone2YokohamaStation", "横滨铁道"),
    "zone3": ("zone3_arc_farm", "Zone3ArcFarm", "圆弧农场"),
    "zone4": ("zone4_far_shore", "Zone4FarShore", "远海街町"),
    "zone5": ("zone5_aqua_platform", "Zone5AquaPlatform", "浅水养殖台"),
}

ZONE_ORDER = ["zone1", "zone2", "zone3", "zone4", "zone5"]

# 区块级植物效果的配置：写进区块专用植物场景
ZONE_PLANT_EFFECTS = {
    "zone1": {"effect": "petals", "sway": 0.028, "wind": 0.9},
    "zone2": {"effect": "pollen", "sway": 0.020, "wind": 0.7},
    "zone3": {"effect": "wind", "sway": 0.042, "wind": 1.5},
    "zone4": {"effect": "sea_breeze", "sway": 0.032, "wind": 1.2},
    "zone5": {"effect": "ripple", "sway": 0.018, "wind": 0.5},
}


def zone_key(zone_id):
    return ZONES[zone_id][0]


def zone_node(zone_id):
    return ZONES[zone_id][1]


def zone_label(zone_id):
    return ZONES[zone_id][2]
