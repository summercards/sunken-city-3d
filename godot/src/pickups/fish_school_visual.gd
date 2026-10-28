extends Node3D
## 海面可捕捞鱼群的外观：模型与游动动画直接移植网页版 fish-schools.js。
##
## 网页版一条鱼 = 椭球身体 + 锥形尾鳍 + 一颗深色眼珠（buildFish）。
## 动画 = 每条鱼绕群心做椭圆巡游，半径 / 速度 / 深度各自随机，
## 朝向取轨道切线，尾鳍按 9 rad/s 摆（update）。
## 这里不另起一套模型：形状取自 animal_mesh.gd，和装饰鱼群共用同一份网格。
##
## 与网页版的三处刻意差异（都是 Godot 这一侧的水面/后处理造成的，改回去会退化）：
##   1. 整条鱼沉在浪面之下（SUBMERGE）。旧版抬到浪峰之上，俯视读成「贴在水膜上的一张纸」；
##      现在按「最高点离浪面多少米」压到水下，浪峰浪谷都不会把背脊顶出水面。
##   2. 每条鱼带自己的群内偏移（SPREAD）。网页版 6 条鱼共心、只靠相位错开，
##      俯视就是一个旋转木马圈——这是「单群太拥挤」的根源。
##   3. 颜色提纯并加少量自发光。环境后处理把对比度压到 0.75，albedo 直接吃光会闷成土黄。
const Geometry = preload("res://src/ambient/animal_mesh.gd")

## 网页版 6 色（fish-schools.js 是 5 色薄荷系，这 6 色沿用更早的彩色定版）。
## 关键不是"压深"，而是"提纯"：旧版把颜色压在 #e8603f 这类偏褐的橙上，
## 又让 albedo 直接吃满阳光衰减，出水后读起来就是土黄/橄榄——这才是"脏"的来源。
## 现在每个色相都往纯色推一档，靠一点自发光把明度顶住，屏幕色才干净。
const COLORS = [
	"#ff5f3d", # 珊瑚鲜橙
	"#ffc21a", # 明亮金黄
	"#ff6fae", # 樱桃粉红
	"#2fe3c8", # 荧光薄荷青
	"#2fb8ff", # 晴空亮蓝
	"#97df3c", # 鲜嫩青柠绿
]
## 个体体型。这里**保持网页版原尺寸**：可捕捞鱼群是玩家要靠近、要点的目标，
## 缩小之后变得难辨认也难点中。装饰群才需要缩小（见 decorative_fish_school.gd）。
const SIZE := 1.0
## 鱼群沉深：整条鱼的**最高点**在浪面之下的米数。
##
## 旧版是「浪峰 0.29 + 半高 0.11 + 0.02」抬到水面之上（+0.42），俯视看像贴在水膜上的一张纸。
## 现在改成按最高点算沉深：取该点真实浪高，再减去「沉深 + 该条鱼自己的半高」，
## 浪峰浪谷都不会把背脊顶出水面，整群读起来是真的在水里游。
## 0.40 m 是「还看得清颜色」的浅档（装饰群用 0.5–1.5 m）；可捕捞群是交互目标，
## 取靠水面的一档，俯视仍能一眼认出鱼形、也点得中。
const SUBMERGE := 0.40
## 群内散开半径。网页版 6 条鱼共用同一个圆心、只靠相位错开，
## 俯视看就是一个旋转木马环——这就是「单群太拥挤」的根源。
## 现在每条鱼有自己的地盘（黄金角铺开），只在自家小圈里打转。
## 鱼恢复到网页版原尺寸后，地盘半径也要跟着放大，否则间距相对体型缩水一半、又挤回去。
const SPREAD := 1.35
## 个体地盘的最小间距（米）。鱼长 0.6 m，1.3 m 约等于 2.2 个身长。
const MIN_GAP := 1.15
## 单条鱼的巡游半径。旧值 0.46–0.92 会让相邻两条鱼绕到同一点撞在一起，
## 收小到 0.30–0.58，鱼就在自己的位置上慢慢晃，群看起来更松散。
const ORBIT_MIN := 0.30
const ORBIT_MAX := 0.58
## 涟漪圈节点半径 —— 由鱼群外沿反推，不手填。
## `surface_ripple.gdshader` 画的是这条半径的 55% 和 72%（最外扩散弧到 95%），
## 所以想让 72% 那圈刚好包住「地盘外沿 + 巡游半径」，节点半径要除以 0.72。
## 拿鱼群半径直接当节点半径，鱼就会压在圈线上。
## 外沿 = SPREAD × 1.16（布局抖动上限）+ ORBIT_MAX。
const RING_INNER_RATIO := 0.72
const RING_RADIUS := (SPREAD * 1.16 + ORBIT_MAX) / RING_INNER_RATIO
## 一点自发光：抵掉水面高光压下来的暗部，颜色才不会闷成土色。
## 给到 0.3 以上会整体漂白，0.16 刚好保住色相。
const BODY_GLOW := 0.16
## 涟漪：只留一圈开环 + 一道外扩脉冲，透明度和圈本身亮度都压下去。
## 旧版是双圈 + 两道错相脉冲、透明度 0.56、圈色近白 —— 俯视是四条同心亮环，比鱼还抢眼。
## 鱼沉到水下之后对比更强（水下没有鱼身压着，圈就成画面主体），所以两个旋钮一起收：
## 只降 alpha 不够，实测 0.28 时圈峰值仍是 (225,227,215)，水面只有 (143,177,189)，
## 差的 80 级全在「近白 × 高 alpha」上，所以圈色改成本身就偏水的青灰。
## 这几项只作用于鱼群：漂流物资的圈走 make_ripple 的默认值，仍是旧观感。
const RIPPLE_OPACITY := 0.20
const RIPPLE_TINT := Color(0.34, 0.58, 0.58)
const RIPPLE_RINGS := 1.0
const RIPPLE_WAVES := 1.0

