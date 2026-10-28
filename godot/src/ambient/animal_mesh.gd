extends RefCounted
## 鱼体几何与群内布局。水体折射的深度预通道能看到这些不透明网格。
##
## 只放鱼和鱼群的东西。鲸自己拼（见 decorative_whale.gd），不走这里 —— 
## 鲸的构件是"球 + 圆锥 + Box"，和鱼的"椭球 + 尾鳍"没有共用件，
## 硬塞一个通用 ellipsoid() 进来只会让两边都变模糊（上一版就是这样退化成香肠的）。
##
## 网页版有两套鱼，形状并不相同，硬套一套就会读错：
##   web/fish-schools.js      水面可捕捞鱼群：扁胖型，半径 (0.17, 0.11, 0.30)，宽 > 高；
##   web/underwater-art.js    水下鱼群：细长型，半径 (0.28, 0.13, 0.09)，长轴在前。
## 俯视机位下扁胖型才看得出「背宽、侧薄」的鱼形，细长型在俯视下会像一根叶子。
##
## 所有变体鼻尖朝 +Z，并按最终尺寸烘进网格；实例矩阵只负责位置和朝向。

## 扁胖型（水面）：半轴 宽 / 高 / 长。
const FLAT_BODY := Vector3(0.17, 0.11, 0.30)
## 背脊高光是一道窄条，不是盖在背上的白斑：宽 3 cm、长 15 cm，贴着脊线。
const FLAT_BACK := Vector3(0.032, 0.028, 0.150)
const FLAT_BACK_AT := Vector3(0.0, 0.092, 0.010)
## 眼睛必须落在身体表面之内（椭球在 z=0.175 处半宽只剩 0.081，取 0.078 才贴住）。
const FLAT_EYE := Vector3(0.030, 0.030, 0.026)
const FLAT_EYE_AT := Vector3(0.078, 0.042, 0.175)
const FLAT_TAIL_AT := Vector3(0.0, 0.0, -0.275)
## 横扇尾鳍：长度（纵深）与尾端半宽。半宽取 0.19 —— 略大于身体半宽 0.17，
## 俯视看才是"鱼尾"而不是"针"；再大就会比鱼身还宽，读成一个菱形。
const FLAT_FIN_LENGTH := 0.30
const FLAT_FIN_HALF_WIDTH := 0.19
const FLAT_FIN_RADIUS := 0.16
const FLAT_FIN_THICKNESS := 0.0

## 细长型（水下）：网页版是 (0.28, 0.13, 0.09)，长轴在前、薄在侧面。
## 转到「鼻尖朝 +Z」后就是 薄 0.09 / 高 0.13 / 长 0.28。
## 别把宽高写反：宽 > 高会变成比目鱼，俯视是一张叶子，侧看是一根棍。
const SLIM_BODY := Vector3(0.090, 0.130, 0.280)
const SLIM_BACK := Vector3(0.030, 0.030, 0.130)
const SLIM_BACK_AT := Vector3(0.0, 0.118, 0.050)
const SLIM_EYE := Vector3(0.024, 0.024, 0.021)
## 眼睛贴在体侧：z=0.185 处椭球半宽约 0.068，取 0.062 才嵌在表面。
const SLIM_EYE_AT := Vector3(0.062, 0.042, 0.185)
const SLIM_TAIL_AT := Vector3(0.0, 0.0, -0.245)
const SLIM_FIN_LENGTH := 0.26
const SLIM_FIN_RADIUS := 0.125
const SLIM_FIN_THICKNESS := 0.0

## 兼容旧调用点（尾鳍枢轴取细长型）。
const FISH_TAIL_AT := SLIM_TAIL_AT

static var _cache := {}


