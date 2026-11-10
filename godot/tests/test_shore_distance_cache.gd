extends SceneTree
## OPT-15：只由统一 runner 在隔离 user:// 执行，不加载 Main，不读写玩家存档。
const ShoreDistance = preload("res://src/rendering/shore_distance.gd")
const N := 16
const REGION := Rect2(-4.0, -4.0, 8.0, 8.0)
var cache_dir := ""
var checks := 0
var failures := 0
var reference_slot := PackedByteArray()
var multimesh_snapshots: Dictionary = {}

class Probe extends ShoreDistance:
	var image: Image
	var edt_calls := 0
	var disk_reads := 0
	var disk_writes := 0
	var multimesh_snapshots: Dictionary = {}
	func _multimesh_instance_transform(mm: MultiMesh, index: int) -> Transform3D:
		if multimesh_snapshots.has(mm):
			var transforms: Array[Transform3D] = multimesh_snapshots[mm]
			return transforms[index]
		return super._multimesh_instance_transform(mm, index)
	func _set_image(payload: PackedByteArray, resolution: int) -> void:
		image = Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGF, payload)
		super._set_image(payload, resolution)
	func _edt(line: PackedFloat32Array) -> PackedFloat32Array:
		edt_calls += 1
		return super._edt(line)
	func _read_cache(key: String, resolution: int) -> PackedByteArray:
		disk_reads += 1
		return super._read_cache(key, resolution)
	func _write_cache(key: String, resolution: int, payload: PackedByteArray) -> void:
		disk_writes += 1
		super._write_cache(key, resolution, payload)

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[shore-distance-cache] FAIL ", label)

func clear_memory() -> void:
	ShoreDistance._process_cache_key = ""
	ShoreDistance._process_cache_directory = ""
	ShoreDistance._process_cache_bytes = PackedByteArray()

func build(nodes: Array, enabled := true, level := 0.0, resolution := N,
		region := REGION, outlines: Array = []) -> Probe:
	var atlas := Probe.new()
	atlas.cache_enabled = enabled
	atlas.cache_directory = cache_dir
	atlas.multimesh_snapshots = multimesh_snapshots
	atlas.rebuild(nodes, level, resolution, region, outlines)
	return atlas

func check_variant(nodes: Array, original_key: String, label: String, level := 0.0,
		resolution := N, region := REGION, outlines: Array = []) -> Probe:
	var expected := build(nodes, false, level, resolution, region, outlines)
	var file := FileAccess.open(cache_dir.path_join(ShoreDistance.CACHE_SLOT_FILE), FileAccess.WRITE)
	if file != null:
		file.store_buffer(reference_slot)
		file.close()
	clear_memory()
	var candidate := build(nodes, true, level, resolution, region, outlines)
	check(candidate._make_cache_key(resolution, outlines) != original_key, label + " 的内容 key 改变")
	check(not candidate.metrics.cache_hit and candidate.edt_calls == resolution * 2, label + " 拒绝旧缓存并重做 EDT")
	check(candidate.image.get_data() == expected.image.get_data(), label + " 与禁用缓存逐字节一致")
	check(candidate._field == expected._field, label + " 的 CPU 距离场一致")
	return candidate

func check_corruption(nodes: Array, clean: PackedByteArray, corrupted: PackedByteArray,
		baseline: PackedByteArray, label: String) -> void:
	var path := cache_dir.path_join(ShoreDistance.CACHE_SLOT_FILE)
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, label + " 夹具可写")
	if file == null: return
	file.store_buffer(corrupted)
	file.close()
	clear_memory()
	var rebuilt := build(nodes)
	check(not rebuilt.metrics.cache_hit and rebuilt.edt_calls == N * 2, label + " 被拒绝重建")
	check(rebuilt.image.get_data() == baseline, label + " 重建字节完全一致")
	check(FileAccess.get_file_as_bytes(path) == clean, label + " 重建恢复有效磁盘条目")

