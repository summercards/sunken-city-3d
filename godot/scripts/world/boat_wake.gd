extends Node3D
## World-space history drives displacement in the ocean mesh itself; no foam overlay.
const LIFETIME := 9.0
const MAX_SAMPLES := 64
const INTERVAL := 0.15
var samples: Array[Dictionary] = []
var _last_emit := -100.0
var _previous := Vector2.INF
var _distance := 0.0

func update_wake(t: float, boat: Node3D, surface: MeshInstance3D) -> void:
	var p := Vector2(boat.position.x, boat.position.z)
	# Teleports and loading a different berth must never draw a stripe across the map.
	if _previous.is_finite() and p.distance_to(_previous) > 8.0:
		samples.clear()
		_last_emit = -100.0
	if _previous.is_finite(): _distance += p.distance_to(_previous)
	_previous = p
	while not samples.is_empty() and t - float(samples[0].time) > LIFETIME:
		samples.pop_front()
	var speed: float = boat.wake_uniform().w
	if speed > 0.18 and t - _last_emit >= INTERVAL:
		var forward := Vector2(-sin(boat.rotation.y), -cos(boat.rotation.y))
		samples.append({"pos": p - forward * 1.9, "side": Vector2(forward.y, -forward.x),
			"time": t, "speed": clampf(speed / 3.4, 0.0, 1.0), "distance": _distance,
			"break": t - _last_emit > 0.5})
		_last_emit = t
		if samples.size() > MAX_SAMPLES: samples.pop_front()
	visible = samples.size() >= 2
	var points := PackedVector4Array()
	var strengths := PackedVector2Array()
	points.resize(32)
	strengths.resize(32)
	# Downsample bounded history, always keeping the newest stern sample.
	var count := mini(samples.size(), 32)
	for i in count:
		var index := roundi(float(i) * (samples.size() - 1) / maxf(1.0, count - 1))
		var sample: Dictionary = samples[index]
		var broken := false
		if i > 0:
			var previous := roundi(float(i - 1) * (samples.size() - 1) / maxf(1.0, count - 1))
			for j in range(previous + 1, index + 1):
				broken = broken or bool(samples[j].break)
		points[i] = Vector4(sample.pos.x, sample.pos.y, float(sample.time), 1.0 if broken else 0.0)
		strengths[i] = Vector2(float(sample.speed), 0.0)
	var mat := surface.material_override as ShaderMaterial
	mat.set_shader_parameter("wake_points", points)
	mat.set_shader_parameter("wake_strengths", strengths)
	mat.set_shader_parameter("wake_count", count)
