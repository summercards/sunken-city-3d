extends RefCounted
## 仅编辑器版候选导出依赖本机Python3/POSIX；运行时生成及读取不依赖该桥。
## 独占创建revision目录，manifest最后提交；中断的未提交目录不被load_recipe接受，历史不覆盖。

const Recipe = preload("res://src/building_attachments/recipe.gd")
const Catalog = preload("res://src/building_attachments/catalog.gd")
const Generator = preload("res://src/building_attachments/generator.gd")
const DEFAULT_BASE := "res://scenes/workshop_attachments"
const SOURCE_FILES := ["catalog.gd", "recipe.gd", "geometry.gd", "forms.gd", "glyphs.gd", "signage.gd", "hvac.gd", "water.gd", "shelter.gd", "generator.gd", "store.gd"]
const CANDIDATE_FILES := ["attachment.tscn", "attachment.recipe.json", "geometry.native.json", "catalog_snapshot.json", "source_manifest.json"]
const MAX_JSON_BYTES := 262144
const MAX_CANDIDATE_FILE_BYTES := 16777216
const SHARED_MATERIALS := {
	"SEA_Matte": "res://assets/materials/solar_cabin/sunny_matte.tres",
	"SEA_Metal": "res://assets/materials/solar_cabin/sunny_metal.tres",
	"SEA_Gloss": "res://assets/materials/solar_cabin/sunny_gloss.tres",
	"SEA_Emission": "res://assets/materials/solar_cabin/sunny_emission.tres"
}

# Python仅作本机POSIX文件系统桥；不执行任何候选内容，所有路径均为独立参数。
const EXCLUSIVE_COMMIT := """
import os, sys, secrets
source, target = sys.argv[1:]
fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
try:
    pieces = target.strip('/').split('/')
    for piece in pieces[:-1]:
        next_fd = os.open(piece, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
        os.close(fd)
        fd = next_fd
    name = pieces[-1]
    temporary = '.attachment_' + secrets.token_hex(16)
    out = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    try:
        with os.fdopen(out, 'wb') as destination, open(source, 'rb') as incoming:
            while True:
                block = incoming.read(1048576)
                if not block:
                    break
                destination.write(block)
            destination.flush()
            os.fsync(destination.fileno())
        os.link(temporary, name, src_dir_fd=fd, dst_dir_fd=fd, follow_symlinks=False)
        os.fsync(fd)
    finally:
        os.unlink(temporary, dir_fd=fd)
finally:
    os.close(fd)
"""

const EXCLUSIVE_DIRECTORY := """
import os, sys
path, exclusive = sys.argv[1:]
fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
try:
    pieces = path.strip('/').split('/')
    for index, piece in enumerate(pieces):
        last = index == len(pieces) - 1
        try:
            os.mkdir(piece, 0o700, dir_fd=fd)
        except FileExistsError:
            if last and exclusive == '1':
                raise
        next_fd = os.open(piece, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
        os.close(fd)
        fd = next_fd
finally:
    os.close(fd)
"""

static func path_reason(path: String, candidate_only: bool = true) -> String:
	if not (path.begins_with("res://") or path.begins_with("user://")) or path.contains("..") or path.contains("\\") or path.simplify_path() != path:
		return "候选路径必须规范且不含点段或路径穿越"
	var relative: String = path.substr(path.find("://") + 3)
	for piece: String in relative.split("/", true):
		if piece.is_empty() or piece == "." or piece.contains(":") or piece.strip_edges() != piece or piece.to_utf8_buffer().has(0):
			return "候选路径分段非法"
	var root: String = DEFAULT_BASE if path.begins_with("res://") else "user://building_attachments"
	if candidate_only and path != root and not path.begins_with(root + "/"):
		return "候选路径不在允许根目录内"
	var absolute: String = ProjectSettings.globalize_path(path).simplify_path()
	var allowed: String = ProjectSettings.globalize_path(root).simplify_path().trim_suffix("/")
	if not absolute.begins_with("/") or (candidate_only and absolute != allowed and not absolute.begins_with(allowed + "/")):
		return "候选全局路径越界"
	# 从文件系统根逐段lstat式检查，不先resolve链接；不存在后缀在最近祖先停止。
	var current: String = "/"
	var pieces: PackedStringArray = absolute.trim_prefix("/").split("/", false)
	for i: int in range(pieces.size()):
		var directory: DirAccess = DirAccess.open(current)
		if directory == null:
			return "候选祖先不可访问：" + current
		var piece: String = pieces[i]
		if directory.is_link(piece):
			return "候选路径禁止符号链接：" + current.path_join(piece)
		var exists_dir: bool = directory.dir_exists(piece)
		var exists_file: bool = directory.file_exists(piece)
		if not exists_dir and not exists_file:
			return ""
		if i < pieces.size() - 1 and not exists_dir:
			return "候选祖先不是目录"
		current = current.path_join(piece)
	return ""

