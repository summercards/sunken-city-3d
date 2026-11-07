extends RefCounted
## 稳定来源 ID → 独立潜水场景；不持有实例、会话或进度。

const _MAPS := {
	"zone1": {
		"map_id": "dive_zone1",
		"scene_path": "res://scenes/underwater/maps/zone1.tscn",
		"label": "家园礁盘",
		"chest_id_base": 0,
	},
	"zone2": {
		"map_id": "dive_zone2",
		"scene_path": "res://scenes/underwater/maps/zone2.tscn",
		"label": "浅湾珊瑚园",
		"chest_id_base": 100,
	},
	"zone3": {
		"map_id": "dive_zone3",
		"scene_path": "res://scenes/underwater/maps/zone3.tscn",
		"label": "环礁深庭",
		"chest_id_base": 200,
	},
	"zone4": {
		"map_id": "dive_zone4",
		"scene_path": "res://scenes/underwater/maps/zone4.tscn",
		"label": "远海断街",
		"chest_id_base": 300,
	},
	"zone5": {
		"map_id": "dive_zone5",
		"scene_path": "res://scenes/underwater/maps/zone5.tscn",
		"label": "北境裂谷",
		"chest_id_base": 400,
	},
	"sea_supply": {
		"map_id": "dive_sea_supply",
		"scene_path": "res://scenes/underwater/maps/sea_supply.tscn",
		"label": "补给站沉箱水域",
		"chest_id_base": 500,
	},
	"rooftop_ranch": {
		"map_id": "dive_rooftop_ranch",
		"scene_path": "res://scenes/underwater/maps/rooftop_ranch.tscn",
		"label": "牧场岩阶",
		"chest_id_base": 600,
	},
	"neon_garden_quarter": {
		"map_id": "dive_neon_garden_quarter",
		"scene_path": "res://scenes/underwater/maps/neon_garden_quarter.tscn",
		"label": "霓虹沉街花园",
		"chest_id_base": 700,
	},
	"resident_harbor": {
		"map_id": "dive_resident_harbor",
		"scene_path": "res://scenes/underwater/maps/resident_harbor.tscn",
		"label": "居民港湾遗迹",
		"chest_id_base": 800,
	},
}


## 家园海底与世界海面同坐标：不使用固定出生点，下水点由海面位置换算。
const HOME_SEABED := {
	"map_id": "dive_home_seabed",
	"scene_path": "res://scenes/underwater/sunroom_region.tscn",
	"label": "家园海底",
	"chest_id_base": 900,
	"world_aligned": true,
	"entry_radius": 60.0,
	"domain": Rect2(-120,-120,240,240),
}


static func source_ids() -> Array[String]:
	var ids: Array[String] = []
	for source_id in _MAPS:
		ids.append(str(source_id))
	return ids


static func get_map(source_id: String) -> Dictionary:
	if source_id == "home_seabed":
		return HOME_SEABED.duplicate(true)
	if not _MAPS.has(source_id):
		return {}
	return _MAPS[source_id].duplicate(true)


## 阳光房附近的固定家园海域优先于普通海区；半径与几何域分开声明。
static func is_home_water(point: Vector3, anchor: Vector3) -> bool:
	return Vector2(point.x-anchor.x,point.z-anchor.z).length() <= float(HOME_SEABED["entry_radius"])


static func home_map() -> Dictionary:
	return HOME_SEABED.duplicate(true)


## 空字符串表示有效；只检查目录，不实例化或初始化地图。
static func validate() -> String:
	var map_ids := {}
	var scene_paths := {}
	for source_id in source_ids() + ["home_seabed"]:
		var entry: Dictionary = HOME_SEABED if source_id == "home_seabed" else _MAPS[source_id]
		var map_id: String = entry["map_id"]
		var scene_path: String = entry["scene_path"]
		if map_id.is_empty() or map_ids.has(map_id):
			return "潜水地图 ID 为空或重复: " + source_id
		if scene_paths.has(scene_path):
			return "潜水地图路径重复: " + source_id
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			return "潜水地图路径不存在: " + scene_path
		map_ids[map_id] = true
		scene_paths[scene_path] = true
	return ""
