extends "res://src/ambient/scene_component.gd"
## 场景装饰鱼群：模型和巡游动画直接移植网页版，不再用「椭球 + 棱锥」拼的旧鱼。
##
## 模型（web/underwater-art.js）：椭球身体 + 奶白背斑 + 两侧深色圆眼 + 三角尾鳍。
## 动画（同文件 + web/fish-schools.js）：
##   每条鱼绕群心做椭圆巡游，个体相位错开；朝向取轨道切线；尾鳍按 9 rad/s 摆，
##   身体随摆尾轻微侧倾，纵向做缓慢起伏。水面群额外跟随同一套海浪采样。
##
## 绘制：每群 4 个 MultiMesh（身体 / 背斑 / 双眼 / 尾鳍）。尾鳍单独一份实例矩阵，
## 否则摆尾摆不出来。首版旧实现把 18 条挤在 ±1.2 m 的方框里，俯视看就是一团；
## 现在每个个体有自己的地盘，最近间距不小于 min_gap_for()，群是散开的。
const Geometry = preload("res://src/ambient/animal_mesh.gd")

## 网页版水下鱼群配色（underwater-art.js 按群轮换）。
## 网页版是直接 PBR，Godot 这边过了 ACES + 深度雾，同样的 hex 出来会偏淡偏白，
## 所以色相不动、饱和度和明度各压一档，屏幕上才回到网页那种饱和的琥珀/天蓝/紫。
const DIVE_PALETTE := ["#ffa726", "#e0712a", "#2fb6e0", "#a865d8"]
## 水面群配色：网页版 fish-schools.js 是清一色薄荷青，俯视看就是一片同色小鱼点，
## 既分不清个体、也没有"海面有活物"的热闹感。这里改成**每组三色**，三组各取一套
## （暖 / 冷 / 混），单看任意一组都有 3 种颜色，整个水面能看出 6 个色相。
##
## 这些 hex 是**反解出来的输入色**，不是"看起来想给"的颜色。鱼沉在水面之下
## 0.5–1.2 m，水面 shader 走折射 + 逐通道吸收（`absorption = 0.088, 0.036, 0.028`，
## 红光吸得最狠），所以：
##   · 暖色在水下**物理上不可达高饱和** —— 反解得到的最饱和琥珀仍需线性 R≈1.37，
##     超过 1.0，只能给到 `#ff9a00` 这一档，上屏约 (217,150,75)；
##   · 所以色板按"过水面之后上屏是什么"定：上屏 s ≥0.43、v ≈0.73–0.87，见本轮记录。
## 标定方法：水下 0.62 m 摆 12 个已知色的 unshaded 球，拍照采样，拟合线性空间
## 3×3 + 偏置，再对目标屏幕色求逆。换水面参数（absorption / shallow_tint）后必须重标，
## 否则鱼会读成土黄（上一版就是这样）。
const SURFACE_SETS := [
	["#ff9a00", "#ff6a55", "#c46ce0"],  # 琥珀 / 珊瑚 / 紫
	["#4fa8ea", "#ff76ab", "#fedb00"],  # 天蓝 / 粉 / 柠檬
	["#00c4b0", "#ff9a00", "#c46ce0"],  # 青 / 琥珀 / 紫
]

