extends SceneTree

const Guard = preload("res://src/plant_authoring/host_scene_guard.gd")
const Attachment = preload("res://src/plant_authoring/host_attachment.gd")
const Screen = preload("res://addons/plant_editor/editor_screen.gd")
const BASE := "res://outputs/host_scene_guard"
const FORMAL := "res://outputs/formal_host/building.tscn"
const HEADER := "[gd_scene format=3]\n"
const NODE := '[node name="Root" type="Node3D"]\n'
var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {}

# 文件安全端口仍用真实 Screen，仅隔离本专项无关的渲染与控件刷新。
class ScreenProbe extends Screen:
	func _accept_result(_result: Dictionary, _fit: bool = false) -> bool:
		return true
	func _sync_controls() -> void:
		pass
	func _set_status(_message: String, _error: bool) -> void:
		pass

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String, detail: Variant = "") -> void:
	checks += 1
	if not ok:
		var message := label + " " + str(detail)
		failures.append(message)
		printerr("FAIL [host-scene-guard] ", message)

func write_text(path: String, text: String) -> void:
	check(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK, "隔离目录可写")
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "测试文本可写 " + path)
	if file != null:
		file.store_string(text)
		file.close()

func reject(label: String, text: String) -> String:
	var path := BASE + "/" + label + "/building.tscn"
	write_text(path, text)
	var reason := Guard.audit_path(path)
	check(not reason.is_empty() and not reason.contains("入口必须"), "加载前拒绝 " + label, reason)
	evidence[label] = reason
	return path

func ext(type: String, path: String, id: String = "1") -> String:
	return '[ext_resource id="%s" path="%s" type="%s"]\n' % [id, path, type]

