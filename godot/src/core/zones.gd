class_name ZoneSpecs
extends RefCounted

## 海面区块注册表 —— 与 sea/zones.js 一一对应。
##
## 坐标约定（与 JS 原版完全一致）：
##   - origin 是区块在世界里的锚点。
##   - 区块内点位（camera / hover / boat / landing / walk.rects / harbor / site）
##     都写相对 origin 的偏移，x、z 自动加 origin，y 一律是绝对世界高度。
##   - 数组写 [x, y, z]，y 写 "water" 表示贴水面。
##   - walk[].rects 每项是 [minX, maxX, minZ, maxZ]（相对）。
##
## 唯一数据源：gameplay 里不写任何区块坐标。

const WATER_LEVEL := 1.12

static var _defs_cache: Array = []


static func get_defs() -> Array:
	if _defs_cache.is_empty():
		_defs_cache = _build_defs()
	return _defs_cache


static func _build_defs() -> Array:
	return [
		{
			"id": "zone1",
			"name": "sea",
			"role": "home",
			"purpose": "起始据点：太阳能木屋、交易码头、绞盘打捞台",
			"status": "木屋码头待机",
			"origin": [0.0, 0.0, 0.0],
			"camera": [0.45, 1.75, -0.65],
			"hover": [4.3, 5.92, -0.4],
			"boat": {"park": [6.97, "water", 7.92], "yaw": -1.05},
			"landing": {"dockEdge": [6.0, 2.1, 4.3], "stand": [3.35, 2.15, 3.35]},
			# 主码头外，西南面的绞盘打捞台也能上岸：船从东侧靠泊。
			"extraLandings": [
				{
					"id": "salvage",
					"name": "绞盘打捞台",
					"dockEdge": [-9.0, 1.33, 13.0],
					"stand": [-11.6, 1.33, 12.6],
					"park": [-7.2, "water", 13.9],
					"yaw": 0.0,
				},
			],
			"walk": [
				{
					"id": "zone1_home_dock",
					"y": 2.15,
					"span": [1.3, 2.45],
					"rects": [
						[-3.2, 8.4, -7.2, -3.0],
						[0.0, 8.4, -3.0, 4.6],
						[7.8, 9.2, -5.2, 1.8],
						[-2.4, 2.8, 6.4, 11.2],
					],
				},
				{
					"id": "zone1_salvage",
					"y": 1.33,
					"span": [1.0, 1.5],
					"rects": [[-15.2, -8.6, 9.8, 15.9]],
				},
			],
			"harbor": [
				{"kind": "salvage", "label": "C · 绞盘打捞台", "point": [-12.0, "water", 13.0]},
				{"kind": "dock", "label": "D · 交易码头", "point": [0.3, "water", 9.0]},
			],
		},
		{
			"id": "zone2",
			"name": "横滨铁道",
			"role": "station",
			"purpose": "沉没铁道站台与复古电车，可开辟站台花圃、车顶花园、水道睡莲",
			"status": "横滨铁道站台待机",
			"origin": [-30.0, 0.0, -18.0],
			"camera": [0.0, 1.2, 0.0],
			"hover": [0.0, 5.32, 0.0],
			"boat": {"park": [-3.51, "water", 5.78], "yaw": -1.57},
			"landing": {"dockEdge": [-2.2, 1.17, 2.3], "stand": [-2.7, 2.83, -0.3]},
			"walk": [
				{
					"id": "zone2_station",
					"y": 2.6,
					"span": [1.1, 3.1],
					"rects": [
						[-3.0, -2.0, -5.0, 2.5],
						[-7.0, -5.5, -6.5, -2.0],
						[-4.5, -3.0, -5.5, -1.0],
						[-5.5, -4.5, -6.0, -1.0],
						[-8.0, -7.0, -7.0, -2.0],
						[1.0, 2.0, -6.5, -2.5],
						[2.0, 3.5, -0.5, 2.5],
						[3.0, 4.5, -5.5, -1.5],
						[4.5, 6.0, -5.0, -1.0],
						[6.0, 7.5, -4.5, -0.5],
					],
				},
			],
			"harbor": [],
		},
		{
			"id": "zone3",
			"name": "圆弧农场",
			"role": "farm",
			"purpose": "圆弧屋顶种植园，可在屋顶花池种龟背竹与芭蕉林",
			"status": "天台种植园待机",
			"origin": [-2.25, 0.3, -36.0],
			"camera": [0.0, 1.6, 0.0],
			"hover": [0.0, 5.2, 0.0],
			"boat": {"park": [9.9, "water", 2.0], "yaw": -2.62},
			"landing": {"dockEdge": [5.4, 3.1, 2.0], "stand": [2.0, 4.31, 1.0]},
			"walk": [
				{
					"id": "zone3_ground",
					"y": 4.3,
					"span": [2.8, 4.95],
					"rects": [
						[-2.5, 2.5, -6.5, 6.5],
						[-3.5, -2.5, -6.0, 6.0],
						[2.5, 3.5, -6.0, 6.0],
						[3.5, 4.5, -5.5, 5.5],
						[-4.0, -3.5, -5.5, 5.5],
						[-4.5, -4.0, -5.0, 5.0],
						[4.5, 5.0, -5.0, 5.0],
						[-5.0, -4.5, -4.5, 4.5],
						[5.0, 5.5, -4.5, 4.5],
					],
				},
			],
			"harbor": [],
		},
		{
			"id": "zone4",
			"name": "远海街町",
			"role": "shore",
			"purpose": "远海终点：断桥与晾衣生活船所在的海街岸边",
			"status": "远海街町待机",
			"unlock": "farSea",
			"origin": [39.5, 0.0, -41.5],
			"camera": [0.0, 1.4, 0.0],
			"boat": {"park": [-6.44, "water", 4.94], "yaw": 2.36},
			"landing": {"dockEdge": [-3.3, 1.73, 4.1], "stand": [-1.7, 1.66, 0.7]},
			"walk": [
				{
					"id": "zone4_shore",
					"y": 1.65,
					"span": [1.3, 2.15],
					"rects": [[-4.1, -0.9, 0.3, 5.5]],
				},
			],
			"harbor": [],
		},
		{
			"id": "zone5",
			"name": "浅水养殖台",
			"role": "aquaculture",
			"purpose": "远海珍珠培育的四格浅水池，船只 2 级后开放修建",
			"status": "浅水养殖台待机",
			"origin": [22.0, 0.0, 16.0],
			"site": [0.0, 0.0],
			"camera": [0.0, 1.5, 0.0],
			"hover": [0.0, 2.5, 0.0],
			"boat": {"park": [-4.73, "water", -0.08], "yaw": 0.0},
			"landing": {"dockEdge": [-2.8, 1.35, -0.6], "stand": [-1.0, 1.15, 0.0]},
			"walk": [
				{
					"id": "zone5_aqua",
					"y": 1.25,
					"span": [1.0, 1.55],
					"rects": [[-3.2, 3.3, -2.8, 2.7]],
				},
			],
			"harbor": [],
		},
	]