@export_enum("dive", "surface", "single") var palette := "dive"
## 鱼型：水面用扁胖型、水下用细长型（网页版本来就是两套模型）。
@export_enum("flat", "slim") var profile := "slim"
@export var palette_index := 0
## palette="single" 时才读它。
@export var color := Color("#ffc55c")
## 每群条数。水面群用 10 条：18 条挤在同一个地盘里，俯视看就是一片密不透风的
## 小鱼点，读不出「一群鱼」。水下群保持 18 条（侧视、体量大、纵深长）。
@export var count := 18
## 巡游轨道半径（X/Z 轴）。网页版水下是 (6,3)，水面是 (2.4,1.3)。
## 巡游轨道半径（X/Z 轴），会在运行时乘 size_scale。
## 水面群别按网页版给：这里乘完 size_scale(0.5) 之后只剩 1.2×0.65，
## 单条鱼的游程比自己的身体还短，俯视看就是"在原地抖"。
@export var orbit_radius := Vector2(6.0, 3.0)
## 单群内个体散布半径。网页版取 ±5 的随机方框会结块，
## 这里交给 Geometry.school_offsets（抖过的黄金角螺旋 + 两两互斥）。
@export var spread_radius := 4.8
@export var swim_speed := 0.13
@export var bob := 0.2
@export var phase := 0.0
@export var seed_value := 71
@export var autonomous := true
## 在水面区域游的群：y 跟随同一套波浪采样，并整体压在浪面之下（见 submerge_*）。
## 水下群（潜水层）保持各自固定深度，不读这个开关。
@export var ride_water := false
## 贴水面游的群：鱼**最高点**位于浪面之下的深度（米）。
##
## 这里的口径是"整条鱼沉在水下多少"，不是"鱼心离水面多少"：按鱼心算，
## 半个体高又朝上，背脊会刚好卡在浪面附近 —— 半透明水膜压住鱼背，
## 屏幕上就是「颜色发白发脏」，比浮在水面上还难看。
## 0.5 m 是水膜稳定盖住整条鱼的下限，1.5 m 是俯视机位还能读出鱼形的上限
## （再深就被水色吃掉，只剩几个色点）。
@export_range(0.0, 3.0, 0.05) var submerge_min := 0.5
@export_range(0.0, 3.0, 0.05) var submerge_max := 1.5
## 个体体型倍数。水面群要小一半（俯视机位比网页版更远，原尺寸显得臃肿）。
@export_range(0.2, 2.0, 0.05) var size_scale := 1.0

var members: Array = []
var transforms: Array[Transform3D] = []
var elapsed := 0.0
var _parts: Dictionary = {}
var _water: MeshInstance3D


func _ready() -> void:
	component_kind = "decoration"
	subcategory = "animals"
	asset_id = "SEA-DECO-ANIMAL-FISH-SCHOOL"
	set_meta("visual_only", true)
	build()


func build() -> void:
	if not members.is_empty():
		return
	var colors := resolved_colors()
	var body_color: Color = colors[0]
	# 水面群在水面上方被阳光直照，再加自发光就会整条抬成灰白；
	# 只有水下群需要一点自发光去抵水色吸收。
	var glow := 0.0 if palette == "surface" else 0.22
	_add_part("Body", Geometry.fish_hull(profile), body_color, glow)
	# 奶白背脊斑只给水下群（网页版 underwater-art.js 才有）。
	# 水面群是俯视机位，那块高光会整个盖在鱼背上，整条鱼读成灰白 ——
	# 网页版水面鱼（fish-schools.js）本来就只有身体 + 尾鳍 + 眼睛。
	if profile == "slim":
		_add_part("Back", Geometry.fish_back(profile), Color("#fff2cc"), glow * 0.5)
	_add_part("Eyes", Geometry.fish_eyes(profile), Color("#112e35"), 0.0)
	_add_part("Fin", Geometry.fish_fin(profile), body_color.lightened(0.14), glow)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# 地盘布局统一走 Geometry.school_offsets：抖过的螺旋 + 互斥，保证散开但不重叠。
	# 旧版把 18 条撒进 ±1.2 m 的方框，俯视看就是一团。
	var gaps := min_gap_for(count)
	var placements := Geometry.school_offsets(count, spread_radius, 0.62, gaps, rng)
	# 群内配色：色板轮流发，再洗一遍牌。
	# 不能直接按索引取模 —— school_offsets 是沿黄金角螺旋铺开的，
	# 颜色跟着索引走，俯视就会看到同色鱼连成一条螺旋臂。
	var swatches: Array = []
	for i in count:
		swatches.append(colors[i % colors.size()])
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Color = swatches[i]
		swatches[i] = swatches[j]
		swatches[j] = tmp
	for i in count:
		members.append({
			"offset": placements[i],
			"phase": rng.randf() * TAU,
			# 轨道整体朝向：所有鱼共用同一个椭圆朝向时，群读成"同一圈上排队"。
			"tilt": rng.randf() * TAU,
			"squash": rng.randf_range(0.72, 1.12),
			"speed": rng.randf_range(0.80, 1.26),
			"scale": rng.randf_range(0.72, 1.0),
			"color": swatches[i],
			# 沉深只对贴水面游的群有意义；给每条鱼一档随机深度，
			# 整群就不会像一层贴纸平铺在水下同一个平面上。
			"depth": rng.randf_range(submerge_min, submerge_max),
		})
	for key in _parts:
		var mm: MultiMesh = (_parts[key] as MultiMeshInstance3D).multimesh
		mm.instance_count = count
		for i in count:
			mm.set_instance_color(i, _instance_color(key, members[i].color))
	sample(0.0)