static func valid_base(base_dir: String) -> bool:
	return path_reason(base_dir).is_empty()

static func python_path() -> String:
	for executable: String in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]:
		if FileAccess.file_exists(executable):
			return executable
	return ""

static func create_directory(path: String, exclusive: bool = false) -> String:
	var reason: String = path_reason(path)
	if not reason.is_empty():
		return reason
	var python: String = python_path()
	if python.is_empty():
		return "缺少Python3，拒绝不安全创建候选目录"
	var output: Array = []
	var code: int = OS.execute(python, PackedStringArray(["-I", "-c", EXCLUSIVE_DIRECTORY, ProjectSettings.globalize_path(path).simplify_path(), "1" if exclusive else "0"]), output, true)
	return "" if code == 0 else "无法安全独占候选目录：" + path

static func commit_file(source: String, target: String, candidate_only: bool = true) -> String:
	var reason: String = path_reason(target, candidate_only)
	if not reason.is_empty():
		return reason
	if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
		return "拒绝覆盖已有文件：" + target
	var python: String = python_path()
	if python.is_empty():
		return "缺少本机Python3，无法保证原子无覆盖提交；拒绝降级写入"
	var output: Array = []
	var code: int = OS.execute(python, PackedStringArray(["-I", "-c", EXCLUSIVE_COMMIT, ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target).simplify_path()]), output, true)
	return "" if code == 0 else "原子无覆盖提交失败：" + target

static func write_json(path: String, data: Dictionary) -> String:
	# 通用报告入口仍可写非候选路径，但同样禁止链接与覆盖。
	var reason: String = path_reason(path, false)
	if not reason.is_empty():
		return reason
	var file: FileAccess = FileAccess.create_temp(FileAccess.READ_WRITE, "sea_attachment", "json", false)
	if file == null:
		return "无法创建临时JSON"
	file.store_string(JSON.stringify(data, "\t", true, true) + "\n")
	file.flush()
	if file.get_error() != OK:
		return "JSON写入失败：" + path
	var temporary_path: String = file.get_path()
	file.close()
	return commit_file(temporary_path, path, false)

static func source_manifest() -> Dictionary:
	var files: Array[Dictionary] = []
	for name: String in SOURCE_FILES:
		var path: String = "res://src/building_attachments/" + name
		files.append({"path": path, "sha256": FileAccess.get_sha256(path)})
	files.append({"path": Catalog.PATH, "sha256": FileAccess.get_sha256(Catalog.PATH)})
	return {"kind": "native/project-authored", "files": files, "license_status": "project_original_code_no_external_mesh", "external_mesh_reuse": false, "glyph_source": "glyphs.gd:sea_original_strokes_v1", "blender_source_status": "derived_native_snapshot_only", "commercial_legal_review": "pending"}

