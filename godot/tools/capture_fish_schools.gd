extends SceneTree
## 鱼群专项验收：模型/动画/配色/单群散布，以及真实渲染近景证据。
## 运行：python scripts/run_verification.py visual-fish-schools --full-world
##
## 为什么单独一个工具：鱼群是"看得见才算过"的资产。旧版只有一个"鱼在动"的断言，
## 于是椭球+棱锥拼的鱼、被水膜洗白的颜色、共心挤成一圈，全都能通过测试。
## 这里把当时肉眼才发现的问题各自变成一条会失败的断言。
var main: Node
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func shot(label: String, target: Vector3, distance: float, orbit: Vector3) -> void:
	main.cam.target = target
	main.cam.distance = distance
	main.cam.orbit_dir = orbit
	main.cam.refresh()
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/fish-schools-" + label + ".png")


## 鱼身上真实落到的屏幕色（鱼像素的中位饱和度）。
##
## 为什么要在测试里采样屏幕：色板是"输入色"，沉到水下以后会被水面逐通道吸收
## （红吸得最狠），输入 s=0.87 的琥珀上屏只剩 s≈0.4，读成土黄。
## 只查色板 hex 的饱和度，等于没查"颜色是不是真的到了玩家眼睛里"。
##
## 像素集合用**差分**取，不按投影坐标猜：同一机位拍两张（有鱼 / 藏掉鱼），
## 差值非零的像素就是鱼本身。按投影点采样两次都被坑过：
## ① 截图分辨率(1280×800)不等于渲染分辨率(1600×1000)，坐标要缩放；
## ② 鱼身上的点和水面泡沫、岸边高光挨得太近，采到的常是背景。
func onscreen_saturation(school: Node3D) -> float:
	# 相机必须先对准这个群：三条群隔了 20 多米，用同一个机位采样会全部落在屏幕外。
	main.cam.target = school.global_position + Vector3(0, 0.3, 0)
	main.cam.distance = 8.0
	main.cam.orbit_dir = Vector3(-0.3, 0.92, 0.5)
	main.cam.refresh()
	school.sample(1.3)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	var with_fish: Image = root.get_texture().get_image().duplicate()

	school.visible = false
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var without_fish: Image = root.get_texture().get_image().duplicate()
	school.visible = true

	var values: Array = []
	for y in range(0, with_fish.get_height(), 2):
		for x in range(0, with_fish.get_width(), 2):
			var on := with_fish.get_pixel(x, y)
			var off := without_fish.get_pixel(x, y)
			# 差值小的是噪点与抗锯齿过渡，只取"确实被鱼改变了"的像素。
			var d: float = absf(on.r - off.r) + absf(on.g - off.g) + absf(on.b - off.b)
			if d < 0.02:
				continue
			values.append(Color(on.r, on.g, on.b).s)
	if values.is_empty():
		return 0.0
	values.sort()
	return values[values.size() / 2]

## 某个水面群实际使用的体型倍率（从第一个实例的基向量长度推）。
func fish_scale(school: Node3D) -> float:
	if school.transforms.is_empty():
		return 0.0
	return (school.transforms[0] as Transform3D).basis.get_scale().length() / sqrt(3.0)

## 某条鱼**最高点**在浪面之下的深度（正值 = 沉在水下多少米）。
##
## 口径必须取最高点，不能取鱼心：按鱼心算的话，半个体高又朝上，
## 大一号的那几条会正好把背脊顶到浪面上，被半透明水膜压成一片灰白。
## 半高要从实例基向量反推，不能用常量 —— 个体 scale 在 0.72–1.0 之间浮动。
func top_depth(world: Vector3, xf: Transform3D, water: MeshInstance3D) -> float:
	var half: float = 0.11 * xf.basis.get_scale().length() / sqrt(3.0)
	var surface: float = water.position.y + water.sample_surface(Vector2(world.x, world.z)).x
	return surface - (world.y + half)

## 全群最浅的那条鱼沉多深（正值 = 在水下）。任何一条露出水面都会让它变小甚至为负。
func shallowest_depth(school: Node3D, water: MeshInstance3D) -> float:
	if water == null:
		return INF
	var best := INF
	school.sample(1.3)
	for i in school.transforms.size():
		var xf: Transform3D = school.transforms[i]
		var world: Vector3 = (school as Node3D).global_position + xf.origin
		best = minf(best, top_depth(world, xf, water))
	return best