## 每个部件的实例色。身体和尾鳍跟随个体色（尾鳍**不提亮**：
## 色板已经为过水面做过提饱和，尾鳍再 lightened 会顶到 1.0，上屏读成白色三角），
## 眼睛固定深色、背斑固定奶白，不随配色走。
func _instance_color(key: String, body: Color) -> Color:
	match key:
		"Eyes":
			return Color("#112e35")
		"Back":
			return Color("#fff2cc")
	return body


## 个体地盘的最小间距。按体型缩放：扁胖型体长 0.6 m × size_scale。
## 1.7 个体长是"看得出是分开的鱼、又不至于散成零星散点"的分界。
##
## 这里必须乘 size_scale。上一轮写死 1.0 m，鱼缩到一半后间距相对体型翻倍，
## 10 条小鱼摊在 4 m 地盘里就成了点缀水面的散点，读不出"一群"。
func min_gap_for(total: int) -> float:
	var body_length := 0.60 * size_scale
	if total <= 3:
		return body_length * 1.85
	return body_length * 1.70


## 本群实际使用的颜色集合。水面群 3 色，水下群仍按网页版整群一色轮换。
func resolved_colors() -> Array:
	match palette:
		"surface":
			var out: Array = []
			for hex in SURFACE_SETS[palette_index % SURFACE_SETS.size()]:
				out.append(Color(hex))
			return out
		"dive":
			return [Color(DIVE_PALETTE[palette_index % DIVE_PALETTE.size()])]
	return [color]


## 主色（第一色）。旧调用点和验收用它做"配色不脏"的取值。
func resolved_color() -> Color:
	return resolved_colors()[0]


## 贴水面游的群由 main 注入水面，按同一套波场取高度。
func set_water(water: MeshInstance3D) -> void:
	_water = water


## 某条鱼应当落在的**本地 y**（相对本节点的水面高度基准）。
##
## 口径：鱼最高点 = 浪面 - depth。半个体高要乘实际实例缩放，
## 否则个体 scale 0.72–1.0 的差异会让大一号的那条露出背脊。
func submerged_y(surface: float, depth: float, scale_mul: float) -> float:
	var half: float = Geometry.fish_half_height(profile) * scale_mul * size_scale
	return surface - (depth + half)


## 潜水层注入水下材质：颜色仍按部件走，但换成带深度雾、焦散和头灯的统一材质。
## 水雾会把颜色往青绿方向洗，所以需要一点自发光保住色相；
## 但给到 0.6 以上就整体抬成浅金/奶白（网页版是饱和的 #ffc55c / #66dcf2），
## 0.30 刚好抵掉雾的洗色而不漂白。
##
## 注意：水下群是**整群一色**（网页版按群轮换四色），颜色必须写在 albedo 上。
## 水下材质走的是自定义 shader，MultiMesh 实例色只被内置材质乘进 COLOR，
## 自定义 shader 的 COLOR 拿不到实例色 —— 这里若给白 albedo + 顶点色，
## 整群鱼会变成白鱼（实测）。群内多色只在 surface 上用（StandardMaterial3D）。
func apply_underwater_materials(lib: Script) -> void:
	for key in _parts:
		var part: MultiMeshInstance3D = _parts[key]
		var part_color: Color = part.get_meta("part_color")
		var linear := part_color.srgb_to_linear()
		var glow := 0.0 if key == "Eyes" else 0.0
		part.material_override = lib.from_color(part_color, {
			"emissive": [linear.r, linear.g, linear.b],
			"emissive_strength": glow,
		})


## 某个个体在相位 a 时的平面位移（相对它自己的地盘中心）。
##
## 三项叠出来的：椭圆本轨 → 整条轨道按个体朝向转一个角度 → 侧向小幅摆动。
## 只用椭圆本轨时全群是"一圈排队"；加了轨道转向，轨迹互相穿插，
## 再加一点点侧摆，路线就不再是规整椭圆，盯着看才像在绕弯。
func _offset_at(a: float, m: Dictionary, orbit: Vector2) -> Vector3:
	var local := Vector3(cos(a) * orbit.x, 0.0, sin(a) * orbit.y).rotated(Vector3.UP, float(m.tilt))
	var side := Vector3(-local.z, 0.0, local.x)
	if side.length_squared() > 0.000001:
		side = side.normalized()
	return local + side * sin(a * 2.0 + float(m.phase)) * 0.10 * size_scale