## 卡通实体材质：toon 漫反射 + 关掉高光 + 可选自发光。
## 自发光是用来抵水色吸收的，给多了整条鱼会抬成灰白；水面群不要开。
static func fish_material(color: Color, glow := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color * glow
	return mat


# ------------------------------------------------------------- 分段网格
# profile: "flat"（水面）/ "slim"（水下）。

static func fish_hull(profile := "flat") -> ArrayMesh:
	var spec := _spec(profile)
	return _cached(profile + "/hull", [[_sphere(18, 10),
		Transform3D(Basis.from_scale(spec.body), Vector3.ZERO)]])


static func fish_back(profile := "flat") -> ArrayMesh:
	var spec := _spec(profile)
	return _cached(profile + "/back", [[_sphere(12, 7),
		Transform3D(Basis.from_scale(spec.back), spec.back_at)]])


## 双眼合成一份网格：两侧对称，俯视和侧视都不会缺一只眼睛。
static func fish_eyes(profile := "flat") -> ArrayMesh:
	var spec := _spec(profile)
	var parts := []
	for side in [-1.0, 1.0]:
		parts.append([_sphere(8, 5), Transform3D(Basis.from_scale(spec.eye),
			Vector3(side * spec.eye_at.x, spec.eye_at.y, spec.eye_at.z))])
	return _cached(profile + "/eyes", parts)


## 尾鳍。两种鱼型用两种尾形，因为机位不同：
##
##   flat（水面，俯视）：横向扇形 —— 顶点接住鱼身，向后再向两侧张开成 V。
##     纯三角形网格，双面渲（薄片没有背面，单面材质从下方看会消失）。
##   slim（水下，侧视）：轴向朝后的三棱锥 —— 侧面看是一枚三角扇，
##     和网页版 `ConeGeometry(0.16, 0.34, 5)` 同一个读法。
##
## 踩过的坑（都是同一类错误：拿"看起来合理"的形状替代"在这个机位读得出"的形状）：
##   圆锥朝后 + 半径偏小 → 俯视是一条尖刺，整条鱼像叶子；
##   三棱柱躺平 + 半径给大 → 俯视变成一个比鱼身还宽的菱形。
static func fish_fin(profile := "flat") -> ArrayMesh:
	var spec := _spec(profile)
	if profile == "flat":
		var w: float = spec.fin_half_width
		var length: float = spec.fin_length
		var vertices := PackedVector3Array([
			Vector3(0, 0, 0),
			Vector3(-w, 0, -length),
			Vector3(w, 0, -length),
		])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
		var fan := ArrayMesh.new()
		fan.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return fan
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = spec.fin_radius
	cone.height = spec.fin_length
	cone.radial_segments = 3
	cone.rings = 1
	var basis := Basis(Vector3.RIGHT, -PI * 0.5)
	return _cached("slim/fin", [[cone,
		Transform3D(basis, Vector3(0, 0, -spec.fin_length * 0.5))]])


static func tail_pivot(profile := "flat") -> Vector3:
	return _spec(profile).tail_at


## 体半高（脊线到腹线的中点距离）。把鱼压到「最高点离水面 X 米」时必须乘上
## 实际实例缩放：个体 scale 在 0.72–1.0 之间浮动，用固定半高会让大一号的那条
## 露出背脊，正好把半透明水膜卡在最难看的那个位置。
static func fish_half_height(profile := "flat") -> float:
	return (_spec(profile).body as Vector3).y


static func _spec(profile: String) -> Dictionary:
	if profile == "slim":
		return {
			"body": SLIM_BODY, "back": SLIM_BACK, "back_at": SLIM_BACK_AT,
			"eye": SLIM_EYE, "eye_at": SLIM_EYE_AT, "tail_at": SLIM_TAIL_AT,
			"fin_length": SLIM_FIN_LENGTH, "fin_radius": SLIM_FIN_RADIUS,
			"fin_half_width": SLIM_FIN_RADIUS * 1.5, "fin_thickness": SLIM_FIN_THICKNESS,
		}
	return {
		"body": FLAT_BODY, "back": FLAT_BACK, "back_at": FLAT_BACK_AT,
		"eye": FLAT_EYE, "eye_at": FLAT_EYE_AT, "tail_at": FLAT_TAIL_AT,
		"fin_length": FLAT_FIN_LENGTH, "fin_radius": FLAT_FIN_RADIUS,
		"fin_half_width": FLAT_FIN_HALF_WIDTH, "fin_thickness": FLAT_FIN_THICKNESS,
	}


static func _cached(key: String, parts: Array) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = _merge(parts)
	var mesh: ArrayMesh = _cache[key]
	return mesh


static func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		st.append_from(part[0], 0, part[1])
	return st.commit()


static func _sphere(radial: int, rings: int) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = radial
	sphere.rings = rings
	return sphere


## 群内地盘布局：黄金角螺旋 + 随机抖动 + 迭代互斥。
##
## 为什么不能只用螺旋：等角等距排出来的是一圈"排队"，俯视看整群就是个环。
## 为什么不能只用随机：随机会出现两条鱼贴在一起。
## 所以先给一个抖过的螺旋初值，再做几轮两两推开，直到最近间距不小于 min_gap。
## 结果对同一个 rng 序列是确定的，读档能复现同一片鱼群。
##
## 返回 Vector3 数组（y 为纵向偏移），x/z 在半径 radius 的椭圆内。
static func school_offsets(count: int, radius: float, squash: float, min_gap: float,
		rng: RandomNumberGenerator, vertical := 0.22) -> Array:
	var points: Array = []
	if count <= 0:
		return points
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		var k := float(i) + 0.5
		var r: float = (0.22 + 0.78 * sqrt(k / float(count))) * radius * rng.randf_range(0.80, 1.16)
		var a: float = k * golden + rng.randf_range(-0.40, 0.40)
		points.append(Vector2(cos(a) * r, sin(a) * r * squash))
	# 互斥迭代：只推平面位置，纵向偏移最后单独给。
	for _pass in 12:
		var moved := false
		for i in points.size():
			for j in range(i + 1, points.size()):
				var delta: Vector2 = points[j] - points[i]
				var dist := delta.length()
				if dist >= min_gap:
					continue
				# 完全重合时给一个确定性的分离方向，否则会除零。
				var push: Vector2 = delta / dist if dist > 0.0001 else Vector2.RIGHT.rotated(float(i) * 2.399963)
				var shift := push * (min_gap - dist) * 0.5
				points[i] -= shift
				points[j] += shift
				moved = true
		if not moved:
			break
	var out: Array = []
	for p in points:
		out.append(Vector3(p.x, rng.randf_range(-vertical, vertical), p.y))
	return out