var fish: Array[Node3D] = []
## x = 相位, y = 轨道半径, z = 速度, w = 深度；每条鱼另有 offsets[i] 的群内偏移。
var motions: Array[Vector4] = []
var offsets: Array[Vector3] = []
## 每条鱼的身体 / 尾鳍节点，避免每帧 get_node。
var bodies: Array = []
var tails: Array = []
var ripple: MeshInstance3D


## 涟漪圈。opacity / rings / waves 的默认值等于旧观感（双圈 + 两道脉冲、0.56），
## 只有鱼群显式传更淡更少的参数 —— 漂流物资继续用默认值，不被鱼群的调参牵连。
static func make_ripple(radius: float, phase: float, opacity := 0.56, rings := 2.0, waves := 2.0,
		tint := Color(0.76, 0.98, 0.95)) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "SurfaceRipple"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	plane.subdivide_width = 12
	plane.subdivide_depth = 12
	node.mesh = plane
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/surface_ripple.gdshader")
	material.render_priority = 3
	material.set_shader_parameter("phase", phase)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("ring_count", rings)
	material.set_shader_parameter("wave_count", waves)
	material.set_shader_parameter("ring_tint", Vector3(tint.r, tint.g, tint.b))
	node.material_override = material
	return node


static func sync_ripple(node: MeshInstance3D, water: MeshInstance3D, time: float) -> void:
	var mat := node.material_override as ShaderMaterial
	mat.set_shader_parameter("u_time", water.time if water != null else time)
	if water != null:
		mat.set_shader_parameter("ocean_waves", water.ocean_waves)
		mat.set_shader_parameter("wave_scale", water.wave_scale)