func sample(t: float) -> void:
	if _parts.is_empty():
		return
	elapsed = t
	transforms.clear()
	var body_mm: MultiMesh = (_parts["Body"] as MultiMeshInstance3D).multimesh
	var back_mm: MultiMesh = null
	if _parts.has("Back"):
		back_mm = (_parts["Back"] as MultiMeshInstance3D).multimesh
	var eyes_mm: MultiMesh = (_parts["Eyes"] as MultiMeshInstance3D).multimesh
	var fin_mm: MultiMesh = (_parts["Fin"] as MultiMeshInstance3D).multimesh
	var origin := global_position
	for i in members.size():
		var m: Dictionary = members[i]
		var offset: Vector3 = m.offset
		var member_phase: float = m.phase
		# 低频加减速：纯等速圆周读起来像机械转盘。±0.30 rad 的慢摆动让整群
		# 有"一起快一阵、又缓下来"的呼吸感，但不会打乱个体的相位关系。
		var a: float = t * swim_speed * float(m.speed) + member_phase + phase \
			+ sin(t * 0.55 + member_phase * 1.7) * 0.30
		# 巡游半径要跟着体型缩放：鱼缩到一半、轨道还按原尺寸给，
		# 单条鱼的游程就会盖住整个地盘，群被拉散成沿水面的散点。
		var orbit := orbit_radius * float(m.squash) * size_scale
		var local := _offset_at(a, m, orbit)
		var px: float = offset.x + local.x
		var pz: float = offset.z + local.z
		var py: float = offset.y + sin(t * 0.7 + member_phase) * bob
		if ride_water and _water != null:
			# 跟随同一套波场取浪面，再整体压到浪面以下 depth 米 ——
			# 这样浪峰浪谷都不会把鱼推到水面上（沉深相对浪面恒定）。
			var surface: float = _water.sample_surface(Vector2(origin.x + px, origin.z + pz)).x
			py = submerged_y(surface, float(m.depth), float(m.scale))
		# 摆尾相位同时驱动身体侧倾、头部小幅摆和尾鳍，读起来才是一条鱼在游。
		var swish := sin(t * 9.0 + member_phase)
		# 朝向取路线切线。用有限差分而不是解析式：轨道转向和侧摆都参与了
		# 位置计算，解析式会漏掉侧摆那一项，鱼会"斜着游"。
		var ahead := _offset_at(a + 0.06, m, orbit)
		var step := ahead - local
		var yaw := atan2(step.x, step.z) + swish * 0.05
		var basis := Basis.from_euler(Vector3(cos(t * 0.7 + member_phase) * 0.06, yaw, -swish * 0.10))
		basis = basis.scaled(Vector3.ONE * float(m.scale) * size_scale)
		var body_xf := Transform3D(basis, Vector3(px, py, pz))
		transforms.append(body_xf)
		body_mm.set_instance_transform(i, body_xf)
		if back_mm != null:
			back_mm.set_instance_transform(i, body_xf)
		eyes_mm.set_instance_transform(i, body_xf)
		var fin_xf := Transform3D(basis * Basis(Vector3.UP, swish * 0.55),
			body_xf.origin + basis * Geometry.FISH_TAIL_AT)
		fin_mm.set_instance_transform(i, fin_xf)
	# 场景装饰检查按 instance_transforms 量包围盒，保持旧契约。
	(_parts["Body"] as MultiMeshInstance3D).set_meta("instance_transforms", transforms.duplicate())


func _process(delta: float) -> void:
	if not autonomous or not is_visible_in_tree():
		return
	elapsed += delta
	sample(elapsed)


func _add_part(key: String, mesh: Mesh, base_color: Color, glow := 0.0) -> void:
	# 基底必须是白 + 开顶点色：每条鱼的颜色由 MultiMesh 实例色给，
	# 材质若还带自己的 albedo，实例色会被再乘一次，整群压成同一个色相。
	var mat := Geometry.fish_material(Color.WHITE, 0.0)
	mat.vertex_color_use_as_albedo = true
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = base_color * glow
	# 水面群的尾巴是一片薄扇形，单面材质从下方看会消失。
	if key == "Fin" and profile == "flat":
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# use_colors 必须先于 instance_count 打开，后开会把已写的实例数据清掉。
	multimesh.use_colors = true
	multimesh.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.name = key
	instance.multimesh = multimesh
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta("part_color", base_color)
	add_child(instance)
	_parts[key] = instance