## 全群最深的那条鱼沉多深。
func deepest_depth(school: Node3D, water: MeshInstance3D) -> float:
	if water == null:
		return INF
	var best := -INF
	school.sample(1.3)
	for i in school.transforms.size():
		var xf: Transform3D = school.transforms[i]
		var world: Vector3 = (school as Node3D).global_position + xf.origin
		best = maxf(best, top_depth(world, xf, water))
	return best

## 单群内两两最近距离（按个体地盘算）。扁胖鱼长 0.6 m，贴到 0.4 m 以内就糊成一团。
func min_pair_distance(school: Node3D) -> float:
	var best := INF
	var points: Array = []
	for member in school.members:
		var m: Dictionary = member
		var offset: Vector3 = m.offset
		points.append(Vector2(offset.x, offset.z))
	for i in points.size():
		for j in range(i + 1, points.size()):
			best = minf(best, points[i].distance_to(points[j]))
	return best

## 单群在若干时刻里铺开的总跨度（最远两条鱼之间的距离）。
func school_span(school: Node3D, steps := 12) -> float:
	var span := 0.0
	for s in steps:
		school.sample(float(s) * 0.9)
		for i in school.transforms.size():
			for j in range(i + 1, school.transforms.size()):
				var a: Vector3 = (school.transforms[i] as Transform3D).origin
				var b: Vector3 = (school.transforms[j] as Transform3D).origin
				span = maxf(span, Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)))
	return span

