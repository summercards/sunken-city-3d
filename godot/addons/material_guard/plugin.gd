@tool
extends EditorPlugin
## 编辑器内的材质参数守卫。
##
## 为什么需要（2026-10-29，一天内复发两次）：
##   Godot 保存 ShaderMaterial 时，`shader_parameter/*` 行是照着「当前已编译着色器的
##   uniform 列表」重建的。该列表一旦为空（着色器重编译中、场景刚重载、资源早于着色器
##   就绪被写），整批参数会被**静默丢光且不报错**。
##   `sunny_palette.gdshader` 的 `palette` 没有默认值，丢了之后 `texture()` 返回纯白，
##   于是整栋太阳能木屋变成白模 —— 主人看到的现象是「一移动节点就变白」。
##
## 这个插件做两件事：
##   1. 编辑器加载时按基线校验一遍，把内存里缺的参数补上（预览不再变白）；
##   2. 文件系统每次变动后重新校验（材质刚被保存坏时立刻补回内存）。
## 只改内存，不写盘 —— 写盘交给 `scripts/repair_material_params.py`，
## 因为 ResourceSaver 正是这次事故的元凶。

const Guard = preload("res://src/rendering/material_param_guard.gd")

var _fs: EditorFileSystem


func _enter_tree() -> void:
	call_deferred("_enforce")

	_fs = EditorInterface.get_resource_filesystem()
	if _fs != null and not _fs.filesystem_changed.is_connected(_on_filesystem_changed):
		_fs.filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	if _fs != null and _fs.filesystem_changed.is_connected(_on_filesystem_changed):
		_fs.filesystem_changed.disconnect(_on_filesystem_changed)


func _on_filesystem_changed() -> void:
	# 文件变动后给着色器一点编译时间，下一帧再校验，避免读到「未就绪」的假空。
	call_deferred("_enforce")


func _enforce() -> void:
	var fixed := Guard.enforce()
	if fixed > 0:
		print("[material-guard] 已按基线补回 %d 条材质参数（内存），如需修磁盘请跑 "
			% fixed + "scripts/repair_material_params.py")