func run() -> void:
	check(OS.get_thread_caller_id() == OS.get_main_thread_id(), "统一 runner 主线程入口")
	check(not ProjectSettings.has_setting("autoload/GameState"), "前置隔离 Autoload")
	var reason := Guard.audit_path(FORMAL)
	check(reason.is_empty(), "正式 workshop 实物文本闭包通过", reason)
	if reason.is_empty():
		var packed := ResourceLoader.load(FORMAL, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		var scene_reason := Attachment.audit_scene(packed)
		check(scene_reason.is_empty(), "正式实物后置审计保留", scene_reason)
		if scene_reason.is_empty():
			var node := packed.instantiate() as Node3D
			var adapter := Attachment.new()
			var bound := adapter.bind_host(node)
			check(bound.ok and int(bound.get("surface_count", 0)) > 0, "正式实物有可读三角面", bound)
			evidence.formal = {"sha256": FileAccess.get_sha256(FORMAL), "nodes": packed.get_state().get_node_count(), "surfaces": bound.get("surface_count", 0)}
			print("[host-scene-guard-formal] ", JSON.stringify(evidence.formal))
			node.free()
	var positive := BASE + "/positive/building.tscn"
	write_text(positive, '[gd_scene format=4 uid="uid://hostscene"]\n' + ext("Material", "res://assets/materials/solar_cabin/sunny_matte.tres") + '[sub_resource type="BoxMesh" id="mesh"]\nmaterial = ExtResource("1")\n' + NODE + '[node name="Box" type="MeshInstance3D" parent="."]\nmesh = SubResource("mesh")\n')
	check(Guard.audit_path(positive).is_empty(), "Store Material 声明的公共材质 shader/PNG 递归闭包通过", Guard.audit_path(positive))
	var marker := BASE + "/executed.txt"
	var script := BASE + "/never_load.gd"
	# 只写文本，不 load/reload/new；若错误放行，哨兵能证明 _init 曾执行。
	write_text(script, '@tool\nextends Resource\nfunc _init():\n\tvar f = FileAccess.open("%s", FileAccess.WRITE)\n\tf.store_string("unexpected")\n' % marker)
	var unsafe := reject("script", HEADER + ext("GDScript", script) + NODE + 'metadata/payload = ExtResource("1")\n')
	reject("script_alias", HEADER + ext("Resource", script) + NODE)
	var resource := BASE + "/scripted.tres"
	write_text(resource, '[gd_resource type="Resource" format=3]\n' + ext("Script", script) + '[resource]\nscript = ExtResource("1")\n')
	reject("resource_script", HEADER + ext("Resource", resource) + NODE)
	reject("material_alias_script", HEADER + ext("Material", resource) + NODE)
	write_text(BASE + "/script_property.tres", '[gd_resource type="Resource" format=3]\n[resource]\n"script" = null\n')
	reject("quoted_script", HEADER + ext("Resource", BASE + "/script_property.tres") + NODE)
	write_text(BASE + "/nested.tscn", HEADER + ext("Script", script) + NODE)
	reject("nested", HEADER + ext("PackedScene", BASE + "/nested.tscn") + NODE)
	reject("inheritance", HEADER + '[node name="Root" instance=ExtResource("1")]\n')
	reject("name_trick", HEADER + '[node name="safe type=\"Node3D\"" type="EvilClass"]\n')
	reject("name_path", HEADER + '[node name="safe/../evil" type="Node3D"]\n')
	write_text(BASE + "/a.tres", '[gd_resource type="Resource" format=3]\n' + ext("Resource", BASE + "/b.tres") + '[resource]\nmetadata/value = ExtResource("1")\n')
	write_text(BASE + "/b.tres", '[gd_resource type="Resource" format=3]\n' + ext("Resource", BASE + "/a.tres") + '[resource]\nmetadata/value = ExtResource("1")\n')
	reject("cycle", HEADER + ext("Resource", BASE + "/a.tres") + NODE)
	reject("traversal", HEADER + ext("Resource", BASE + "/../a.tres") + NODE)
	reject("class", HEADER + '[node name="Root" type="UnknownClass"]\n')
	reject("top_level", HEADER + NODE + "top_level = true\n")
	reject("callable_key", HEADER + NODE + 'metadata/value = {Callable(): 1}\n')
	reject("object_nested", HEADER + NODE + 'metadata/value = [{"x": Object(Resource)}]\n')
	reject("inline_script", HEADER + '[sub_resource type="GDScript" id="s"]\nsource_code = "@tool"\n' + NODE)
	reject("unknown_sub", HEADER + '[sub_resource type="UnknownResource" id="x"]\n' + NODE)
	reject("duplicate_sub", HEADER + '[sub_resource type="Resource" id="x"]\n[sub_resource type="Resource" id="x"]\n' + NODE)
	reject("self_sub", HEADER + '[sub_resource type="Resource" id="x"]\nmetadata/self = SubResource("x")\n' + NODE)
	reject("missing_sub", HEADER + NODE + 'metadata/x = SubResource("missing")\n')
	reject("wrong_ref_namespace", HEADER + ext("ShaderMaterial", "res://assets/materials/solar_cabin/sunny_matte.tres") + NODE + 'metadata/x = SubResource("1")\n')
	reject("header_expression", HEADER + '[ext_resource type=Object(GDScript) path="res://x.tres" id="1"]\n' + NODE)
	reject("duplicate_path", HEADER + '[ext_resource type="Resource" path="res://a.tres" path="res://b.tres" id="1"]\n' + NODE)
	var binary := FileAccess.open(BASE + "/binary.tres", FileAccess.WRITE)
	binary.store_buffer(PackedByteArray([82, 83, 82, 67, 0, 255]))
	binary.close()
	reject("binary_dependency", HEADER + ext("Resource", BASE + "/binary.tres") + NODE)
	reject("binary_entry", "RSRC")
	for bad_path in ["user://building.tscn", "/tmp/building.tscn", "res://outputs/../building.tscn", "res://outputs//building.tscn", "res://outputs/./building.tscn", "res://outputs\\building.tscn"]:
		check(not Guard.audit_path(bad_path).is_empty(), "拒绝入口 unsafe path " + bad_path)
	for bad_path in ["https://invalid.example/payload.tres", "user://payload.tres", "res://outputs/./payload.tres", "res://outputs//payload.tres", BASE + "/unknown.png", BASE + "/sunny_palette_fake.gdshader", "res://shaders/sunny_palette_fake.gdshader"]:
		reject("external_%d" % checks, HEADER + ext("Resource", bad_path) + NODE)
	var directory := DirAccess.open(BASE)
	check(directory.create_link(ProjectSettings.globalize_path(positive), "linked_building.tscn") == OK, "创建隔离文件符号链接")
	check(directory.create_link(ProjectSettings.globalize_path(BASE + "/positive"), "linked_dir") == OK, "创建隔离目录符号链接")
	check(not Guard.audit_path(BASE + "/linked_dir/building.tscn").is_empty(), "拒绝符号链接目录")
	check(DirAccess.make_dir_recursive_absolute(BASE + "/file_link") == OK, "文件链接目录可写")
	var link_dir := DirAccess.open(BASE + "/file_link")
	check(link_dir.create_link(ProjectSettings.globalize_path(positive), "building.tscn") == OK, "创建入口文件符号链接")
	check(Guard.audit_path(BASE + "/file_link/building.tscn").contains("符号链接"), "拒绝入口文件符号链接")
	check(directory.create_link(ProjectSettings.globalize_path(positive), "positive_link") == OK, "创建隔离链接依赖")
	reject("link_dependency", HEADER + ext("Resource", BASE + "/positive_link") + NODE)
	check(not Attachment._safe_value({Callable(self, "run"): 1}, {}), "后置检查拒绝字典 Callable 键")
	var script_key := GDScript.new()
	check(not Attachment._safe_value({script_key: 1}, {}), "后置检查拒绝字典 Script 键")
	var screen := ScreenProbe.new()
	var before := screen.session.state_fingerprint()
	var read_result: Dictionary = screen._read_host(unsafe)
	check(not read_result.ok, "UI _read_host 在 load 前拒绝")
	var binding := {"host_path": unsafe, "matrix": Attachment.encode_transform(Transform3D.IDENTITY), "opening_id": "", "enabled": false}
	check(not screen._precheck_state(screen.snapshot(), {"host_binding": binding}).ok, "UI _precheck_state 经统一审计")
	check(not screen.load_host(unsafe).ok and screen.session.state_fingerprint() == before, "load_host 拒绝且保持原状态")
	var draft := screen.get_recovery()
	draft.host_binding = binding
	draft.applied_host_binding = binding
	# 已应用上下文由 Session 独占；顶层字段只兼容旧草稿，不得覆盖它。
	draft.session.authoring_context = {"host_binding": binding}
	var recovery: Dictionary = screen.restore_recovery(draft)
	check(not recovery.get("ok", true) and str(recovery.get("reason", "")) == Guard.audit_path(unsafe) and screen.session.state_fingerprint() == before, "recovery 加载前拒绝已应用危险宿主且状态不变", recovery.get("reason", ""))
	var built: Dictionary = screen.session.build()
	if is_instance_valid(built.get("root")): built.root.free()
	screen.free()
	var shader_path := "res://shaders/sunny_palette.gdshader"
	var shader_original := FileAccess.get_file_as_string(shader_path)
	write_text(shader_path, '#include "res://shaders/sunny_palette_gloss.gdshader"\n' + shader_original)
	check(Guard.audit_path(positive).is_empty(), "已知 shader include 递归通过")
	write_text(shader_path, '#include "res://shaders/sunny_palette.gdshader"\n')
	check(Guard.audit_path(positive).contains("循环"), "shader include 循环拒绝")
	write_text(shader_path, '#include "https://invalid.example/unknown.gdshader"\n')
	check(Guard.audit_path(positive).contains("白名单"), "shader include 网络路径拒绝")
	write_text(shader_path, '#include "res://shaders/../shaders/sunny_palette_gloss.gdshader"\n')
	check(not Guard.audit_path(positive).is_empty(), "shader include 穿越拒绝")
	write_text(shader_path, shader_original)
	check(Guard.audit_path(positive).is_empty(), "隔离 shader 原文恢复")
	check(not FileAccess.file_exists(marker), "所有负例脚本 _init 均未执行")
	var report_file := FileAccess.open("res://outputs/host_scene_guard_report.json", FileAccess.WRITE)
	check(report_file != null, "安全专项报告可写")
	if report_file != null:
		report_file.store_string(JSON.stringify({"checks": checks, "failures": failures, "evidence": evidence, "negative_script_executed": FileAccess.file_exists(marker)}, "\t"))
		report_file.close()
	print("[host-scene-guard] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