## 单条鱼的游程直径：盯住第 0 条，量它一段时间里走过的最大位移。
## 这条断言的用途是把"在原地抖"和"真的游一圈"分开 —— 只查"在动"是不够的。
func fish_travel(school: Node3D, steps := 16) -> float:
	var pts: Array = []
	for s in steps:
		school.sample(float(s) * 0.8)
		pts.append((school.transforms[0] as Transform3D).origin)
	var best := 0.0
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			best = maxf(best, (pts[i] as Vector3).distance_to(pts[j]))
	return best

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set("_autosave_on", false)
	root.get_node("Economy").ticking = false
	for i in 6:
		await process_frame
	main.hud.hide()
	main.markers.hide()
	main.ribbon.hide()
	main.cam.suspend_follow()

	var animals := main.get_node("World/Environment/Animals")
	var surface_schools: Array = []
	for child in animals.get_children():
		if child.get("asset_id") == "SEA-DECO-ANIMAL-FISH-SCHOOL":
			surface_schools.append(child)
	check(surface_schools.size() == 3, "三条水面装饰鱼群存在（实际 %d）" % surface_schools.size())

	for school in surface_schools:
		school.set("autonomous", false)
		check(school.profile == "flat", "%s 用网页版扁胖型（水面）" % school.name)
		check(school.members.size() == school.count, "%s 条数与声明一致（%d）" % [school.name, school.count])
		# 水面群要"稀疏"：18 条挤在同一片地盘里读不出"一群鱼"。
		check(school.count <= 12, "%s 每群不超过 12 条（实际 %d）" % [school.name, school.count])
		# 体型：网页版原尺寸在 Godot 的俯视机位下显得臃肿，水面群要小一半。
		# 这里卡的是"实际渲染出来的身体半长"，不是 size_scale 这个旋钮 ——
		# 改旋钮名不该让断言失效，改体型才该。
		check(fish_scale(school) <= 0.62, "%s 体型已缩小（倍率 %.2f）" % [school.name, fish_scale(school)])
		# 沉深：整条鱼要压在水下 0.5–1.5 m（按最高点算，不是鱼心）。
		# 卡在 0.45 而不是 0.5，是给波浪采样与实例缩放的浮点余量留一格；
		# 上限 1.6 是"再深就被水色吃掉"的边界，超过就不是"景观鱼"了。
		var water: MeshInstance3D = main.get("water_node")
		var shallow := shallowest_depth(school, water)
		var deep := deepest_depth(school, water)
		check(shallow >= 0.45, "%s 没有一条露出水面（最浅 %.2f m）" % [school.name, shallow])
		check(shallow <= 0.85, "%s 整群没有全挤在最浅一档（最浅 %.2f m）" % [school.name, shallow])
		check(deep <= 1.6, "%s 最深一条没沉过头（%.2f m）" % [school.name, deep])
		check(deep - shallow >= 0.25, "%s 群内有纵深层次（%.2f m 差）" % [school.name, deep - shallow])
		# 单群散布：不能共心排成一圈；也不能挤成一小坨（反馈原话是"散开一些"）。
		check(min_pair_distance(school) > 0.45, "%s 单群个体散开（最近 %.2f m）" % [school.name, min_pair_distance(school)])
		var span := school_span(school)
		check(span >= 3.0, "%s 整群铺开跨度够大（%.2f m）" % [school.name, span])
		# 每条鱼自己的游程：只查"两个时刻位移不同"会把原地抖也算成在游。
		var travel := fish_travel(school)
		check(travel >= 1.0, "%s 单条鱼真的游得开（游程直径 %.2f m）" % [school.name, travel])
		# 配色：每个群 2–3 种颜色，且每种都真的发到了鱼身上（不是只写在常量里）。
		var set_colors: Array = school.resolved_colors()
		check(set_colors.size() >= 2 and set_colors.size() <= 3, "%s 群内 %d 色" % [school.name, set_colors.size()])
		for c in set_colors:
			check((c as Color).s > 0.5 and (c as Color).v > 0.6,
				"%s 配色不脏 %s（s=%.2f v=%.2f）" % [school.name, (c as Color).to_html(false), (c as Color).s, (c as Color).v])
		var used := {}
		for member in school.members:
			used["#" + (member.color as Color).to_html(false)] = true
		check(used.size() == set_colors.size(), "%s 每条鱼都拿到了色板里的颜色（实际用到 %d / %d）"
			% [school.name, used.size(), set_colors.size()])
		# 色相要真的分得开，三支同一色系的"丰富"是假的。
		var hues: Array = []
		for c in set_colors:
			hues.append((c as Color).h)
		var spread := 0.0
		for i in hues.size():
			for j in range(i + 1, hues.size()):
				var d: float = absf(hues[i] - hues[j])
				spread = maxf(spread, minf(d, 1.0 - d))
		check(spread >= 0.12, "%s 群内色相拉得开（最大 %.2f）" % [school.name, spread])
		# 动画：两个时刻的实例变换必须不同。
		school.sample(0.0)
		var before: Transform3D = school.transforms[0]
		school.sample(2.0)
		check(not before.is_equal_approx(school.transforms[0]), "%s 真的在游" % school.name)
		# 全程采样：8 个时刻里任何一条鱼的**最高点**都不许冒到浪面之上。
		# 这条会抓"某一帧被浪推到水面"—— 只看一个时刻是不够的，浪是动的。
		var surfaced := 0
		var min_seen := INF
		for step in 8:
			school.sample(float(step) * 0.7)
			for i in school.transforms.size():
				var xf: Transform3D = school.transforms[i]
				var world: Vector3 = (school as Node3D).global_position + xf.origin
				var depth := top_depth(world, xf, water)
				min_seen = minf(min_seen, depth)
				if depth <= 0.0:
					surfaced += 1
		check(surfaced == 0, "%s 全程没有一条冒出水面（最小沉深 %.2f m，露出 %d 次）"
			% [school.name, min_seen, surfaced])
		check(min_seen >= 0.45, "%s 全程沉深都不低于 0.45 m（最小 %.2f m）" % [school.name, min_seen])

	# 可捕捞鱼群：同一套网页版模型与动画。
	var catch_school: Dictionary = main.props.nearest_school(Vector3(-3, 1.12, 18), 400.0)
	check(not catch_school.is_empty(), "存在可捕捞鱼群")
	if not catch_school.is_empty():
		var root_node: Node3D = catch_school.root
		check(root_node.fish.size() >= 3 and root_node.fish.size() <= 6, "3–6 条小群")
		var min_gap := INF
		for i in root_node.offsets.size():
			for j in range(i + 1, root_node.offsets.size()):
				min_gap = minf(min_gap, Vector2(root_node.offsets[i].x, root_node.offsets[i].z)
					.distance_to(Vector2(root_node.offsets[j].x, root_node.offsets[j].z)))
		check(min_gap > 0.4, "单群个体散开（最近 %.2f m）" % min_gap)
		# 网页版 6 色里粉红/金黄本身饱和度中等，0.5 是可用的下限；
		# 旧版的土黄族饱和度能过这条，但色相偏褐——所以同时卡明度和色相跨度。
		var hues: Array = []
		for hex in root_node.COLORS:
			var c := Color(hex)
			check(c.s > 0.5 and c.v > 0.6, "配色不脏 %s（s=%.2f v=%.2f）" % [hex, c.s, c.v])
			hues.append(c.h)
		check(hues.size() == 6, "六色轮换")
		check(root_node.ripple != null and root_node.get_node_or_null("SurfaceRipple") != null, "涟漪圈存在")
		# 只允许一层圈。build() 被调两次时 add_child 会叠出两圈，
		# 参数怎么调都调不淡（两层 alpha 合成）——这是调参不生效最常见的原因。
		var ripple_nodes := 0
		for child in root_node.get_children():
			if String(child.name).begins_with("SurfaceRipple"):
				ripple_nodes += 1
		check(ripple_nodes == 1, "涟漪只有一层（实际 %d）" % ripple_nodes)
		# 涟漪要淡、要少：旧版双圈 + 两道脉冲、0.56，俯视是四条同心亮环。
		# 这三条锁的是"圈不许比鱼抢眼"，不是某个具体参数名的美观值。
		var ripple_mat: ShaderMaterial = (root_node.ripple as MeshInstance3D).material_override as ShaderMaterial
		var ripple_opacity: float = float(ripple_mat.get_shader_parameter("opacity"))
		check(ripple_opacity <= 0.35, "涟漪透明度压低（%.2f）" % ripple_opacity)
		check(float(ripple_mat.get_shader_parameter("ring_count")) <= 1.0, "涟漪只留一圈开环")
		check(float(ripple_mat.get_shader_parameter("wave_count")) <= 1.0, "涟漪只留一道外扩脉冲")
		# 只降 alpha 不够：圈色本身是近白，20% 叠在深蓝水上仍是一道亮环。
		var ripple_tint = ripple_mat.get_shader_parameter("ring_tint")
		check(ripple_tint is Vector3 and (ripple_tint as Vector3).length() < 1.5,
			"涟漪亮度压到水面档（非近白）")

		# 鱼整条沉到水里：按最高点算沉深（同装饰群口径），不是鱼心。
		# 下限 0.25 锁"确实进了水"，上限 0.9 锁"没沉成水底暗点、还点得中"。
		var catch_water: MeshInstance3D = main.get("water_node")
		root_node.animate(3.0, catch_water)
		var catch_shallow := INF
		var catch_deep := -INF
		for i in root_node.fish.size():
			var f: Node3D = root_node.fish[i]
			var xf := Transform3D(Basis.IDENTITY.scaled(f.scale), f.position)
			var world: Vector3 = root_node.global_position + f.position
			var d := top_depth(world, xf, catch_water)
			catch_shallow = minf(catch_shallow, d)
			catch_deep = maxf(catch_deep, d)
			check(d >= 0.25, "可捕捞鱼 %d 整条在水面之下（最高点沉深 %.2f m）" % [i, d])
			check(d <= 0.9, "可捕捞鱼 %d 没有沉过头（%.2f m）" % [i, d])
		check(catch_deep - catch_shallow >= 0.01, "可捕捞群有纵向层次（%.2f m 差）" % (catch_deep - catch_shallow))

		# 漂流物资的圈保持旧观感：这次只压鱼群，不许顺手把场景里的圈一起调淡。
		var crate: Dictionary = main.props.nearest_crate(Vector3(-3, 1.12, 18), 400.0)
		if not crate.is_empty():
			var crate_ring: MeshInstance3D = crate.get("ring")
			var crate_mat: ShaderMaterial = crate_ring.material_override as ShaderMaterial
			check(is_equal_approx(float(crate_mat.get_shader_parameter("opacity")), 0.56),
				"漂流物资的圈没被鱼群的调参牵连（%.2f）" % float(crate_mat.get_shader_parameter("opacity")))
			check(float(crate_mat.get_shader_parameter("ring_count")) >= 1.5, "漂流物资仍是双圈")
		# 可捕捞群是交互目标，必须保持网页版原尺寸（曾一度缩到 0.5，结果难辨认也难点）。
		var catch_scale: float = (root_node.fish[0] as Node3D).scale.length() / sqrt(3.0)
		check(catch_scale >= 0.85, "可捕捞鱼群保持原尺寸（倍率 %.2f）" % catch_scale)
		# 装饰群则是氛围，要明显更小；两者不同是有意分化。
		check(catch_scale > fish_scale(surface_schools[0]) * 1.5,
			"可捕捞群显著大于装饰群（%.2f vs %.2f）" % [catch_scale, fish_scale(surface_schools[0])])

	# 巨鲸：构件表必须和网页版一致，否则又会退化成"一根香肠"。
	# 网页版 gameplay.js 是 头球 + 躯干球 + 两块 Box 胸鳍 + 圆锥尾段 + 一块 Box 尾鳍。
	var whale: Node3D = animals.get_node_or_null("Whale")
	check(whale != null, "巨鲸节点存在")
	if whale != null:
		whale.set_process(false)
		whale.call("sample", 0.0)
		var body: Node3D = whale.get("body")
		var names: Array = []
		for child in body.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).name != "Rim":
				names.append(String((child as MeshInstance3D).name))
		check(names.has("Head") and names.has("Torso"), "鲸有头与躯干两块椭球（实际 %s）" % str(names))
		var fins := 0
		for n in names:
			if n.begins_with("PectoralFin"):
				fins += 1
		check(fins == 2, "鲸有两块胸鳍（实际 %d）" % fins)
		var tail: Node3D = whale.get("tail")
		var fluke: Node3D = whale.get("fluke")
		check(tail != null and tail.get_node_or_null("TailSegment") != null, "鲸有圆锥尾段")
		check(tail != null and fluke != null, "鲸有尾枢轴与尾鳍枢轴")
		if fluke != null:
			var blade = fluke.get_node_or_null("FlukeBlade")
			check(blade != null and (blade as MeshInstance3D).mesh is BoxMesh, "尾鳍是一块 Box（同网页版）")
		# 材质契约：普通标准材质，只接光照与阴影，没有任何额外效果。
		# 2026-10-28 第四次修订前的断言是反过来的（必须走 toon + 开 depth_tint + 有补偿光），
		# 现在改成"盯住这些效果不许回来"——否则下次谁顺手加回自发光，这里不会红。
		var head_node: MeshInstance3D = body.get_node("Head")
		# 先按 Material 接住再判类型：直接声明成 StandardMaterial3D 时，
		# 若材质被改回 ShaderMaterial 会抛"类型不能赋值"的脚本错误并中断整轮，
		# 那样失败信息只剩一行类型错误，看不出是哪条契约破了。
		var head_any: Material = head_node.material_override
		check(head_any != null and head_any is StandardMaterial3D,
			"鲸皮肤是普通 StandardMaterial3D（实际 %s）" % ("null" if head_any == null else head_any.get_class()))
		if head_any is StandardMaterial3D:
			var head_mat: StandardMaterial3D = head_any
			check(not head_mat.emission_enabled, "鲸没有自发光")
			check(head_mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED,
				"鲸接光照（不是 UNSHADED）")
			# 深灰：色相接近中性（不要偏成蓝），亮度落在深灰区间而不是黑。
			var skin := head_mat.albedo_color
			var lum := skin.get_luminance()
			check(lum >= 0.28 and lum <= 0.48, "鲸皮肤是深灰（亮度 %.2f）" % lum)
			var spread: float = maxf(skin.r, maxf(skin.g, skin.b)) - minf(skin.r, minf(skin.g, skin.b))
			check(spread < 0.10, "鲸皮肤接近中性灰（色偏 %.3f）" % spread)
			check(head_mat.roughness >= 0.7, "鲸粗糙度高，浅水段不被镜面反光打成亮斑（%.2f）" % head_mat.roughness)
			check(is_equal_approx(head_mat.metallic, 0.0), "鲸不做金属材质")
		# 描边是额外一层 mesh；本次明确摘掉，任何 Rim 节点回来都算回归。
		var rim_nodes := 0
		for child in body.get_children():
			if String(child.name).begins_with("Rim"):
				rim_nodes += 1
		check(rim_nodes == 0, "鲸没有描边壳（实际 %d 个 Rim 节点）" % rim_nodes)
		var fin_node: MeshInstance3D = body.get_node("PectoralFinR")
		var fin_any: Material = fin_node.material_override
		check(fin_any is StandardMaterial3D and not (fin_any as StandardMaterial3D).emission_enabled,
			"鲸胸鳍同为普通材质且无自发光")
		# 沉深：位置按主人指定锚定到「阳光房海下基座倒数第三层楼板」。
		# 基座 7 层、间距 2.58，从底往上 y = -17.02/-14.44/-11.86 → 取 -11.86。
		# 该层距水面 12.98 m：水面俯视只剩一层淡影（实拍 -12 档已验证），
		# 正是主人要的「隐约剪影」。这里把锚定关系写成断言，改基座层高时会提醒同步。
		var sway: float = float(whale.get("dive_sway"))
		var depth: float = 1.12 - whale.global_position.y
		check(is_equal_approx(whale.global_position.y, -11.86),
			"鲸锚定在阳光房基座倒数第三层（y=%.2f，应为 -11.86）" % whale.global_position.y)
		check(depth >= 12.0 and depth <= 14.0,
			"鲸在水下 12–14 m 的隐约剪影档（距水面 %.2f m）" % depth)
		check(sway >= 1.0, "鲸的下潜幅度够（%.2f m，要求 ≥ 1.0）" % sway)
		# 起伏最高点仍要在水下，否则鲸背会穿出水面。
		var top_y: float = whale.global_position.y + sway + 1.207
		var clearance: float = 1.12 - top_y
		check(clearance > 1.0, "鲸背在起伏最高点仍在水下（余量 %.2f m）" % clearance)
		# 摆尾：两个时刻的尾鳍角度必须不同。
		whale.call("sample", 0.0)
		var a: float = (tail as Node3D).rotation.y
		whale.call("sample", 1.0)
		check(not is_equal_approx(a, (tail as Node3D).rotation.y), "鲸尾真的在摆")

	# 抓图证据：三条水面群 + 可捕捞群。
	await shot("surface-home", surface_schools[0].global_position + Vector3(0, 0.3, 0), 7.0, Vector3(-0.35, 0.9, 0.55))
	# 上屏饱和度：色板对不够，还要看颜色真的到了眼睛里（水面会吸收掉一档）。
	for school in surface_schools:
		var sat := await onscreen_saturation(school)
		var swatches: Array = []
		for m in school.members.slice(0, 3):
			swatches.append((m.color as Color).to_html(false))
		print("[fish-schools] %s onscreen_saturation=%.2f swatches=%s"
			% [school.name, sat, str(swatches)])
		check(sat >= 0.35, "%s 上屏颜色没有水土化（中位饱和度 %.2f）" % [school.name, sat])
	if not catch_school.is_empty():
		await shot("catch", (catch_school.root as Node3D).global_position + Vector3(0, 0.3, 0), 7.0, Vector3(-0.2, 0.93, 0.3))
	await shot("wide", surface_schools[0].global_position, 24.0, Vector3(-0.5, 0.78, 0.6))
	if whale != null:
		var wp: Vector3 = (whale.get("body") as Node3D).global_position
		await shot("whale-top", wp, 22.0, Vector3(-0.01, 1.0, 0.05))
		await shot("whale-quarter", wp, 20.0, Vector3(0.62, 0.62, 0.48))

	# 水下群：minimal 版本锁死潜水，只有 --full-world 能进。
	if main.get("dive") != null and not main.dive.active:
		main.call("_on_dive")
	if main.get("dive") != null and main.dive.active:
		var uw: Node3D = main.dive
		uw.call("freeze_time", 3.0)
		uw.call("debug_teleport", Vector3(-5, -13, -8))
		for i in 10:
			await process_frame
		var deco: Node = uw.get("deco")
		var dive_schools: Array = deco.get("_fish")
		check(dive_schools.size() == 7, "七群水下鱼（实际 %d）" % dive_schools.size())
		# 色板从组件自身读，避免测试里再抄一份——抄一份就会在调色后变成假失败。
		var dive_palette: Array = (dive_schools[0].component as Node3D).DIVE_PALETTE
		for i in dive_schools.size():
			var school: Node3D = dive_schools[i].component
			check(school.profile == "slim", "水下群用网页版细长型")
			check(dive_palette[i % 4] == "#" + school.resolved_color().to_html(false),
				"水下群按网页版四色轮换（%s）" % school.resolved_color().to_html(false))
			check(min_pair_distance(school) > 0.45, "水下群单群散开")
		uw.set_process(false)
		var cam: Camera3D = uw.get("camera")
		cam.global_position = Vector3(-3.0, -12.6, -12.0)
		cam.look_at(Vector3(-5.0, -13.0, -16.0))
		deco.call("update", 0.0, 3.0, Vector3(-5, -13, -8), cam)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/fish-schools-uw-side.png")
		uw.set_process(true)
	else:
		print("[fish-schools] 潜水段未执行（当前为最小版本范围，需 --full-world）")

	print("[fish-schools] ", checks, " checks, failures=", failures)
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
