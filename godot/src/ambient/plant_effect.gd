extends Node3D
## 区块专用植物的「区域效果」。
##
## 每个区块的专用植物可以向这里登记一种效果（摆放表里 plant.effect）：
##   petals      sea · 花瓣飘落（2026-10-28 起 zone1 停用，见 naming.ZONE_PLANT_EFFECTS）
##   pollen      横滨铁道 · 花粉尘埃
##   wind        圆弧农场 · 强风（只加强摆动，不发射粒子）
##   sea_breeze  远海街町 · 咸味海风里的细碎水沫
##   ripple      浅水养殖台 · 水面浮起的气泡
##
## 停用一个区块的粒子只改数据（植物场景的 effect 字段），不改这里：
## 效果名留空即不建发射器，代价是零，代码路径保持可用。
##
## 效果是「一个区块一个发射器」，不是每株一个；这样几百株植物也只有一份粒子开销。

@export var effect := ""
@export var radius := 7.0
@export var amount := 20

const PALETTE := {
	"petals": Color(0.96, 0.62, 0.72, 0.9),
	"pollen": Color(0.98, 0.92, 0.66, 0.75),
	"sea_breeze": Color(0.82, 0.96, 1.0, 0.55),
	"ripple": Color(0.72, 0.95, 1.0, 0.65),
}


func _ready() -> void:
	match effect:
		"petals":
			_emit(Vector3(0, -1, 0), 5.5, 0.35, 0.09, 0.16)
		"pollen":
			_emit(Vector3(0.2, 0.15, -0.1), 9.0, 0.02, 0.03, 0.06)
		"sea_breeze":
			_emit(Vector3(1.0, 0.05, 0.3), 9.0, 0.05, 0.05, 0.10)
		"ripple":
			_emit(Vector3(0, 1, 0), 4.0, -0.12, 0.06, 0.13)
		_:
			pass


func _emit(direction: Vector3, lifetime: float, gravity: float, smin: float, smax: float) -> void:
	var p := GPUParticles3D.new()
	p.name = "Emit"
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime * 0.5
	p.emitting = true
	p.visibility_aabb = AABB(Vector3(-radius, -2, -radius), Vector3(radius * 2, 6, radius * 2))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(radius, 0.6, radius)
	proc.direction = direction
	proc.spread = 35.0
	proc.initial_velocity_min = 0.10
	proc.initial_velocity_max = 0.45
	proc.gravity = Vector3(0, gravity, 0)
	proc.scale_min = smin
	proc.scale_max = smax
	proc.color = PALETTE.get(effect, Color.WHITE)
	p.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