static func create_registry(defs: Array = []) -> ZoneRegistry:
	if defs.is_empty():
		defs = get_defs()
	return ZoneRegistry.new(defs)


## 区块注册表（对应 JS 的 createZoneRegistry 返回值）。
class ZoneRegistry:
	extends RefCounted

	var list: Array = []
	var by_id: Dictionary = {}
	var ids: Array = []
	var walk_regions: Array = []
	var water_level: float = 1.12

	func _init(defs: Array) -> void:
		for d in defs:
			var zone: Dictionary = _create_zone(d)
			list.append(zone)
			by_id[zone.id] = zone
			ids.append(zone.id)
			for region in zone.regions:
				walk_regions.append(region)

	func _num(v: Variant) -> float:
		return water_level if typeof(v) == TYPE_STRING else float(v)

	## 相对坐标 → 世界坐标（x/z 加 origin，y 是绝对高度）。
	func _vec(a: Array, ox: float, oz: float) -> Vector3:
		return Vector3(float(a[0]) + ox, _num(a[1]), float(a[2]) + oz)

	func _rects_of(spec: Dictionary, ox: float, oz: float) -> Array:
		var out: Array = []
		for r in spec.rects:
			var min_x: float = float(r[0]) + ox
			var max_x: float = float(r[1]) + ox
			var min_z: float = float(r[2]) + oz
			var max_z: float = float(r[3]) + oz
			out.append(Rect2(min_x, min_z, max_x - min_x, max_z - min_z))
		return out

	func _create_zone(d: Dictionary) -> Dictionary:
		var origin: Array = d.get("origin", [0.0, 0.0, 0.0])
		var ox: float = float(origin[0])
		var oy: float = float(origin[1])
		var oz: float = float(origin[2])

		var regions: Array = []
		for spec in d.walk:
			var rects: Array = _rects_of(spec, ox, oz)
			var min_x: float = INF
			var max_x: float = -INF
			var min_z: float = INF
			var max_z: float = -INF
			for r in rects:
				min_x = minf(min_x, r.position.x)
				max_x = maxf(max_x, r.end.x)
				min_z = minf(min_z, r.position.y)
				max_z = maxf(max_z, r.end.y)
			regions.append({
				"id": spec.id,
				"zone": d.id,
				"y": float(spec.y),
				"span": spec.get("span", [float(spec.y) - 0.4, float(spec.y) + 0.6]),
				"rects": rects,
				"minX": min_x,
				"maxX": max_x,
				"minZ": min_z,
				"maxZ": max_z,
			})

		# 一个区块可以有多个上岸点：主码头 + 独立平台（打捞台、养殖台…）。
		var landings: Array = [{
			"id": "main",
			"name": d.name,
			"boatPark": _vec(d.boat.park, ox, oz),
			"boatYaw": float(d.boat.get("yaw", 0.0)),
			"dockEdge": _vec(d.landing.dockEdge, ox, oz),
			"landStand": _vec(d.landing.stand, ox, oz),
		}]
		for l in d.get("extraLandings", []):
			landings.append({
				"id": l.id,
				"name": l.get("name", d.name),
				"boatPark": _vec(l.park, ox, oz),
				"boatYaw": float(l.get("yaw", 0.0)),
				"dockEdge": _vec(l.dockEdge, ox, oz),
				"landStand": _vec(l.stand, ox, oz),
			})

		var harbor: Array = []
		for h in d.get("harbor", []):
			var entry: Dictionary = h.duplicate(true)
			entry.point = _vec(h.point, ox, oz)
			harbor.append(entry)

		var zone: Dictionary = d.duplicate(true)
		zone.origin = Vector3(ox, oy, oz)
		zone.camera = _vec(d.camera, ox, oz) if d.has("camera") else null
		zone.hover_anchor = _vec(d.hover, ox, oz) if d.has("hover") else null
		zone.site = _vec([d.site[0], 0.0, d.site[1]], ox, oz) if d.has("site") else null
		zone.boat_park = landings[0].boatPark
		zone.boat_yaw = landings[0].boatYaw
		zone.dock_edge = landings[0].dockEdge
		zone.land_stand = landings[0].landStand
		zone.landings = landings
		zone.harbor = harbor
		zone.regions = regions
		return zone

	func get_zone(id: String) -> Variant:
		return by_id.get(id, null)

	func is_unlocked(id: String, state: Dictionary) -> bool:
		var zone: Variant = get_zone(id)
		if zone == null:
			return false
		if zone.get("unlock", "") == "farSea":
			return bool(state.get("farSeaUnlocked", false))
		return true

	## 取某个上岸点（不传 landing_id 就取主码头）。
	func landing(zone_id: String, landing_id: String = "main") -> Variant:
		var zone: Variant = get_zone(zone_id)
		if zone == null:
			return null
		if landing_id.is_empty() or landing_id == "main":
			return zone.landings[0]
		for l in zone.landings:
			if l.id == landing_id:
				return l
		return zone.landings[0]

	func landings_of(zone_id: String) -> Array:
		var zone: Variant = get_zone(zone_id)
		return zone.landings if zone != null else []

	func label(id: String) -> String:
		var zone: Variant = get_zone(id)
		return zone.name if zone != null else id

	func role(id: String) -> Variant:
		var zone: Variant = get_zone(id)
		return zone.role if zone != null else null

	func service_zones(kind: String) -> Array:
		var out: Array = []
		for z in list:
			for h in z.harbor:
				if h.kind == kind:
					out.append(z.id)
					break
		return out

	func harbor_point(kind: String) -> Variant:
		for zone in list:
			for h in zone.harbor:
				if h.kind == kind:
					return h.point
		return null

	## 区块的模型包围盒（由可站立地块 + 点位估算），用于校验区块间距。
	func footprint(id: String) -> Variant:
		var zone: Variant = get_zone(id)
		if zone == null:
			return null
		var xs: Array = []
		var zs: Array = []
		for r in zone.regions:
			xs.append(r.minX)
			xs.append(r.maxX)
			zs.append(r.minZ)
			zs.append(r.maxZ)
		for p in [zone.boat_park, zone.dock_edge, zone.land_stand]:
			xs.append(p.x)
			zs.append(p.z)
		for h in zone.harbor:
			xs.append(h.point.x)
			zs.append(h.point.z)
		if zone.site != null:
			xs.append(zone.site.x)
			zs.append(zone.site.z)
		return {
			"minX": xs.min(),
			"maxX": xs.max(),
			"minZ": zs.min(),
			"maxZ": zs.max(),
		}

	## 区块内的建造点（buildSites 用 zone 字段挂靠）。
	func sites_in(id: String, sites: Array) -> Array:
		var out: Array = []
		for s in sites:
			if s.get("zone", "") == id:
				out.append(s)
		return out
