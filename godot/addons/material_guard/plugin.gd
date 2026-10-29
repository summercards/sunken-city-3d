@tool
extends EditorPlugin
## 编辑器内的材质参数守卫。
##
## 为什么需要（2026-10-29，一天内复发三次）：
##   Godot 保存 ShaderMaterial 时，`shader_parameter/*` 行是照着「当前已编译着色器的
##   uniform 列表」重建的。该列表一旦为空（着色器重编译中、场景刚重载、资源早于着色器
##   就绪被写），整批参数会被**静默丢光且不报错**，连 ext_resource 贴图行一起删。
##   `sunny_palette.gdshader` 的 palette 没有默认值，丢了之后 texture() 返回纯白，
##   于是整栋太阳能木屋变成白模。
##
## 这个插件只做一件事：发现磁盘缺参数，就按基线把**文件**补回来，然后让编辑器重扫。
##
## 它刻意不调用 set_shader_parameter：
##   那会把加载中的 .tres 标成「已修改」，下次保存场景时编辑器顺带回写它，
##   而回写那一刻若 uniform 列表还没就绪，参数照样被清空 —— 守卫变成肇事者。
##   实测就是这么复发的（插件每次加载标脏 4 条参数，之后保存场景即丢参数）。

const Guard = preload("res://src/rendering/material_param_guard.gd")

var _fs: EditorFileSystem
var _pending := false


func _enter_tree() -> void:
	_fs = EditorInterface.get_resource_filesystem()
	if _fs != null and not _fs.filesystem_changed.is_connected(_on_filesystem_changed):
		_fs.filesystem_changed.connect(_on_filesystem_changed)
	call_deferred("_check")


func _exit_tree() -> void:
	if _fs != null and _fs.filesystem_changed.is_connected(_on_filesystem_changed):
		_fs.filesystem_changed.disconnect(_on_filesystem_changed)


func _on_filesystem_changed() -> void:
	# 文件刚变动时着色器可能还在编译，等一轮再查，避免误判。
	if _pending:
		return
	_pending = true
	await get_tree().create_timer(1.0).timeout
	_pending = false
	_check()


func _check() -> void:
	var fixed := Guard.repair_disk()
	if fixed <= 0:
		return
	print("[material-guard] 已按基线修回 %d 份材质的磁盘参数，正在重扫资源" % fixed)
	if _fs != null:
		# 让编辑器丢弃旧副本、按修好的文件重新导入，预览立刻恢复。
		_fs.scan()