static func export_revision(recipe: Dictionary, base_dir: String = DEFAULT_BASE) -> Dictionary:
	var reason: String = Recipe.validate(recipe)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "recipe": recipe.duplicate(true)}
	if not valid_base(base_dir):
		return {"ok": false, "reason": "候选目录必须位于scenes/workshop_attachments或user://building_attachments；禁止正式库与路径穿越"}
	if not OS.has_feature("editor"):
		return {"ok": false, "reason": "候选另存仅供Godot编辑器版工具使用，不支持导出游戏运行时写入；现有候选未修改"}
	if python_path().is_empty():
		return {"ok": false, "reason": "候选另存需要本机Python3提供POSIX防链接/原子不覆盖提交；未找到Python3，本次未保存，现有候选未修改"}
	var built: Dictionary = Generator.build(recipe)
	if not built.ok:
		return built
	var root: Node3D = built.root
	var parent: String = base_dir.path_join(str(recipe.attachment_id))
	reason = create_directory(parent)
	if not reason.is_empty():
		root.free()
		return {"ok": false, "reason": reason}
	var revision: int = 1
	var directory: String = ""
	var parent_access: DirAccess = DirAccess.open(parent)
	if parent_access == null:
		root.free()
		return {"ok": false, "reason": "候选父目录不可访问"}
	while revision <= 9999:
		var leaf: String = "revision_%04d" % revision
		directory = parent.path_join(leaf)
		reason = path_reason(directory)
		if not reason.is_empty():
			root.free()
			return {"ok": false, "reason": reason}
		if parent_access.dir_exists(leaf) or parent_access.file_exists(leaf):
			revision += 1
			continue
		reason = create_directory(directory, true)
		if reason.is_empty():
			break
		if path_reason(directory).is_empty() and parent_access.dir_exists(leaf):
			revision += 1
			continue
		root.free()
		return {"ok": false, "reason": reason}
	if revision > 9999:
		root.free()
		return {"ok": false, "reason": "修订编号已耗尽"}
	var packed := PackedScene.new()
	var pack_error: Error = packed.pack(root)
	if pack_error != OK:
		root.free()
		return {"ok": false, "reason": "静态场景打包失败：%s" % pack_error, "directory": directory}
	var scene_path: String = directory.path_join("attachment.tscn")
	# 编辑器WRITE备份保存的物理路径带随机后缀；READ_WRITE保持.tscn目标名与清理路径一致。
	var temporary: FileAccess = FileAccess.create_temp(FileAccess.READ_WRITE, "sea_attachment", "tscn", false)
	if temporary == null:
		root.free()
		return {"ok": false, "reason": "无法创建临时静态场景：open_error=%d" % FileAccess.get_open_error(), "directory": directory}
	var temporary_path: String = temporary.get_path()
	temporary.close()
	var save_error: Error = ResourceSaver.save(packed, temporary_path)
	var open_error: Error = FileAccess.get_open_error()
	root.free()
	if save_error != OK:
		return {"ok": false, "reason": "场景保存失败：%d（%s）；临时文件=%s，扩展名=%s，handle_open=%s，open_error=%d" % [save_error, error_string(save_error), temporary_path.get_file(), temporary_path.get_extension(), temporary.is_open(), open_error], "directory": directory}
	reason = commit_file(temporary_path, scene_path)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "directory": directory}
	var documents: Dictionary = {
		"attachment.recipe.json": recipe.duplicate(true),
		"geometry.native.json": built.snapshot,
		"catalog_snapshot.json": Catalog.definitions(),
		"source_manifest.json": source_manifest()
	}
	for name: String in documents:
		reason = write_json(directory.path_join(name), documents[name])
		if not reason.is_empty():
			return {"ok": false, "reason": reason, "directory": directory}
	var hashes: Dictionary = {}
	for name: String in CANDIDATE_FILES:
		reason = path_reason(directory.path_join(name))
		if not reason.is_empty():
			return {"ok": false, "reason": reason, "directory": directory}
		hashes[name] = FileAccess.get_sha256(directory.path_join(name))
	var manifest: Dictionary = {"schema": "sea.building_attachments.candidate", "schema_version": 1, "committed": true, "immutable": true, "attachment_id": recipe.attachment_id, "type_id": recipe.type_id, "condition": recipe.condition, "revision": revision, "generator_version": Generator.GENERATOR_VERSION, "files_sha256": hashes, "stats": built.stats, "mount_anchor": built.mount_anchor, "runtime_path": null, "stage": "candidate_not_registered_not_world_installed", "source": documents["source_manifest.json"], "shared_materials": Catalog.definitions().materials}
	reason = write_json(directory.path_join("candidate_manifest.json"), manifest)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "directory": directory}
	return {"ok": true, "reason": "", "directory": directory, "revision": revision, "recipe_path": directory.path_join("attachment.recipe.json"), "scene_path": scene_path, "manifest_path": directory.path_join("candidate_manifest.json"), "stats": built.stats, "manifest": manifest}