func run() -> void:
	cache_dir = "user://shore_distance_opt15_" + str(Time.get_ticks_usec())
	clear_memory()
	var geometry := Node3D.new()
	root.add_child(geometry)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 1.0, 2.0)
	mesh_node.mesh = mesh
	geometry.add_child(mesh_node)
	var nodes: Array = [geometry]
	var disabled := build(nodes, false)
	var baseline := disabled.image.get_data()
	var original_key := disabled._make_cache_key(N, [])
	check(ShoreDistance.RESOLUTION == 1536, "正式默认分辨率仍为 1536")
	check(not disabled.metrics.cache_hit and disabled.edt_calls == N * 2, "禁用缓存执行原 EDT")
	check(disabled.disk_reads == 0 and disabled.disk_writes == 0, "禁用缓存无磁盘 I/O")
	check(not disabled.segments.is_empty(), "夹具确实切出真实几何线段")

	var cold := build(nodes)
	check(not cold.metrics.cache_hit and cold.edt_calls == N * 2, "首次冷构建执行 EDT")
	check(cold.image.get_format() == Image.FORMAT_RGF and baseline.size() == N * N * 8, "缓存为原始无损 RGF")
	check(cold.image.get_data() == baseline, "冷构建与禁用缓存逐字节相等")
	var slot := cache_dir.path_join(ShoreDistance.CACHE_SLOT_FILE)
	check(FileAccess.file_exists(slot), "生成固定单 slot")
	var clean := FileAccess.get_file_as_bytes(slot)
	reference_slot = clean
	if clean.size() != baseline.size() + ShoreDistance.CACHE_MAGIC.length() + 5 * 4 + 8 + 64:
		check(false, "磁盘条目必须具有完整固定头及 payload")
		geometry.free()
		print("[shore-distance-cache] %d checks, %d failures" % [checks, failures])
		quit(1)
		return

	cold.segments.clear()
	cold._segment_scale.clear()
	cold._triangles["test"] = true
	cold.edt_calls = 0
	cold.disk_reads = 0
	cold.disk_writes = 0
	cold.rebuild(nodes, 0.0, N, REGION)
	check(cold.metrics.cache_hit and cold.edt_calls == 0 and cold.metrics.edt_ms == 0.0, "同实例热命中完全跳过 EDT")
	check(cold.disk_reads == 0 and cold.disk_writes == 0, "进程内热命中不做磁盘 I/O")
	check(cold.segments == disabled.segments and cold._segment_scale == disabled._segment_scale, "热命中仍重新提取线段及尺度")
	check(cold._triangles.is_empty(), "热命中清除三角形临时数据")
	check(cold.image.get_data() == baseline and cold._field == disabled._field, "热命中图像字节及 CPU 场完全一致")
	check(cold.distance_at(Vector2(0.5, 0.5)) == disabled.distance_at(Vector2(0.5, 0.5)), "热命中保留 distance_at 查询")
	clear_memory()
	var disk_hot := build(nodes)
	check(disk_hot.metrics.cache_hit and disk_hot.edt_calls == 0 and disk_hot.disk_reads == 1, "清除进程缓存后从磁盘命中")
	check(disk_hot.image.get_data() == baseline, "磁盘命中图像原始字节完全相等")
	check(disk_hot.metrics.build_ms >= 0.0 and disk_hot.metrics.edt_ms == 0.0, "metrics 明确提供 build_ms/edt_ms/cache_hit")

	mesh_node.position.x = 0.25
	check_variant(nodes, original_key, "geometry transform")
	mesh_node.position = Vector3.ZERO
	mesh_node.rotation.y = 0.25
	check_variant(nodes, original_key, "geometry rotation")
	mesh_node.rotation = Vector3.ZERO
	mesh_node.scale = Vector3(1.25, 1.0, 0.75)
	check_variant(nodes, original_key, "geometry scale")
	mesh_node.scale = Vector3.ONE
	mesh.size.x = 2.5
	check_variant(nodes, original_key, "geometry 内容")
	mesh.size.x = 2.0
	geometry.visible = false
	check_variant(nodes, original_key, "父级 visibility")
	geometry.visible = true
	mesh_node.set_meta("visual_only", true)
	check_variant(nodes, original_key, "visual_only")
	mesh_node.remove_meta("visual_only")
	check_variant(nodes, original_key, "water level", 0.1)
	check_variant(nodes, original_key, "resolution", 0.0, 18)
	check_variant(nodes, original_key, "region", 0.0, N, Rect2(-3.0, -3.0, 6.0, 6.0))
	check_variant(nodes, original_key, "outline", 0.0, N, REGION, [Rect2(2.0, 2.0, 1.0, 1.0)])
	# 这两个 region 方形化后 bounds 相同，仍须以原始 region 区分 key。
	var non_square := build(nodes, false, 0.0, N, Rect2(-4.0, -2.0, 8.0, 4.0))
	check(non_square.bounds == disabled.bounds and non_square._make_cache_key(N, []) != original_key, "region 不能仅以最终 bounds 代替")
	var precision := build(nodes, false, 0.1)
	var precision_key := precision._make_cache_key(N, [])
	precision._level += 0.000000000001
	check(precision._make_cache_key(N, []) != precision_key, "key 不把 double 水位量化成 float32")
	precision._level = 0.1
	precision._segment_scale[0] += 0.01
	check(precision._make_cache_key(N, []) != precision_key, "key 包含每段尺度")

	# MultiMesh 独立根：普通 mesh 隐藏后不得贡献线段，杜绝空切片/其他节点代偿。
	var multi_geometry := Node3D.new()
	root.add_child(multi_geometry)
	var multi_node := MultiMeshInstance3D.new()
	multi_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 1
	multi.set_instance_transform(0, Transform3D.IDENTITY)
	multi_node.multimesh = multi
	multi_geometry.add_child(multi_node)
	var multi_nodes: Array = [multi_geometry]
	mesh_node.visible = false
	check(build(nodes, false).segments.is_empty(), "隐藏的普通 mesh 不贡献 MultiMesh 夹具线段")
	check(multi_node.is_visible_in_tree() and multi_geometry.is_visible_in_tree(), "独立 MultiMesh 根与节点均可见")
	# Godot 4.7.2 Dummy mesh_storage.h：setter 空实现、getter 恒为单位变换，
	# 不是异步更新；await/force_draw 无法修复。仅替代测试的 transform 读取边界，
	# _visit 的 MultiMesh 分支、矩阵乘法、真实 mesh 切片、key、缓存和 EDT 均走正式代码。
	var dummy_backend := DisplayServer.get_name() == "headless" and RenderingServer.get_rendering_device() == null
	if dummy_backend:
		var initial_transforms: Array[Transform3D] = [Transform3D.IDENTITY]
		multimesh_snapshots[multi] = initial_transforms
	clear_memory()
	var multi_cold := build(multi_nodes)
	check(not multi_cold.segments.is_empty(), "MultiMesh 仍提取真实几何")
	check(multi_cold.segments == disabled.segments, "独立单位变换 MultiMesh 切片等于普通 mesh 基线")
	var multi_key := multi_cold._make_cache_key(N, [])
	reference_slot = FileAccess.get_file_as_bytes(slot)
	var moved_transform := Transform3D(Basis.IDENTITY, Vector3(0.5, 0.0, 0.0))
	multi.set_instance_transform(0, moved_transform)
	var native_transform := multi.get_instance_transform(0)
	print("[shore-distance-cache] MultiMesh dummy_backend=", dummy_backend,
		" native_origin=", native_transform.origin, " requested_origin=", moved_transform.origin)
	if dummy_backend:
		check(native_transform == Transform3D.IDENTITY, "Dummy 原生 getter 恒返回单位变换而非请求的平移")
		var native_uncached := Probe.new()
		native_uncached.cache_enabled = false
		native_uncached.rebuild(multi_nodes, 0.0, N, REGION)
		check(native_uncached.edt_calls == N * 2 and native_uncached.segments == multi_cold.segments, "Dummy 原生无缓存路径同样读到旧几何，排除缓存造成 transform 丢失")
		var moved_transforms: Array[Transform3D] = [moved_transform]
		multimesh_snapshots[multi] = moved_transforms
	else:
		check(native_transform == moved_transform, "真实渲染后端立即读回 MultiMesh instance transform")
	var multi_moved := check_variant(multi_nodes, multi_key, "MultiMesh instance transform")
	var direct_slice := Probe.new()
	direct_slice._level = 0.0
	direct_slice._region = REGION
	direct_slice._slice(mesh, moved_transform)
	check(not multi_moved.segments.is_empty() and multi_moved.segments != multi_cold.segments, "MultiMesh 平移后非空线段确实改变")
	check(multi_moved.segments == direct_slice.segments and multi_moved._segment_scale == direct_slice._segment_scale, "MultiMesh 平移切片精确等于显式 transform 独立切片")
	check(multi_moved.image.get_data() != multi_cold.image.get_data(), "MultiMesh 平移后 RGF 字节确实改变")
	multi.set_instance_transform(0, Transform3D.IDENTITY)
	if dummy_backend:
		var restored_transforms: Array[Transform3D] = [Transform3D.IDENTITY]
		multimesh_snapshots[multi] = restored_transforms
	multi.visible_instance_count = 0
	var multi_hidden := check_variant(multi_nodes, multi_key, "MultiMesh visible_instance_count")
	check(multi_hidden.segments.is_empty(), "MultiMesh visible_instance_count=0 不切片")
	multimesh_snapshots.clear()
	multi_geometry.free()
	mesh_node.visible = true
	reference_slot = clean
	clear_memory()
	build(nodes)
	var header_size := clean.size() - baseline.size()
	var corrupted := clean.duplicate()
	corrupted[0] ^= 1
	check_corruption(nodes, clean, corrupted, baseline, "magic 损坏")
	corrupted = clean.duplicate()
	corrupted[ShoreDistance.CACHE_MAGIC.length()] ^= 1
	check_corruption(nodes, clean, corrupted, baseline, "格式版本损坏")
	corrupted = clean.duplicate()
	corrupted[ShoreDistance.CACHE_MAGIC.length() + 3 * 4] ^= 1
	check_corruption(nodes, clean, corrupted, baseline, "Image 格式损坏")
	corrupted = clean.duplicate()
	corrupted[ShoreDistance.CACHE_MAGIC.length() + 5 * 4 + 8] ^= 1
	check_corruption(nodes, clean, corrupted, baseline, "内容 key 损坏")
	corrupted = clean.duplicate()
	corrupted[header_size] ^= 1
	check_corruption(nodes, clean, corrupted, baseline, "payload SHA-256 损坏")
	corrupted = clean.duplicate()
	corrupted.encode_u64(ShoreDistance.CACHE_MAGIC.length() + 5 * 4, ShoreDistance.CACHE_MAX_PAYLOAD_BYTES + 1)
	check_corruption(nodes, clean, corrupted, baseline, "伪造超上限长度")
	check_corruption(nodes, clean, clean.slice(0, clean.size() - 1), baseline, "截断文件")
	corrupted = clean.duplicate()
	corrupted.append(0)
	check_corruption(nodes, clean, corrupted, baseline, "额外尾部")

	var oversized_header := clean.slice(0, header_size)
	oversized_header.encode_u64(ShoreDistance.CACHE_MAGIC.length() + 5 * 4, ShoreDistance.CACHE_MAX_PAYLOAD_BYTES + 1)
	var oversized_file := FileAccess.open(slot, FileAccess.WRITE)
	check(oversized_file != null, "超大文件夹具可用")
	if oversized_file != null:
		oversized_file.store_buffer(oversized_header)
		oversized_file.seek(header_size + ShoreDistance.CACHE_MAX_PAYLOAD_BYTES)
		oversized_file.store_8(0)
		oversized_file.close()
		clear_memory()
		var rejected_large := build(nodes)
		check(not rejected_large.metrics.cache_hit and rejected_large.edt_calls == N * 2, "实际超大磁盘文件在读取 payload 前拒绝")
		check(rejected_large.image.get_data() == baseline, "超大文件拒绝后字节完全一致")

	var again := build(nodes, false)
	check(not again.metrics.cache_hit and again.edt_calls == N * 2 and again.image.get_data() == baseline, "已有热缓存时 disabled 仍计算且输出同值")
	check(again.disk_reads == 0 and again.disk_writes == 0, "已有热缓存时 disabled 也无磁盘 I/O")
	# 只制造当前隔离测试自己拥有的普通文件来阻止建目录，不删文件、不递归清理。
	var blocker := cache_dir.path_join("not_a_directory")
	var blocker_file := FileAccess.open(blocker, FileAccess.WRITE)
	check(blocker_file != null, "写失败夹具可用")
	if blocker_file != null:
		blocker_file.store_string("OPT-15")
		blocker_file.close()
		var failed_write := Probe.new()
		failed_write.cache_directory = blocker.path_join("cache")
		failed_write.rebuild(nodes, 0.0, N, REGION)
		check(not failed_write.metrics.cache_hit and failed_write.image.get_data() == baseline, "缓存写失败安全降级且图像相同")
		check(FileAccess.get_file_as_string(blocker) == "OPT-15", "写失败不修改阻挡文件")
	clear_memory()
	check(ShoreDistance.CACHE_MAX_PAYLOAD_BYTES >= 1536 * 1536 * 8, "缓存上限容纳正式 18MiB 图")
	geometry.free()
	print("[shore-distance-cache] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
