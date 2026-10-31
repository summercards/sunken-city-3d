extends SceneTree
## Read-only: compare three ways of measuring the sunroom body box.
##
## The shop placement rule ("50 m south of the sunroom body centre") was frozen
## from a live AABB measurement, but `MultiMeshInstance3D.get_aabb()` is only
## trustworthy once the instance transforms are installed. This probe prints
## every candidate so the test can pick the stable one instead of racing import
## state.
var main: Node

func _init() -> void:
	call_deferred("run")

func box_of(node: Node, use_meta: bool) -> AABB:
	var out := AABB()
	var first := true
	for m in node.find_children("*", "VisualInstance3D", true, false):
		var b: AABB
		if m is MultiMeshInstance3D and m.multimesh != null and use_meta:
			var local: AABB = m.multimesh.mesh.get_aabb()
			var declared: Array = m.get_meta("instance_transforms", [])
			for i in m.multimesh.instance_count:
				var xf: Transform3D = m.global_transform
				xf = xf * (declared[i] if i < declared.size() else m.multimesh.get_instance_transform(i))
				var part: AABB = xf * local
				out = part if first else out.merge(part)
				first = false
			continue
		if m is MeshInstance3D or m is MultiMeshInstance3D:
			b = m.global_transform * m.get_aabb()
			out = b if first else out.merge(b)
			first = false
	return out

func fmt(b: AABB) -> Array:
	return [round(b.position.x * 100) / 100.0, round(b.position.y * 100) / 100.0, round(b.position.z * 100) / 100.0,
		round(b.size.x * 100) / 100.0, round(b.size.y * 100) / 100.0, round(b.size.z * 100) / 100.0]

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._autosave_on = false
	main.set_process(false)
	for i in 8:
		await process_frame
	var zone: Node = main.get_node("World/Zones/Zone1HomeHarbor")
	var rows := []
	for q in ["后部方形建筑", "前部倾斜太阳能房"]:
		var n: Node = zone.find_child(q, true, false)
		if n == null:
			rows.append({"query": q, "missing": true})
			continue
		var plain := box_of(n, false)
		var meta := box_of(n, true)
		rows.append({"query": q, "plain": fmt(plain), "meta": fmt(meta),
			"plain_center": [round(plain.get_center().x * 100) / 100.0, round(plain.get_center().z * 100) / 100.0],
			"meta_center": [round(meta.get_center().x * 100) / 100.0, round(meta.get_center().z * 100) / 100.0]})
	var shop: Node3D = main.get_node("World/SeaStructures/floating_shop")
	var report := {"nodes": rows, "shop": [shop.global_position.x, shop.global_position.z]}
	var file := FileAccess.open("res://outputs/sunroom-body-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("[sunroom-probe] ", JSON.stringify(report))
	main.queue_free()
	await process_frame
	quit(0)