func build(rng: RandomNumberGenerator, count: int, phase: float) -> void:
	var color_offset := int(round(phase * 3.0))
	fish.clear()
	bodies.clear()
	tails.clear()
	motions.clear()
	offsets.clear()
	# 地盘布局先算好：抖过的螺旋 + 互斥，保证 3–6 条鱼散开且不重叠。
	# 网页版共心只靠相位错开，俯视就是一个旋转木马环。
	var placements := Geometry.school_offsets(count, SPREAD, 0.78, MIN_GAP, rng)
	for i in count:
		var col := Color(COLORS[(i + color_offset) % COLORS.size()])
		var f := _fish(col)
		f.name = "Fish%02d" % i
		# 个体体型差：网页版是随机 size，这里保持可复现的确定性抖动。
		f.scale = Vector3.ONE * SIZE * (0.92 + float(i % 3) * 0.07)
		add_child(f)
		fish.append(f) # Do not rediscover duplicates by auto-renamed node names.
		bodies.append(f.get_node_or_null("Body"))
		tails.append(f.get_node_or_null("Tail"))
		# 群内地盘由 Geometry.school_offsets 统一算（抖过的螺旋 + 互斥），
		# 保证散得开又不叠在一起。
		offsets.append(placements[i])
		# Keep rng call count (4 per fish) identical for deterministic seeding.
		var p0 := rng.randf() * TAU
		var r0 := rng.randf_range(ORBIT_MIN, ORBIT_MAX)
		var spd := rng.randf_range(0.55, 1.05)
		var depth_off := rng.randf_range(0.015, 0.045)
		motions.append(Vector4(p0, r0, spd, depth_off))
	ripple = make_ripple(RING_RADIUS, phase, RIPPLE_OPACITY, RIPPLE_RINGS, RIPPLE_WAVES, RIPPLE_TINT)
	add_child(ripple)


func animate(time: float, water: MeshInstance3D) -> void:
	if fish.is_empty():
		return
	var origin := global_position
	for i in fish.size():
		var f := fish[i]
		var m := motions[i]
		var o := offsets[i]
		var a := time * m.z + m.x
		# 轨道轴比也逐个体微调，避免所有鱼挤在同一个椭圆上同频打转。
		var axis_ratio := 0.72 + 0.20 * sin(m.x * 1.7)
		var px := o.x + cos(a) * m.y
		var pz := o.z + sin(a) * m.y * axis_ratio
		# 网页版：y = 0.03 + sin(a*1.7)*0.02 + depth；网页版把鱼放在水面 +0.04 m。
		# 这里改成「最高点 = 浪面 - 沉深」：半高必须乘该条鱼自己的实例缩放
		# （0.92–1.06 浮动），否则大一号的那条会把背脊顶出水面。
		var half := Geometry.fish_half_height("flat") * f.scale.y
		var surface := 0.0
		if water != null:
			surface = water.sample_surface(Vector2(origin.x + px, origin.z + pz)).x
		# m.w 是每条鱼的深度微差（0.015–0.045），叠在沉深上，整群才有纵向层次。
		var py := surface - (SUBMERGE + half + m.w) + sin(a * 1.7) * 0.02
		f.position = Vector3(px, py, pz)
		# 朝向 = 轨道切线（网格鼻尖朝 +Z）。
		var vx := -sin(a) * m.y
		var vz := cos(a) * m.y * axis_ratio
		var swish := sin(time * 9.0 + m.x * 3.0)
		f.rotation.y = atan2(vx, vz) + swish * 0.05
		f.rotation.z = -swish * 0.10
		f.rotation.x = cos(time * 1.6 + m.x) * 0.05
		var tail: Node3D = tails[i]
		if tail != null:
			tail.rotation.y = swish * 0.5
	sync_ripple(ripple, water, time)


func _part(parent: Node3D, mesh: Mesh, color: Color, glow: float) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = Geometry.fish_material(color, glow)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


## 一条鱼：扁胖身体（含背脊高光）、双眼、可摆动的尾鳍。鼻尖朝 +Z。
func _fish(color: Color) -> Node3D:
	var f := Node3D.new()
	var body := _part(f, Geometry.fish_hull("flat"), color, BODY_GLOW)
	body.name = "Body"
	_part(body, Geometry.fish_eyes("flat"), Color("#112e35"), 0.0)
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Geometry.tail_pivot("flat")
	f.add_child(tail)
	var fin := _part(tail, Geometry.fish_fin("flat"), color.lightened(0.12), BODY_GLOW)
	# 薄扇形尾鳍没有背面，不双面渲会从下方看穿。
	(fin.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	return f