static func read_json(path: String) -> Dictionary:
	var reason: String = path_reason(path)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "JSON文件不存在：" + path}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "JSON文件不可读：" + path}
	var length: int = file.get_length()
	if length <= 0 or length > MAX_JSON_BYTES:
		file.close()
		return {"ok": false, "reason": "JSON文件大小超限或为空：" + path}
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return {"ok": false, "reason": "JSON文件读取不完整：" + path}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return {"ok": false, "reason": "JSON解析失败：%s，第%d行：%s" % [path, parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Dictionary:
		return {"ok": false, "reason": "JSON根节点须为对象：" + path}
	return {"ok": true, "reason": "", "data": parser.data}

static func valid_sha256(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true

static func source_dependency_reason(source: Variant) -> String:
	if not source is Dictionary or not source.get("files") is Array:
		return "来源manifest缺少依赖列表"
	var allowed: Array[String] = [Catalog.PATH]
	for name: String in SOURCE_FILES:
		allowed.append("res://src/building_attachments/" + name)
	var seen: Dictionary = {}
	for item: Variant in source.files:
		if not item is Dictionary or not item.get("path") is String or not allowed.has(item.path):
			return "来源manifest包含白名单外依赖路径"
		if seen.has(item.path) or not valid_sha256(item.get("sha256")):
			return "来源manifest依赖重复或校验无效"
		seen[item.path] = true
	return "" if seen.size() == allowed.size() else "来源manifest依赖不完整"

static func load_recipe(path: String) -> Dictionary:
	if path.contains("..") or path.contains("\\"):
		return {"ok": false, "reason": "拒绝路径穿越"}
	var directory: String = path.get_base_dir() if path.get_file() == "attachment.recipe.json" else path.trim_suffix("/")
	if not valid_base(directory):
		return {"ok": false, "reason": "只接受独立外挂候选修订路径"}
	var parsed: Dictionary = read_json(directory.path_join("candidate_manifest.json"))
	if not parsed.ok:
		return parsed
	var manifest: Dictionary = parsed.data
	if manifest.get("schema", "") != "sea.building_attachments.candidate" or manifest.get("schema_version") != 1 or manifest.get("committed") != true:
		return {"ok": false, "reason": "候选缺少完整提交manifest"}
	var reason: String = source_dependency_reason(manifest.get("source"))
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	if manifest.get("shared_materials") != SHARED_MATERIALS:
		return {"ok": false, "reason": "manifest材质依赖不在正式白名单内"}
	var hashes: Variant = manifest.get("files_sha256")
	if not hashes is Dictionary or hashes.size() != CANDIDATE_FILES.size():
		return {"ok": false, "reason": "manifest文件依赖必须恰为五个候选文件"}
	for key: Variant in hashes:
		if not CANDIDATE_FILES.has(key):
			return {"ok": false, "reason": "manifest文件依赖不在白名单内"}
	for name: String in CANDIDATE_FILES:
		reason = path_reason(directory.path_join(name))
		if not reason.is_empty():
			return {"ok": false, "reason": reason}
		if not valid_sha256(hashes.get(name)) or not FileAccess.file_exists(directory.path_join(name)):
			return {"ok": false, "reason": "候选文件缺失或校验无效：" + name}
		var file: FileAccess = FileAccess.open(directory.path_join(name), FileAccess.READ)
		if file == null:
			return {"ok": false, "reason": "候选文件不可读：" + name}
		var length: int = file.get_length()
		file.close()
		if length <= 0 or length > MAX_CANDIDATE_FILE_BYTES:
			return {"ok": false, "reason": "候选文件大小超限或为空：" + name}
		if FileAccess.get_sha256(directory.path_join(name)) != hashes[name]:
			return {"ok": false, "reason": "候选文件损坏或被修改：" + name}
	parsed = read_json(directory.path_join("source_manifest.json"))
	if not parsed.ok:
		return parsed
	reason = source_dependency_reason(parsed.data)
	if not reason.is_empty() or parsed.data != manifest.source:
		return {"ok": false, "reason": "来源manifest不一致或依赖越界：" + reason}
	parsed = read_json(directory.path_join("attachment.recipe.json"))
	if not parsed.ok:
		return parsed
	var data: Dictionary = parsed.data
	reason = Recipe.validate(data)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "recipe": data}
	if manifest.get("attachment_id") != data.attachment_id or manifest.get("type_id") != data.type_id or manifest.get("condition") != data.condition:
		return {"ok": false, "reason": "manifest与配方身份不一致", "recipe": data}
	# 场景仅作历史产物校验；UI须用Generator.build(recipe)重建，绝不加载候选scene或脚本。
	return {"ok": true, "reason": "", "recipe": data, "directory": directory, "scene_path": directory.path_join("attachment.tscn"), "manifest": manifest}
