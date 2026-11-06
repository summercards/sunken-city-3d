extends Node3D
## SEA-ROOM 剖切：把「对着镜头的这面墙」和挡住俯视视线的天花收起来。
##
## 用户要求「对着镜头的这面墙在这个位置是看不见的」。做法不是永久删掉一面墙，
## 而是按相机方位逐帧决定：每面墙有一个朝外的法线，相机落在它的外侧就藏起来。
## 换机位（比如以后开放旋转观察）时，藏起来的会自己换一面 —— 永远只缺朝向
## 镜头的那一侧，房间永远保持「盒子」的读法，不会出现两面墙同时消失。
##
## 天花单独判断：相机在房顶以上时收起。相机贴地（将来的第一人称视角）时
## 天花照常显示 —— 这条不做成常量开关，是因为它本来就是几何关系。

## 相机越过这面墙的外表面之后，再走这么多米才收起它。留一点余量，
## 免得贴着墙面擦过时来回闪。
##
## 判据是「越过墙本身」，不是「越过房间中心」：房间半宽 2.5 米，
## 相机必须真的到 2.5 米以外才算从这面墙外侧看。用「相对中心 0.25 米」判会出错 ——
## 默认视点偏 +Z 0.55 米时，相机转到正东（x≈9.9、z≈0.55）仍会被判成
## 「在前墙外侧」，于是东墙和前墙同时收起，房间缺两面墙。
const FACING_MARGIN := 0.25
## 房间墙到中心的距离（内部净空 5.0 米）。前厅件不带这个默认值 ——
## 它们各自有更小的 offset。
const WALL_OFFSET := 2.5
## 相机高出「室内地面 + 墙高」这么多时才收起天花。
const CEILING_MARGIN := 0.05
## 前厅件的「朝外法线余量」。比墙的 0.25 米大得多 ——
## 前厅只有 1.8 米进深，稍微转一下相机就站到侧玻璃外侧；
## 余量太小，正面构图也会被判成「从侧边看」而把侧玻璃一起收掉，
## 前厅就只剩一块地板。
const PORCH_MARGIN := 1.6
## 「相机站到前厅前面了」的房间局部 z。超过这个值，整座前厅都在镜头与室内之间，
## 前厅件（玻璃、立柱、裙墙、圈梁）一律收起，只留地板。
##
## 只按各自法线判是不够的：相机在 +Z 侧时，正面玻璃确实收了，
## 但东西两侧玻璃的法线朝 ±X、dot 是负的，会被判成「远侧」而留着 ——
## 它们一样挡在镜头和房间之间，在画面左侧斜插一块暗板（实测截图里就是它）。
const PORCH_FRONT_Z := 2.4

var camera: Camera3D
var walls: Array = []
## 顶面：天花 + 玻璃前厅的斜顶。相机高于墙顶时一律收起 ——
## 这两块都在「镜头与房间之间」，留着就只剩一片顶板，屋里什么都看不见。
var roofs: Array = []
## 前厅里「可以整排收起」的构件（按局部 +Z 判定）。相机在 +Z 侧时收起，
## 相机在 -Z 侧时全部恢复 —— 前厅只有一侧有正面，规则不对称是应该的。
var ceiling_height := 2.75


## `wall_entries` 里每一项都是 `{node, normal, margin?}`。前厅的玻璃、立柱、
## 裙墙、圈梁也走这张表 —— 它们本来就是「有朝外法线的墙面」，
## 只是尺寸比 5 米墙小得多，所以各自带一个更大的 margin。
func configure(cam: Camera3D, wall_entries: Array, roof_nodes: Array, wall_height: float) -> void:
	camera = cam
	walls = wall_entries
	roofs = roof_nodes
	ceiling_height = wall_height
	refresh()


func refresh() -> void:
	if camera == null:
		return
	# 相机在**房间局部空间**里的位置。
	#
	# 必须用 to_local 而不是世界位置差：房间整体 scale 1.5（见 bedroom.tscn 头注释），
	# 而下面所有阈值（墙到中心的距离、前厅 face、天花高度、PORCH_FRONT_Z）
	# 都是建模时的局部尺寸。在世界空间里比，就得给每个常量乘一次 scale ——
	# 漏乘一个就是「转到侧面缺两面墙」这种只有看渲染才发现的问题。
	# 转成局部之后，这些常量永远不用改。
	var local_cam := to_local(camera.global_position)
	var flat := Vector3(local_cam.x, 0.0, local_cam.z)
	for entry in walls:
		var node: Node3D = entry.get("node")
		if not is_instance_valid(node):
			continue
		var outward: Vector3 = entry.get("normal", Vector3.ZERO)
		var face: float = entry.get("offset", WALL_OFFSET)
		var margin: float = entry.get("margin", FACING_MARGIN)
		var visible := flat.dot(outward) < face + margin
		# 前厅件多一条：整座前厅压在镜头与室内之间时，全部都收。
		if visible and bool(entry.get("porch", false)) and flat.z > PORCH_FRONT_Z:
			visible = false
		node.visible = visible
	var from_above := local_cam.y > ceiling_height + CEILING_MARGIN
	for roof in roofs:
		if is_instance_valid(roof):
			roof.visible = not from_above


func _process(_delta: float) -> void:
	refresh()


func hidden_walls() -> PackedStringArray:
	var names := PackedStringArray()
	for entry in walls:
		var node: Node3D = entry.get("node")
		if is_instance_valid(node) and not node.visible:
			names.append(String(node.name))
	return names
