#!/usr/bin/env python3
"""只读校验真实连续实体报告并交付候选；不启动引擎、不登记正式资产。"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import re
import stat
import struct
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
DEFAULT_OUTPUT = Path("D:/projects/sea-work/building_workshop/continuous_v002/outputs")
OLD_IMAGE = Path("D:/projects/sea-work/building_workshop/editor_v001/outputs/workshop_editor_1600x1000.png")
KIND = "workshop_continuous_delivery"
GENERATOR = "sea_workshop_continuous_shell_v2"
BUNDLE = ("building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json")
MODEL_PNGS = tuple(f"workshop_shell_model_{view}.png" for view in ("rect", "front", "l"))
EDITOR_PNGS = tuple(f"workshop_editor_1600x1000_continuous_{view}.png" for view in ("rect", "front", "back", "l_top", "l"))
PALETTE = "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
RECIPE_FIELDS = set((
    "schema schema_version building_id display_name revision standards_id catalog_id construction_mode "
    "shape width depth floors floor_height slab_thickness wall_thickness column_width window_width "
    "window_height window_sill bay_width door_width door_height bevel_segments bevel_width taper "
    "spatial_profile aging damage vegetation_density growth_weights structure_seed damage_seed "
    "vegetation_seed component_bindings floor_overrides facade_overrides slot_overrides excluded_slots locked_vegetation"
).split())
TOPOLOGY_ERRORS = (
    "boundary_edges", "nonmanifold_edges", "orientation_errors", "duplicate_triangles",
    "degenerate_triangles", "nonfinite_vertices", "normal_errors", "uv_area_errors",
    "uv_safe_errors", "colour_errors", "disconnected_parts", "window_ring_errors", "nonpositive_volumes",
)
KNOWN_LIMITS = [
    "passed 仅表示本脚本读取的真实报告、文件身份/hash、静态安全与交付完整性通过；不签用户美术终验。",
    "连续实体/洞口与接合证据不等于土木结构安全、受力承载或复杂物理验收。",
    "复杂 damage、结构位移、任意外部 prefab 适配和未知参数组合未签署。",
    "楼梯、全楼可达、正式导航、正式世界接入、完整风格及完整 Blender/GLB 链未签署。",
    "截图只使用真实 PNG，比较图完整等比缩放，不猜旧 viewport 裁剪区域，不使用 AI 补图。",
    "模型像素主体宽度按与背景差异测量，可能包含阴影；不能代替人工视觉审阅。",
    "本脚本不执行 Godot、契约检查、性能测试、插件卸载重载或跨进程恢复。",
    "两个候选仍为 exported_pending_project_registration；绝不修改 Main、registry 或旧资产。",
    "ZIP 仅含两组原 building_id/revision_0001 五件及 JSON 说明，不含截图或公共色板；依赖生产 res:// 色板路径。",
    "hash guard 仅覆盖本次实际读取的输入，不证明工程在历史或并行操作中从未变化。",
]


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def absolute(value: str | Path) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise ValueError(f"必须使用绝对路径：{value}")
    return path.resolve()


def within(path: Path, parent: Path) -> bool:
    return path == parent or path.is_relative_to(parent)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def plain_path(path: Path) -> None:
    # Windows junction 也属于重解析点，不能只检查 is_symlink()。
    for item in (path, *path.parents):
        if item.exists() or item.is_symlink():
            info = item.lstat()
            require(not stat.S_ISLNK(info.st_mode) and not (
                getattr(info, "st_file_attributes", 0) & 0x400), f"拒绝链接/重解析路径：{item}")


def resource(value: str, project: Path) -> Path:
    require(isinstance(value, str) and value.startswith("res://"), f"非法资源路径：{value}")
    suffix = value[6:]
    require(bool(suffix) and "\\" not in suffix and ":" not in suffix
            and all(part not in ("", ".", "..") for part in suffix.split("/")), f"不安全资源路径：{value}")
    path = project / suffix
    require(within(path.resolve(), project.resolve()), f"资源路径逃逸：{value}")
    return path


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def stable(value: Any) -> str:
    # 对应 Catalog._stable_string，整数值浮点数不带小数部分。
    if isinstance(value, dict):
        return "{" + ",".join(stable(k) + ":" + stable(value[k]) for k in sorted(value)) + "}"
    if isinstance(value, list):
        return "[" + ",".join(stable(v) for v in value) + "]"
    if isinstance(value, float) and value.is_integer() and abs(value) <= 9007199254740991:
        return str(int(value))
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def positive(value: Any) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value > 0


class Delivery:
    def __init__(self) -> None:
        self.checks: list[dict[str, Any]] = []
        self.inputs: dict[Path, str] = {}
        self.cache: dict[Path, bytes] = {}

    def check(self, name: str, passed: bool, detail: Any = None) -> None:
        self.checks.append({"name": name, "passed": passed is True, "detail": detail})

    def read(self, path: Path) -> bytes:
        path = path.resolve()
        raw = path.read_bytes()
        require(path not in self.inputs or self.inputs[path] == digest(raw), f"输入已变化：{path}")
        self.inputs[path] = digest(raw)
        self.cache[path] = raw
        return raw

    def obj(self, path: Path) -> dict[str, Any]:
        def reject_constant(value: str) -> None:
            raise ValueError(f"JSON 不允许非有限数值：{value}")

        def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
            result = {}
            for key, value in pairs:
                require(key not in result, f"JSON 重复键：{key}")
                result[key] = value
            return result

        value = json.loads(self.read(path).decode("utf-8-sig"), parse_constant=reject_constant, object_pairs_hook=unique)
        require(isinstance(value, dict), f"JSON 必须是对象：{path}")
        return value

    def match(self, path: Path, expected: Any, label: str) -> None:
        actual = digest(self.read(path))
        self.check(label, isinstance(expected, str) and re.fullmatch(r"[0-9a-f]{64}", expected) is not None
                   and expected == actual, {"path": path.as_posix(), "expected": expected, "actual": actual})

    def guard(self) -> dict[str, Any]:
        changed = []
        for path, expected in list(self.inputs.items()):
            try:
                actual = digest(path.read_bytes())
            except OSError:
                actual = None
            if actual != expected:
                changed.append({"path": path.as_posix(), "before": expected, "after": actual})
        self.check("本轮输入读取前后 SHA256 一致", not changed, changed)
        return {"same": not changed, "changed": changed, "files": {p.as_posix(): h for p, h in sorted(self.inputs.items())}}

    def stage(self, name: str, action: Any) -> Any:
        try:
            return action()
        except Exception as exc:
            self.check(name, False, f"{type(exc).__name__}: {exc}")
            return None

    def ok(self) -> bool:
        return bool(self.checks) and all(row["passed"] is True for row in self.checks)


def runner(a: Delivery, path: Path, suite: str) -> dict[str, Any]:
    require(path.name == "report.json", "CLI 必须指向外层实际 runner report.json")
    outer = a.obj(path)
    run_dir = absolute(outer["run_dir"])
    require(run_dir == path.parent, "外层 run_dir 与 report 所在目录不一致")
    require(not within(run_dir, ROOT) and not within(ROOT, run_dir), "runner 必须来自工程外独立目录")
    results = outer["results"]
    require(isinstance(results, dict) and suite in results, f"外层报告缺少 {suite}")
    for name, row in results.items():
        require(isinstance(row, dict), f"runner result 无效：{name}")
        a.check("runner 实际结果：" + name, row.get("passed") is True and type(row.get("exit_code")) is int
                and row["exit_code"] == 0 and row.get("unexpected_errors") == [] and row.get("expected_errors", []) == []
                and row.get("completion_marker") is True and row.get("failure_labels", []) == []
                and row.get("failure_markers", []) == [], row)
    if "passed" in outer:
        a.check("runner 顶层 passed", outer["passed"] is True)
    if "asset_import" in outer:
        imported = outer["asset_import"]
        a.check("runner asset_import 无错误", imported.get("exit_code") == 0 and imported.get("unexpected_errors") == [], imported)
    result = results[suite]
    command = result["command"]
    require(isinstance(command, list) and all(isinstance(v, str) for v in command)
            and command.count("--path") == 1, "runner command 必须含唯一 --path")
    project = absolute(command[command.index("--path") + 1])
    require(project == (run_dir / "project").resolve() and project.is_dir(), "runner project 身份或目录无效")
    args = command[1:command.index("--")] if "--" in command else command[1:]
    if suite == "editor-workshop":
        a.check("真实编辑器而非 headless/script", "--editor" in args and not any(
            v in ("--headless", "--script", "-s") or v.startswith("--script=") for v in args)
            and "--" in command and "--workshop-editor-verify" in command[command.index("--") + 1:])
    else:
        a.check("geometry 实际专项命令", "--headless" in args and "--script" in args
                and args[args.index("--script") + 1] == "res://tests/test_workshop_shell.gd")
    log_path = absolute(result["log"])
    require(within(log_path, run_dir) and not within(log_path, project), "日志必须属于同一 runner 批次")
    text = a.read(log_path).decode("utf-8-sig")
    tag = "workshop-editor" if suite == "editor-workshop" else "workshop-shell"
    markers = re.findall(r"\[" + tag + r"\]\s+(\d+)\s+checks,\s+(\d+)\s+failures", text)
    a.check("日志唯一完成标记：" + suite, len(markers) == 1, markers)
    require(len(markers) == 1, "日志缺少唯一实际完成计数")
    count, failures = map(int, markers[0])
    a.check("日志实际零失败：" + suite, count > 0 and failures == 0, {"checks": count, "failures": failures})
    a.check("日志无失败/引擎错误：" + suite, re.search(
        r"^\s*(?:FAIL\b|(?:SCRIPT\s+)?ERROR:|Parse Error:|Invalid (?:call|access))", text, re.M) is None)
    inner_path = project / "outputs" / ("workshop_editor_report.json" if suite == "editor-workshop" else "workshop_shell_report.json")
    inner = a.obj(inner_path)
    return {"outer_path": path.as_posix(), "inner_path": inner_path.as_posix(), "project": project,
            "inner": inner, "log_checks": count, "log_failures": failures, "head": outer.get("head"), "command": command}


def editor_report(a: Delivery, evidence: dict[str, Any]) -> list[dict[str, Any]]:
    editor, project = evidence["inner"], evidence["project"]
    a.check("editor 内层 passed 且 failures 为空", editor.get("passed") is True and editor.get("failures") == [])
    for key, expected in {"enginehint": True, "is_playing": False, "scene_unchanged": True,
                          "root_paused_unchanged": True, "game_save_connected": False}.items():
        a.check("editor 状态：" + key, editor.get(key) is expected, editor.get(key))
    a.check("editor dependencies 为空", editor.get("dependencies") == [])
    a.check("editor 内层隔离项目身份", absolute(editor["project_path"]) == project)
    config = a.read(project / "project.godot").decode("utf-8-sig")
    autoload = re.search(r'^\[autoload\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)
    a.check("实际隔离配置无 Autoload/Main", (autoload is None or not any(
        line.strip() and not line.lstrip().startswith(";") for line in autoload[1].splitlines()))
        and re.search(r'^run/main_scene\s*=\s*"[^"\n]+"', config, re.M) is None)
    enabled = re.search(r'^\[editor_plugins\]\s*\n(.*?)(?=^\[|\Z)', config, re.M | re.S)
    a.check("实际隔离配置仅工坊插件", enabled is not None and re.findall(
        r'"(res://[^"\n]+)"', enabled[1]) == ["res://addons/building_workshop/plugin.cfg"])
    checks = editor["checks"]
    require(isinstance(checks, list) and bool(checks), "editor checks 必须是非空逐项数组")
    a.check("editor 日志与 checks 数一致", len(checks) == evidence["log_checks"])
    for index, row in enumerate(checks):
        a.check(f"editor check[{index}]", isinstance(row, dict) and isinstance(row.get("name"), str)
                and bool(row["name"]) and row.get("passed") is True, row)
    samples = editor["shell_samples"]
    require(isinstance(samples, list) and len(samples) == 2, "shell_samples 必须恰为两个，禁止筛选历史/重复样例")
    identities, shapes = set(), set()
    for sample in samples:
        recipe = sample["recipe"]
        building_id = sample["building_id"]
        require(isinstance(building_id, str) and re.fullmatch(r"shell_(?:rect|l)_[0-9]+_[0-9]+", building_id) is not None,
                "连续候选必须使用真实新 shell building_id")
        a.check("shell recipe 字段完整：" + building_id, set(recipe) == RECIPE_FIELDS)
        a.check("shell recipe 完整身份及模式：" + building_id, recipe.get("building_id") == building_id
                and recipe.get("construction_mode") == "shell_v2" and recipe.get("revision") == 1
                and recipe.get("schema") == "sea.workshop.building_recipe")
        identities.add(building_id)
        shapes.add(recipe["shape"])
        require(recipe["shape"] in ("rectangle", "l"), "shell shape 非当前矩形/L形")
        expected_pngs = (*MODEL_PNGS[:2], *EDITOR_PNGS[:3]) if recipe["shape"] == "rectangle" else (MODEL_PNGS[2], *EDITOR_PNGS[3:])
        a.check("样例图片与实际形状绑定：" + building_id,
                set(sample.get("artifacts", [])) == {"res://outputs/" + name for name in expected_pngs})
        a.check("样例 ID 属于本轮 buildids：" + building_id, building_id in editor.get("buildids", []))
        audit = sample["actual_geometry"]
        topology = audit["actual_mesh_topology"]
        require(isinstance(topology, dict) and bool(topology), "缺少实际 mesh topology，不能使用生成器辅助 metadata 代替")
        for part, value in topology.items():
            a.check(building_id + " 实际拓扑：" + part, value.get("closed") is True and value.get("oriented") is True
                    and value.get("connected_components") == 1 and positive(value.get("triangles"))
                    and all(type(value.get(k)) is int and value[k] == 0 for k in
                            ("boundary_edges", "nonmanifold_edges", "orientation_errors")), value)
        floors = recipe["floors"]
        expected_parts = {f"wall_shell_{n}" for n in range(floors)} | {f"slab_{n}" for n in range(floors)} | {"roof_main"}
        a.check("shell 连续结构组织：" + building_id, expected_parts <= set(topology)
                and audit.get("wall_shells") == floors and audit.get("slabs") == floors and audit.get("roofs") == 1)
        body = audit["geometry"]
        a.check("shell 实际模型无脚本/预览节点：" + building_id, positive(body.get("visual_meshes"))
                and positive(body.get("collision_shapes")) and all(body.get(k) == 0 for k in ("scripts", "editor_nodes", "unowned_nodes")), body)
    require(len(identities) == 2 and shapes == {"rectangle", "l"}, "必须是两个独立新 ID，矩形与 L 形各一个")
    return samples


def geometry_report(a: Delivery, evidence: dict[str, Any]) -> dict[str, Any]:
    inner = evidence["inner"]
    require(inner.get("suite") == "workshop-shell", "geometry 内层 suite 不一致")
    count, failures = inner["checks"], inner["failures"]
    require(type(count) is int and count > 0 and isinstance(failures, list), "geometry checks/failures 格式无效")
    a.check("geometry 实际计数与日志一致且零失败", count == evidence["log_checks"]
            and inner.get("failure_count") == len(failures) == evidence["log_failures"] == 0, failures)
    if "passed" in inner:
        a.check("geometry 内层 passed", inner["passed"] is True)
    fixtures = inner["fixtures"]
    expected_fixtures = {"rect_12x9_f3", "l_12x12_f3", "rect_f1", "rect_f5", "l_f1", "l_f5", "floor_1_override", "left_windows_disabled"}
    require(isinstance(fixtures, dict) and set(fixtures) == expected_fixtures, "geometry 实际 fixtures 不完整或不是当前专项集合")
    result = {"checks_count": count, "failure_count": inner.get("failure_count"), "failures": failures,
              "fixtures": {}, "visual_acceptance": inner.get("visual_acceptance")}
    for name, fixture in fixtures.items():
        for field in ("nodes", "triangles", "structure_triangles", "legacy_structure_triangles"):
            require(positive(fixture.get(field)), f"fixture {name} 缺少真实统计 {field}")
        ratio = fixture["structure_triangles"] / fixture["legacy_structure_triangles"]
        a.check("fixture 结构面数比：" + name, type(fixture.get("structure_triangle_ratio")) in (int, float)
                and math.isclose(ratio, fixture["structure_triangle_ratio"], rel_tol=1e-6, abs_tol=1e-8)
                and ratio < 0.65, {"calculated": ratio, "reported": fixture.get("structure_triangle_ratio")})
        topology = fixture["actual_topology"]
        a.check("fixture 实际拓扑零错误：" + name, all(type(topology.get(k)) is int and topology[k] == 0
                for k in TOPOLOGY_ERRORS) and positive(topology.get("window_frames")), topology.get("bad_parts"))
        a.check("fixture 当前生成器：" + name, fixture.get("generator_version") == GENERATOR)
        result["fixtures"][name] = {k: fixture[k] for k in (
            "nodes", "triangles", "structure_triangles", "legacy_structure_triangles", "structure_triangle_ratio", "actual_topology")}
    result["fixture_count"] = len(fixtures)
    return result


def sources(a: Delivery, projects: list[Path]) -> list[dict[str, Any]]:
    paths = set((GODOT / "src/workshop").glob("*.gd")) | set((GODOT / "addons/building_workshop").glob("*.gd"))
    paths |= set((GODOT / "tests").glob("*workshop*.gd")) | {ROOT / "scripts/run_verification.py", Path(__file__).resolve()}
    require(all((GODOT / "src/workshop" / name).is_file() for name in
                ("shell_generator.gd", "shell_geometry.gd", "recipe.gd", "store.gd", "session.gd")), "连续内核源缺失")
    result = []
    for path in sorted(paths):
        raw = a.read(path)
        row = {"path": path.as_posix(), "sha256": digest(raw), "isolated_copies": []}
        if within(path, GODOT):
            relative = path.relative_to(GODOT)
            for project in projects:
                copied = project / relative
                if not (project / "tests").is_dir():
                    # runner 的编辑器最小副本只复制这八个共享内核，不复制 runtime UI/tests。
                    if relative.parts[0] == "tests" or (relative.parts[:2] == ("src", "workshop")
                            and path.stem not in {"recipe", "catalog", "generator", "mesh_builder", "session", "store", "shell_geometry", "shell_generator"}):
                        continue
                copied_raw = a.read(copied)
                a.check("隔离代码与当前源码一致：" + copied.as_posix(), raw.replace(b"\r\n", b"\n") == copied_raw.replace(b"\r\n", b"\n"))
                row["isolated_copies"].append({"path": copied.as_posix(), "sha256": digest(copied_raw), "comparison": "CRLF 转 LF"})
        result.append(row)
    return result


def bundle(a: Delivery, project: Path, editor: dict[str, Any], sample: dict[str, Any]) -> dict[str, Any]:
    building_id = sample["building_id"]
    directory = project / "outputs/workshop_editor" / building_id / "revision_0001"
    require(within(directory.resolve(), project), "五件目录逃逸隔离项目")
    artifacts = {resource(v, project).resolve() for v in editor["artifacts"]}
    files = {name: directory / name for name in BUNDLE}
    raw = {}
    for name, path in files.items():
        require(path.resolve() in artifacts, f"五件未列入真实 artifacts：{path}")
        raw[name] = a.read(path)
    recipe, catalog, manifest, ledger = (a.obj(files[name]) for name in (
        "building.recipe.json", "catalog_snapshot.json", "candidate_manifest.json", "ledger.json"))
    a.check("五件原始身份：" + building_id, all(v.get("building_id") == building_id
            and type(v.get("revision")) is int and v["revision"] == 1 for v in (recipe, manifest, ledger)))
    a.check("落盘 recipe 与完整当前 shell 配方一致：" + building_id, recipe == sample["recipe"]
            and set(recipe) == RECIPE_FIELDS and recipe.get("construction_mode") == "shell_v2")
    a.check("manifest 精确五件清单：" + building_id, isinstance(manifest.get("file_list"), list)
            and sorted(manifest["file_list"]) == sorted(BUNDLE))
    a.check("manifest 新 generator 及候选边界：" + building_id, manifest.get("generator") == GENERATOR
            and manifest.get("construction_mode") == "shell_v2" and manifest.get("authoring_context") == "editor"
            and manifest.get("noMain") is True and manifest.get("formal_registry_written") is False
            and manifest.get("static_scene") is True and manifest.get("has_workshop_rebuild_script") is False
            and manifest.get("preview_camera_lights_packed") is False and ledger.get("status") == "candidate_only"
            and all(v.get("candidate_ledger_status") == "exported_pending_project_registration" for v in (manifest, ledger)))
    recorded = manifest["source_hashes"]
    require(isinstance(recorded, dict) and set(recorded) == {"building.recipe.json", "catalog_snapshot.json", "building.tscn"},
            "manifest source_hashes 必须为已知三个实际源文件")
    for name, expected in recorded.items():
        a.match(files[name], expected, building_id + " manifest source hash：" + name)
    a.match(files["building.tscn"], manifest.get("hash"), building_id + " 场景总 hash")
    authoring = manifest["authoring_source_hashes"]
    required_sources = {"res://src/workshop/" + name + ".gd" for name in ("recipe", "catalog", "generator", "mesh_builder", "store")}
    required_sources |= {"res://addons/building_workshop/" + name + ".gd" for name in ("editor_store", "catalog_adapter")}
    required_sources |= {"res://data/workshop/" + name + ".json" for name in ("catalog_v1", "standards_v1", "palette_cells_v1")}
    require(isinstance(authoring, dict) and required_sources <= set(authoring), "缺少必要创作源逐条 hash")
    for value, expected in authoring.items():
        a.match(resource(value, project), expected, building_id + " 创作源逐条 hash：" + value)
    a.check("catalog ID 绑定：" + building_id, bool(catalog.get("catalog_id"))
            and recipe.get("catalog_id") == catalog["catalog_id"] == manifest.get("catalog_id"))
    a.check("catalog 确定性指纹：" + building_id, digest(stable(catalog).encode("utf-8")) == manifest.get("catalog_fingerprint"))
    a.check("catalog 本轮原始目录与生产目录一致：" + building_id,
            catalog == a.obj(project / "data/workshop/catalog_v1.json") == a.obj(GODOT / "data/workshop/catalog_v1.json"))
    components = catalog["components"]
    require(isinstance(components, dict) and bool(components), "catalog components 不能为空")
    for component_id, definition in components.items():
        require(isinstance(definition, dict) and bool(definition.get("version")), f"catalog 组件缺少版本：{component_id}")
        if definition.get("kind") == "prefab":
            version = definition["version"]
            require(version.startswith("sha256:"), "prefab version 必须记录 SHA256")
            a.match(resource(definition["prefab"], project), version[7:], "catalog prefab hash：" + component_id)
            # 交付五件不捎带隔离 fixture；当前新样例应为纯参数目录。
            a.check("catalog prefab 在生产存在且一致：" + component_id,
                    a.read(resource(definition["prefab"], GODOT)) == a.read(resource(definition["prefab"], project)))
    for component_id in recipe["component_bindings"].values():
        a.check("recipe catalog 组件引用：" + str(component_id), component_id in components)
    text = raw["building.tscn"].decode("utf-8-sig")
    node_types = re.findall(r'^\[node\b[^\n]*\btype\s*=\s*"([^"]+)"', text, re.M)
    allowed_types = {"Node3D", "MeshInstance3D", "StaticBody3D", "CollisionShape3D"}
    a.check("TSCN 静态节点白名单无相机灯光：" + building_id, bool(node_types) and set(node_types) <= allowed_types)
    a.check("TSCN 无 Script/嵌套场景：" + building_id, re.search(
        r'\btype\s*=\s*"[^"]*(?:Script|PackedScene)"|^\s*script\s*=|\.(?:gd|cs|gdextension)"|\binstance\s*=', text, re.M | re.I) is None)
    a.check("场景 generator/mode metadata：" + building_id,
            f'metadata/generator_version = "{GENERATOR}"' in text and 'metadata/construction_mode = "shell_v2"' in text)
    dependencies = []
    for declaration in re.findall(r'^\[ext_resource\b[^\n]*\]', text, re.M):
        path_match = re.search(r'\bpath\s*=\s*"([^"]+)"', declaration)
        type_match = re.search(r'\btype\s*=\s*"([^"]+)"', declaration)
        require(path_match is not None and type_match is not None, "TSCN 外部依赖缺少 path/type")
        value = path_match[1]
        require(value == PALETTE and type_match[1] == "Texture2D", "五件静态场景只允许生产公共色板外部依赖")
        isolated, production = resource(value, project), resource(value, GODOT)
        a.check("生产色板与隔离色板一致（不复制）：" + building_id, a.read(isolated) == a.read(production))
        dependencies.append({"resource": value, "production_path": production.as_posix(), "sha256": a.inputs[production.resolve()], "packaged": False})
    require(bool(dependencies), "静态场景缺少真实公共色板依赖")
    return {"building_id": building_id, "revision": 1, "source_directory": directory.as_posix(),
            "hashes": {name: digest(data) for name, data in raw.items()}, "files": [p.as_posix() for p in files.values()],
            "dependencies": dependencies, "formal_registration": "pending"}


def png(a: Delivery, path: Path, size: tuple[int, int] | None) -> tuple[Any, dict[str, Any]]:
    from PIL import Image

    raw = a.read(path)
    require(len(raw) >= 33 and raw[:8] == b"\x89PNG\r\n\x1a\n" and raw[12:16] == b"IHDR", f"不是真实 PNG：{path}")
    dimensions = struct.unpack(">II", raw[16:24])
    require(size is None or dimensions == size, f"PNG 真实尺寸错误：{path}，{dimensions}，预期 {size}")
    with Image.open(io.BytesIO(raw)) as image:
        require(image.format == "PNG" and image.size == dimensions, "PNG 解码格式或尺寸不一致")
        image.verify()
    with Image.open(io.BytesIO(raw)) as image:
        image.load()
        rgb = image.convert("RGB")
    return rgb, {"source": path.as_posix(), "sha256": digest(raw), "width": dimensions[0], "height": dimensions[1], "art_accepted": False}


def new_file(path: Path, raw: bytes) -> str:
    plain_path(path)
    require(path.parent.is_dir(), f"写文件前父目录必须存在：{path.parent}")
    if path.exists():
        require(path.is_file() and path.read_bytes() == raw, f"拒绝覆盖差异文件：{path}")
        return "identical"
    with path.open("xb") as stream:
        stream.write(raw)
    return "created"


def visuals(a: Delivery, evidence: dict[str, Any], output: Path, summary: dict[str, Any]) -> None:
    from PIL import Image, ImageChops, ImageDraw, ImageFont

    editor, project = evidence["inner"], evidence["project"]
    artifacts = {resource(v, project).resolve() for v in editor["artifacts"]}
    images = {}
    pending = []
    for name in (*MODEL_PNGS, *EDITOR_PNGS):
        path = project / "outputs" / name
        require(path.resolve() in artifacts, f"真实报告没有 PNG artifact：{name}")
        image, row = png(a, path, (1400, 1100) if name in MODEL_PNGS else None)
        if name in MODEL_PNGS:
            background = Image.new("RGB", image.size, image.getpixel((0, 0)))
            difference = ImageChops.difference(image, background)
            channels = difference.split()
            mask = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2]).point(lambda x: 255 if x > 0.08 * 255 else 0)
            bounds = mask.getbbox()
            width = bounds[2] - bounds[0] if bounds else 0
            a.check("实际 PNG 前景宽度至少600：" + name, width >= 600, {"foreground_bbox": bounds, "width": width})
            row["foreground_width"] = width
        images[name] = image
        row["local_path"] = (output / name).as_posix()
        pending.append((name, row))
    # 全部实际解码/尺寸验证后才复制，原始 PNG 字节不重编码。
    for name, row in pending:
        row["copy_status"] = new_file(output / name, a.cache[(project / "outputs" / name).resolve()])
        summary["png_local_copies"].append(row)
    old, old_row = png(a, OLD_IMAGE, None)
    font_path = next((p for p in (Path("C:/Windows/Fonts/msyh.ttc"), Path("C:/Windows/Fonts/msyhbd.ttc"))
                      if p.is_absolute() and p.is_file()), None)
    require(font_path is not None, "找不到实际存在的 Windows Microsoft YaHei 绝对字体路径")
    a.read(font_path)
    title_font = ImageFont.truetype(str(font_path), 28)
    note_font = ImageFont.truetype(str(font_path), 18)
    canvas = Image.new("RGB", (1400, 900), "#edf0f3")
    draw = ImageDraw.Draw(canvas)
    draw.text((32, 18), "旧：开间拼块", font=title_font, fill="#263348")
    draw.text((730, 18), "新：连续实体", font=title_font, fill="#263348")
    for image, box in ((old, (24, 76, 688, 820)), (images[MODEL_PNGS[0]], (712, 76, 1376, 820))):
        fitted = image.copy()
        fitted.thumbnail((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
        canvas.paste(fitted, (box[0] + (box[2] - box[0] - fitted.width) // 2, box[1] + (box[3] - box[1] - fitted.height) // 2))
    draw.text((24, 844), "左：历史编辑器完整原图；右：本轮矩形模型大图。仅等比缩放，未裁剪、未生成或补绘模型。", font=note_font, fill="#445064")
    stream = io.BytesIO()
    canvas.save(stream, format="PNG")
    target = output / "model_comparison.png"
    new_file(target, stream.getvalue())
    summary["comparison"] = {"path": target.as_posix(), "sha256": digest(stream.getvalue()), "width": 1400, "height": 900,
                             "old": old_row, "new": (output / MODEL_PNGS[0]).as_posix(), "font": font_path.as_posix(), "crop": None,
                             "art_accepted": False}


def install(a: Delivery, bundles: list[dict[str, Any]], requested: bool) -> list[dict[str, Any]]:
    parent = GODOT / "scenes"
    require(parent.is_dir(), f"必须先确认 ROOT/godot/scenes 父目录已存在：{parent}")
    plain_path(parent)
    candidate_root = parent / "workshop_buildings"
    plans = []
    # 两个目标一起预检，任一差异都不开始安装；不使用 copytree 或 glob 收集。
    for row in bundles:
        target = candidate_root / row["building_id"] / "revision_0001"
        plain_path(target)
        if target.exists():
            require(target.is_dir() and {p.name for p in target.iterdir()} == set(BUNDLE), f"候选目录不是精确五件：{target}")
            for name in BUNDLE:
                require((target / name).is_file() and digest((target / name).read_bytes()) == row["hashes"][name], f"已有候选存在差异，拒绝覆盖：{target / name}")
        elif target.parent.exists():
            require(target.parent.is_dir() and not any(target.parent.iterdir()), f"拒绝向已有其他版本/资产目录追加：{target.parent}")
        plans.append({"building_id": row["building_id"], "directory": target.as_posix(),
                      "files": [(target / name).as_posix() for name in BUNDLE], "status": "identical" if target.exists() else "not_installed",
                      "formal_registration": "pending"})
    if not requested:
        return plans
    a.guard()
    require(a.ok(), "安装前输入或其他必要校验未通过")
    for row, plan in zip(bundles, plans):
        target = Path(plan["directory"])
        if target.exists():
            continue
        # mkdir 不递归：上一级每一步都在 Python 明确检查后创建。
        for directory in (candidate_root, target.parent, target):
            plain_path(directory)
            require(directory.parent.is_dir(), f"创建前父目录不存在：{directory.parent}")
            if not directory.exists():
                directory.mkdir()
            require(directory.is_dir(), f"不是目录：{directory}")
        for name in BUNDLE:
            data = a.cache[(Path(row["source_directory"]) / name).resolve()]
            new_file(target / name, data)
            require(digest((target / name).read_bytes()) == row["hashes"][name], f"安装后 hash 不匹配：{target / name}")
        plan["status"] = "installed_candidate_only"
    return plans


def package(a: Delivery, bundles: list[dict[str, Any]], output: Path) -> dict[str, Any]:
    members = {}
    for row in bundles:
        for name in BUNDLE:
            members[f"{row['building_id']}/revision_0001/{name}"] = a.cache[(Path(row["source_directory"]) / name).resolve()]
    members["delivery_report.json"] = json_bytes({"kind": KIND, "candidate_validation_passed": True,
        "formal_registration": "pending", "bundles": bundles, "known_limits": KNOWN_LIMITS,
        "instructions": "仅两个原ID/revision_0001候选；公共色板保持生产res://路径，不随包复制；不得据此自动登记或接入Main。"})
    require(len(members) == 11 and all(Path(name).suffix in (".json", ".tscn") for name in members), "ZIP 白名单错误")
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, raw in sorted(members.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, raw)
    raw = stream.getvalue()
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        require(archive.testzip() is None and set(archive.namelist()) == set(members), "ZIP 完整性验证失败")
        require(all(archive.read(name) == content for name, content in members.items()), "ZIP 五件内容变化")
    target = output / "continuous_candidates.zip"
    state = new_file(target, raw)
    return {"path": target.as_posix(), "sha256": digest(raw), "status": state,
            "members": [{"path": name, "sha256": digest(content)} for name, content in sorted(members.items())], "public_palette_packaged": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-report", required=True, type=Path, help="真实 editor 外层 runner report.json 绝对路径")
    parser.add_argument("--geometry-report", required=True, type=Path, help="真实 geometry 外层 runner report.json 绝对路径")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT, help="工程外交付输出目录")
    parser.add_argument("--install-candidates", action="store_true", help="仅校验全部通过后安装两个新候选，不正式登记")
    parser.add_argument("--contract-status", type=Path, help="可选，只读现有全工程契约状态 JSON，单独列示不代签")
    args = parser.parse_args()
    a = Delivery()
    summary: dict[str, Any] = {"kind": KIND, "schema_version": 1, "created_at": datetime.now(timezone.utc).isoformat(),
        "passed": False, "status": "failed", "engine_executed": False, "formal_registration": "pending",
        "scope": "真实连续模型证据、静态候选五件、可追溯交付；非美术/土木结构/复杂物理或damage终验",
        "known_limits": KNOWN_LIMITS, "png_local_copies": [], "bundles": [], "candidate_installations": [],
        "install_requested": args.install_candidates, "zip": None, "source_code_hashes": [],
        "whole_project_contracts": {"requested": bool(args.contract_status), "status": "not_provided", "passed": None}}
    try:
        output = absolute(args.output_root)
        editor_path, geometry_path = absolute(args.editor_report), absolute(args.geometry_report)
        require(not within(output, ROOT) and not within(ROOT, output), "输出必须在正式工程外，且不能是工程祖先")
        require(editor_path != geometry_path, "两个 CLI 输入必须为各自外层 runner report")
        for path in (editor_path, geometry_path, OLD_IMAGE, *([absolute(args.contract_status)] if args.contract_status else [])):
            require(not within(path, output), "输出目录不能包含输入报告或历史图片")
        for path in (editor_path, geometry_path, OLD_IMAGE):
            require(not within(output, path.parent) and not within(path.parent, output), "输出目录不能与 runner/历史图片证据目录重叠")
        plain_path(output)
        require(output.parent.is_dir(), "output-root 的父目录必须已存在")
        if not output.exists():
            output.mkdir()
        require(output.is_dir(), "output-root 必须是目录")
        report_path = output / "continuous_delivery_report.json"
        plain_path(report_path)
        if report_path.exists():
            require(json.loads(report_path.read_text(encoding="utf-8-sig")).get("kind") == KIND, "拒绝覆盖其他类型报告")
    except Exception as exc:
        print(json.dumps({"passed": False, "status": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 2
    summary["output"] = report_path.as_posix()
    editor = a.stage("读取真实 editor 外层/内层报告", lambda: runner(a, editor_path, "editor-workshop"))
    geometry = a.stage("读取真实 geometry 外层/内层报告", lambda: runner(a, geometry_path, "workshop-shell"))
    for label, evidence in (("editor", editor), ("geometry", geometry)):
        if evidence:
            summary[label + "_evidence"] = {k: v.as_posix() if isinstance(v, Path) else v
                                            for k, v in evidence.items() if k != "inner"}
    if geometry:
        summary["geometry_statistics"] = a.stage("核对实际 geometry fixtures 与 failure_count", lambda: geometry_report(a, geometry))
    if editor:
        samples = a.stage("核对 editor 两个实际 shell_samples", lambda: editor_report(a, editor))
        if samples:
            summary["shell_samples"] = samples
            for sample in samples:
                row = a.stage("核对候选五件：" + sample["building_id"], lambda s=sample: bundle(a, editor["project"], editor["inner"], s))
                if row:
                    summary["bundles"].append(row)
        a.stage("核验并复制八张真实 PNG 与中文比较图", lambda: visuals(a, editor, output, summary))
    if editor and geometry:
        summary["source_code_hashes"] = a.stage("记录全部相关代码及核对实际隔离副本", lambda: sources(a, [editor["project"], geometry["project"]])) or []
    if args.contract_status:
        def contract_status() -> None:
            path = absolute(args.contract_status)
            recorded = a.obj(path)
            require(recorded.get("passed") is True or recorded.get("passed") is False, "契约状态必须明确 passed 布尔值")
            summary["whole_project_contracts"] = {"requested": True, "path": path.as_posix(), "sha256": a.inputs[path],
                "passed": recorded["passed"], "status": "passed" if recorded["passed"] else "failed", "recorded": recorded,
                "scope": "独立列示的已有全工程结果，不运行、不修复、不用于覆盖专项结论"}
        a.stage("读取可选全工程契约状态", contract_status)
    a.check("完整两候选与八张 PNG 已交付", len(summary["bundles"]) == 2 and len(summary["png_local_copies"]) == 8
            and bool(summary.get("comparison")))
    summary["input_hash_guard"] = a.guard()
    if a.ok():
        summary["candidate_installations"] = a.stage("候选安装白名单预检及可选安装",
            lambda: install(a, summary["bundles"], args.install_candidates)) or []
        if a.ok():
            summary["zip"] = a.stage("生成仅含 JSON/TSCN 的原 ID 五件 ZIP", lambda: package(a, summary["bundles"], output))
    else:
        summary["installation_blocked"] = "必要真实证据/文件校验未通过；不安装、不生成可交付 ZIP"
    summary["input_hash_guard"] = a.guard()
    failed = [row for row in a.checks if row["passed"] is not True]
    passed = not failed and summary["zip"] is not None
    summary.update({"passed": passed, "status": "passed" if passed else "failed", "checks": a.checks,
                    "checks_count": len(a.checks), "failed_count": len(failed), "failed": failed,
                    "passed_definition": "全部必要真实报告与文件/代码/hash/PNG/候选边界检查通过且ZIP成功；全工程契约独立列示；不签美术/土木结构/复杂物理"})
    summary["path_list"] = [report_path.as_posix(), *[row["local_path"] for row in summary["png_local_copies"]],
        *([summary["comparison"]["path"]] if summary.get("comparison") else []),
        *([summary["zip"]["path"]] if summary["zip"] else []),
        *[path for row in summary["bundles"] for path in row["files"]],
        *[path for row in summary["candidate_installations"] if row["status"] != "not_installed" for path in row["files"]]]
    try:
        # 唯一允许刷新的是本脚本同 kind 的汇总报告；候选、PNG、ZIP 均不覆盖差异。
        plain_path(report_path)
        report_path.write_bytes(json_bytes(summary))
    except Exception as exc:
        print(json.dumps({"passed": False, "status": "report_write_failed", "error": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps({key: summary[key] for key in ("passed", "status", "output", "failed_count", "failed", "path_list", "whole_project_contracts")}, ensure_ascii=False, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
