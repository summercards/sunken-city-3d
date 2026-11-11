#!/usr/bin/env python3
"""读取真实架构专项证据并交付五个建筑候选；不运行 Godot、不登记正式资产。"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
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
DEFAULT_OUTPUT = Path("D:/projects/sea-work/building_workshop/architecture_v001/outputs")
KIND = "workshop_architecture_delivery"
GENERATOR = "sea_workshop_continuous_shell_v2"
BUNDLE = (
    "building.recipe.json",
    "catalog_snapshot.json",
    "building.tscn",
    "candidate_manifest.json",
    "ledger.json",
)
PALETTE = "res://assets/textures/shared/sea_cabin_timber_8x8_512.png"
EDITOR_PLUGIN = "res://addons/building_workshop/plugin.cfg"
ARCHITECTURE_KEYS = (
    "architecture_rect_parapet",
    "architecture_l_railing",
    "architecture_t_terrace",
    "architecture_u_mixed",
    "architecture_window_detail",
)
ARCHITECTURE_ID = re.compile(
    r"architecture_(?:rect_parapet|l_railing|t_terrace|u_mixed|window_detail)_[0-9]+_[0-9]+"
)
SOURCE_FILES = (
    "src/workshop/recipe.gd",
    "src/workshop/catalog.gd",
    "src/workshop/generator.gd",
    "src/workshop/mesh_builder.gd",
    "src/workshop/store.gd",
    "src/workshop/shell_geometry.gd",
    "src/workshop/shell_generator.gd",
    "src/workshop/architecture_config.gd",
    "src/workshop/shell_window_geometry.gd",
    "src/workshop/roof_edge_geometry.gd",
    "addons/building_workshop/editor_store.gd",
    "addons/building_workshop/catalog_adapter.gd",
    "data/workshop/catalog_v1.json",
    "data/workshop/standards_v1.json",
    "data/workshop/palette_cells_v1.json",
)
ARCHITECTURE_SOURCE_PATHS = {
    "res://src/workshop/architecture_config.gd",
    "res://src/workshop/shell_window_geometry.gd",
    "res://src/workshop/roof_edge_geometry.gd",
}
KNOWN_LIMITS = [
    "静态开合/封窗和窗沿参数只签署静态生成结果，不等同于游戏内动画。",
    "几何、碰撞和 hash 通过不等于土木安全、受力承载或施工安全。",
    "完整风格未终验；真实 PNG 交由主线程进行美术目检，不由本脚本代签。",
    "楼梯 navigation 未覆盖；若楼梯缺失或破损，仍保持 pending。",
    "本脚本不运行 Godot、不运行全工程契约、不修改 Main、registry、旧资产或公共色板。",
    "候选 ZIP 不包含公共色板；场景继续依赖生产 res:// 公共色板外链。",
    "截图仅复制 artifactlist 中的真实 PNG，不裁剪、不补绘、不使用 AI 图像。",
    "输入 hash guard 只覆盖本次实际读取的文件，不声明并行历史操作未发生。",
]


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


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
    for item in (path, *path.parents):
        if not (item.exists() or item.is_symlink()):
            continue
        info = item.lstat()
        require(
            not stat.S_ISLNK(info.st_mode)
            and not (getattr(info, "st_file_attributes", 0) & 0x400),
            f"拒绝链接/重解析路径：{item}",
        )


def resource(value: str, project: Path) -> Path:
    require(isinstance(value, str) and value.startswith("res://"), f"非法资源路径：{value}")
    suffix = value[6:]
    require(
        bool(suffix)
        and "\\" not in suffix
        and ":" not in suffix
        and all(part not in ("", ".", "..") for part in suffix.split("/")),
        f"不安全资源路径：{value}",
    )
    path = (project / suffix).resolve()
    require(within(path, project.resolve()), f"资源路径逃逸：{value}")
    return path


def stable(value: Any) -> str:
    if isinstance(value, dict):
        return "{" + ",".join(stable(k) + ":" + stable(value[k]) for k in sorted(value)) + "}"
    if isinstance(value, list):
        return "[" + ",".join(stable(v) for v in value) + "]"
    if isinstance(value, float) and value.is_integer() and abs(value) <= 9007199254740991:
        return str(int(value))
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


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
        current = digest(raw)
        require(path not in self.inputs or self.inputs[path] == current, f"输入已变化：{path}")
        self.inputs[path] = current
        self.cache[path] = raw
        return raw

    def obj(self, path: Path) -> dict[str, Any]:
        def reject_constant(value: str) -> None:
            raise ValueError(f"JSON 不允许非有限数值：{value}")

        def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
            result: dict[str, Any] = {}
            for key, value in pairs:
                require(key not in result, f"JSON 重复键：{key}")
                result[key] = value
            return result

        value = json.loads(
            self.read(path).decode("utf-8-sig"),
            parse_constant=reject_constant,
            object_pairs_hook=unique,
        )
        require(isinstance(value, dict), f"JSON 必须是对象：{path}")
        return value

    def match(self, path: Path, expected: Any, label: str) -> None:
        actual = digest(self.read(path))
        self.check(
            label,
            isinstance(expected, str)
            and re.fullmatch(r"[0-9a-f]{64}", expected) is not None
            and expected == actual,
            {"path": path.as_posix(), "expected": expected, "actual": actual},
        )

    def stage(self, name: str, action: Any) -> Any:
        try:
            return action()
        except Exception as exc:
            self.check(name, False, f"{type(exc).__name__}: {exc}")
            return None

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
        return {
            "same": not changed,
            "changed": changed,
            "files": {path.as_posix(): value for path, value in sorted(self.inputs.items())},
        }

    def ok(self) -> bool:
        return bool(self.checks) and all(row["passed"] is True for row in self.checks)


def section(text: str, name: str) -> dict[str, str]:
    match = re.search(r"^\[" + re.escape(name) + r"\]\s*\n(.*?)(?=^\[|\Z)", text, re.M | re.S)
    if not match:
        return {}
    return {
        item.group(1).strip(): item.group(2).strip()
        for item in re.finditer(r"^([^;\s][^=\n]*)=(.*)$", match.group(1), re.M)
    }


def enabled_plugins(text: str) -> list[str]:
    return re.findall(r'"([^"\n]+)"', section(text, "editor_plugins").get("enabled", ""))


def runner(a: Delivery, path: Path, suite: str, editor: bool) -> dict[str, Any]:
    require(path.name == "report.json", "CLI 必须指向外层实际 runner report.json")
    outer = a.obj(path)
    run_dir = absolute(outer["run_dir"])
    require(run_dir == path.parent, "外层 run_dir 与 report 所在目录不一致")
    require(not within(run_dir, ROOT) and not within(ROOT, run_dir), "runner 必须来自工程外独立目录")
    results = outer.get("results")
    require(isinstance(results, dict) and suite in results, f"外层报告缺少 {suite}")
    for name, row in results.items():
        require(isinstance(row, dict), f"runner result 无效：{name}")
        a.check(
            "runner 实际结果：" + name,
            row.get("passed") is True
            and type(row.get("exit_code")) is int
            and row["exit_code"] == 0
            and row.get("unexpected_errors") == []
            and row.get("expected_errors", []) == []
            and row.get("completion_marker") is True
            and row.get("failure_labels", []) == []
            and row.get("failure_markers", []) == [],
            row,
        )
    a.check("runner 顶层 passed", outer.get("passed") is True)
    result = results[suite]
    command = result.get("command")
    require(
        isinstance(command, list)
        and all(isinstance(value, str) for value in command)
        and command.count("--path") == 1,
        "runner command 必须含唯一 --path",
    )
    project = absolute(command[command.index("--path") + 1])
    require(project == (run_dir / "project").resolve() and project.is_dir(), "runner project 身份或目录无效")
    args = command[1:command.index("--")] if "--" in command else command[1:]
    if editor:
        a.check(
            "真实编辑器而非 headless/script",
            "--editor" in args
            and not any(
                value in ("--headless", "--script", "-s") or value.startswith("--script=")
                for value in args
            )
            and "--" in command
            and "--workshop-editor-verify" in command[command.index("--") + 1 :],
            command,
        )
    else:
        a.check(
            "geometry 实际架构专项命令",
            "--headless" in args
            and "--script" in args
            and args[args.index("--script") + 1] == "res://tests/test_workshop_architecture.gd",
            command,
        )
    log_path = absolute(result["log"])
    require(within(log_path, run_dir) and not within(log_path, project), "日志必须属于同一 runner 批次")
    text = a.read(log_path).decode("utf-8-sig")
    tag = "workshop-editor" if editor else "workshop-architecture"
    markers = re.findall(r"\[" + tag + r"\]\s+(\d+)\s+checks,\s+(\d+)\s+failures", text)
    a.check("日志唯一完成标记：" + suite, len(markers) == 1, markers)
    require(len(markers) == 1, "日志缺少唯一实际完成计数")
    count, failures = map(int, markers[0])
    a.check("日志实际零失败：" + suite, count > 0 and failures == 0, {"checks": count, "failures": failures})
    a.check(
        "日志无失败/引擎错误：" + suite,
        re.search(r"^\s*(?:FAIL\b|(?:SCRIPT\s+)?ERROR:|Parse Error:|Invalid (?:call|access))", text, re.M)
        is None,
    )
    inner_name = "workshop_editor_report.json" if editor else "workshop_architecture_report.json"
    inner_path = project / "outputs" / inner_name
    inner = a.obj(inner_path)
    if editor:
        config = a.read(project / "project.godot").decode("utf-8-sig")
        autoload = re.search(r"^\[autoload\]\s*\n(.*?)(?=^\[|\Z)", config, re.M | re.S)
        a.check(
            "编辑器隔离项目 noMain/无 Autoload",
            (autoload is None or not any(line.strip() and not line.lstrip().startswith(";") for line in autoload[1].splitlines()))
            and re.search(r'^run/main_scene\s*=\s*"[^"\n]+"', config, re.M) is None,
            config,
        )
        a.check("编辑器隔离项目只启用工坊插件", enabled_plugins(config) == [EDITOR_PLUGIN])
    return {
        "outer_path": path.as_posix(),
        "inner_path": inner_path.as_posix(),
        "project": project,
        "inner": inner,
        "log_checks": count,
        "log_failures": failures,
        "command": command,
    }


def geometry_report(a: Delivery, evidence: dict[str, Any]) -> dict[str, Any]:
    report = evidence["inner"]
    require(report.get("suite") == "workshop-architecture", "geometry 内层 suite 不一致")
    checks = report.get("checks")
    failures = report.get("failures")
    failure_count = report.get("failure_count")
    require(type(checks) is int and checks > 0 and isinstance(failures, list), "geometry checks/failures 格式无效")
    a.check(
        "geometry 实际计数与日志一致且零失败",
        checks == evidence["log_checks"]
        and failure_count == len(failures) == evidence["log_failures"] == 0,
        {"checks": checks, "failure_count": failure_count, "failures": failures},
    )
    a.check("geometry report failures 为空", failures == [])
    fixtures = report.get("fixtures")
    a.check("geometry fixtures 非空", isinstance(fixtures, dict) and bool(fixtures))
    return {
        "suite": report.get("suite"),
        "checks_count": checks,
        "failure_count": failure_count,
        "failures": failures,
        "fixture_count": len(fixtures) if isinstance(fixtures, dict) else 0,
        "fixtures": fixtures,
        "visual_acceptance": report.get("visual_acceptance"),
    }


def validate_architecture_recipe(a: Delivery, sample: dict[str, Any]) -> None:
    key = sample.get("key")
    recipe = sample.get("recipe")
    require(isinstance(key, str) and key in ARCHITECTURE_KEYS, f"未知架构样例 key：{key}")
    require(isinstance(recipe, dict), f"架构样例 recipe 不是对象：{key}")
    architecture = recipe.get("architecture")
    require(isinstance(architecture, dict), f"架构样例缺少 architecture：{key}")
    required = {"plan", "window", "floor_windows", "facade_windows", "window_overrides", "roof"}
    a.check(key + " architecture 字段完整", required <= set(architecture), sorted(architecture))
    a.check(key + " construction_mode=shell_v2", recipe.get("construction_mode") == "shell_v2")
    expected = {
        "architecture_rect_parapet": ("rectangle", "parapet", "fixed", 0.0),
        "architecture_l_railing": ("l", "railing", "fixed", 0.0),
        "architecture_t_terrace": ("t", "parapet", "casement_right", 35.0),
        "architecture_u_mixed": ("u", "mixed", "awning", 25.0),
        "architecture_window_detail": ("rectangle", "parapet", "casement_left", 45.0),
    }[key]
    window = architecture.get("window", {})
    roof = architecture.get("roof", {})
    plan = architecture.get("plan", {})
    actual = (
        recipe.get("shape"),
        roof.get("mode") if isinstance(roof, dict) else None,
        window.get("type") if isinstance(window, dict) else None,
        float(window.get("open_angle")) if isinstance(window, dict) and isinstance(window.get("open_angle"), (int, float)) else None,
    )
    a.check(key + " 形状/屋顶/窗型与实际样例一致", actual[:3] == expected[:3], actual)
    a.check(key + " open_angle 与实际样例一致", actual[3] == expected[3], actual[3])
    if key == "architecture_t_terrace":
        a.check(key + " setback 退台配置真实存在", isinstance(plan, dict) and plan.get("wing_x") == 0.5 and plan.get("wing_z") == 0.5 and plan.get("setback_start") == 2 and plan.get("setback_step") == 0.45, plan)
    if key == "architecture_u_mixed":
        a.check(key + " U形翼宽与窗台配置真实存在", isinstance(plan, dict) and plan.get("wing_x") == 0.6 and plan.get("wing_z") == 0.55 and isinstance(window, dict) and window.get("sill") == 1.0, {"plan": plan, "window": window})
    a.check(key + " recipe building_id 安全且匹配", isinstance(recipe.get("building_id"), str) and ARCHITECTURE_ID.fullmatch(recipe["building_id"]) is not None)


def editor_report(a: Delivery, evidence: dict[str, Any]) -> list[dict[str, Any]]:
    report = evidence["inner"]
    project = evidence["project"]
    a.check("editor 内层 passed 且 failures 为空", report.get("passed") is True and report.get("failures") == [])
    for key, expected in {
        "enginehint": True,
        "is_playing": False,
        "scene_unchanged": True,
        "root_paused_unchanged": True,
        "game_save_connected": False,
    }.items():
        a.check("editor 状态：" + key, report.get(key) is expected, report.get(key))
    a.check("editor dependencies 为空", report.get("dependencies") == [])
    a.check("editor 内层隔离项目身份", absolute(report["project_path"]) == project)
    checks = report.get("checks")
    require(isinstance(checks, list) and bool(checks), "editor checks 必须是非空数组")
    a.check("editor 日志与 checks 数一致", len(checks) == evidence["log_checks"])
    for index, row in enumerate(checks):
        a.check(
            f"editor check[{index}]",
            isinstance(row, dict) and isinstance(row.get("name"), str) and bool(row["name"]) and row.get("passed") is True,
            row,
        )
    samples = report.get("architecture_samples")
    require(isinstance(samples, list) and len(samples) == 5, "architecture_samples 必须恰为五个")
    keys = [sample.get("key") for sample in samples if isinstance(sample, dict)]
    a.check("五个架构 key 唯一且完整", keys == list(ARCHITECTURE_KEYS), keys)
    all_artifacts = report.get("artifacts")
    require(isinstance(all_artifacts, list) and all(isinstance(value, str) for value in all_artifacts), "editor artifacts 必须是资源路径数组")
    artifacts = {resource(value, project).resolve() for value in all_artifacts}
    for path in sorted(artifacts):
        a.check("报告 artifact 落盘：" + path.as_posix(), path.is_file(), path.as_posix())
        if path.is_file():
            a.read(path)
    a.check("artifacts 包含内层报告", evidence["inner_path"] == (project / "outputs/workshop_editor_report.json").as_posix() or (project / "outputs/workshop_editor_report.json").resolve() in artifacts)
    for sample in samples:
        require(isinstance(sample, dict), "架构 sample entry 必须是对象")
        required_entry = {"key", "building_id", "recipe", "save_result", "artifacts", "geometry_audit"}
        a.check(str(sample.get("key")) + " entry 字段完整", required_entry <= set(sample), sorted(sample))
        validate_architecture_recipe(a, sample)
        require(isinstance(sample.get("building_id"), str) and ARCHITECTURE_ID.fullmatch(sample["building_id"]) is not None, "building_id 不安全")
        require(isinstance(sample.get("artifacts"), list) and all(isinstance(v, str) for v in sample["artifacts"]), "样例 artifacts 无效")
        sample_paths = {resource(value, project).resolve() for value in sample["artifacts"]}
        a.check(str(sample["key"]) + " artifacts 属于总 artifactlist", sample_paths <= artifacts)
        require(isinstance(sample.get("save_result"), dict), "save_result 必须是实际返回对象")
        a.check(str(sample["key"]) + " save_result ok", sample["save_result"].get("ok") is True)
        require(isinstance(sample.get("geometry_audit"), dict) and bool(sample["geometry_audit"]), "geometry_audit 必须为真实非空对象")
    return samples


def save_bundle(a: Delivery, project: Path, sample: dict[str, Any], all_artifacts: set[Path]) -> dict[str, Any]:
    building_id = sample["building_id"]
    save_result = sample["save_result"]
    fields = {
        "directory": "directory",
        "building.recipe.json": "recipe_path",
        "catalog_snapshot.json": "catalog_path",
        "building.tscn": "scene_path",
        "candidate_manifest.json": "manifest_path",
        "ledger.json": "ledger_path",
    }
    paths: dict[str, Path] = {}
    for filename, field in fields.items():
        value = save_result.get(field)
        require(isinstance(value, str) and bool(value), f"{building_id} save_result 缺少实际字段 {field}")
        paths[filename] = resource(value, project).resolve()
    directory = paths["directory"]
    require(directory.is_dir() and within(directory, project / "outputs/workshop_editor"), f"{building_id} 输出目录不在隔离输出根")
    require(all(path.parent == directory and path.name == name for name, path in paths.items() if name != "directory"), f"{building_id} save_result 文件路径不一致")
    for name, path in paths.items():
        if name == "directory":
            continue
        a.check(f"{building_id} 五件来自真实 artifacts：{name}", path in all_artifacts)
        require(path.is_file(), f"{building_id} 缺少 {name}")
        a.read(path)
    recipe = a.obj(paths["building.recipe.json"])
    catalog = a.obj(paths["catalog_snapshot.json"])
    manifest = a.obj(paths["candidate_manifest.json"])
    ledger = a.obj(paths["ledger.json"])
    a.check(
        building_id + " 原始身份",
        all(value.get("building_id") == building_id and type(value.get("revision")) is int and value["revision"] == 1 for value in (recipe, manifest, ledger)),
    )
    a.check(building_id + " recipe 与内层 entry 一致", recipe == sample["recipe"] and recipe.get("construction_mode") == "shell_v2")
    a.check(building_id + " manifest 精确五件清单", sorted(manifest.get("file_list", [])) == sorted(BUNDLE))
    a.check(
        building_id + " manifest/ledger 候选边界",
        manifest.get("generator") == GENERATOR
        and manifest.get("construction_mode") == "shell_v2"
        and manifest.get("authoring_context") == "editor"
        and manifest.get("noMain") is True
        and manifest.get("formal_registry_written") is False
        and manifest.get("static_scene") is True
        and manifest.get("has_workshop_rebuild_script") is False
        and manifest.get("preview_camera_lights_packed") is False
        and ledger.get("status") == "candidate_only"
        and manifest.get("candidate_ledger_status") == "exported_pending_project_registration"
        and ledger.get("candidate_ledger_status") == "exported_pending_project_registration",
        {"manifest": manifest, "ledger": ledger},
    )
    source_hashes = manifest.get("source_hashes")
    require(isinstance(source_hashes, dict) and set(source_hashes) == set(BUNDLE[:3]), f"{building_id} source_hashes 不完整")
    for name, expected in source_hashes.items():
        a.match(paths[name], expected, building_id + " manifest file hash：" + name)
    a.match(paths["building.tscn"], manifest.get("hash"), building_id + " 场景 file hash")
    a.check(
        building_id + " catalog snapshot fingerprint",
        bool(catalog.get("catalog_id"))
        and recipe.get("catalog_id") == catalog.get("catalog_id") == manifest.get("catalog_id")
        and digest(stable(catalog).encode("utf-8")) == manifest.get("catalog_fingerprint"),
    )
    authoring = manifest.get("authoring_source_hashes")
    require(isinstance(authoring, dict) and authoring, f"{building_id} authoring_source_hashes 不能为空")
    for source in ARCHITECTURE_SOURCE_PATHS:
        expected = authoring.get(source)
        source_path = resource(source, project)
        raw = a.read(source_path)
        a.check(building_id + " 架构来源非空：" + source, bool(raw) and isinstance(expected, str) and bool(expected))
        a.match(source_path, expected, building_id + " 架构来源 hash：" + source)
    for source, expected in authoring.items():
        source_path = resource(source, project)
        a.match(source_path, expected, building_id + " authoring source hash：" + source)
    tscn = a.cache[paths["building.tscn"]]
    text = tscn.decode("utf-8-sig")
    node_types = re.findall(r'^\[node\b[^\n]*\btype\s*=\s*"([^"]+)"', text, re.M)
    a.check(building_id + " TSCN 静态节点白名单", bool(node_types) and set(node_types) <= {"Node3D", "MeshInstance3D", "StaticBody3D", "CollisionShape3D"})
    a.check(building_id + " TSCN 无 Script/嵌套场景", re.search(r'\btype\s*=\s*"[^"]*(?:Script|PackedScene)"|^\s*script\s*=|\.(?:gd|cs|gdextension)"|\binstance\s*=', text, re.M | re.I) is None)
    a.check(building_id + " TSCN generator/mode metadata", f'metadata/generator_version = "{GENERATOR}"' in text and 'metadata/construction_mode = "shell_v2"' in text)
    dependencies = []
    for declaration in re.findall(r'^\[ext_resource\b[^\n]*\]', text, re.M):
        path_match = re.search(r'\bpath\s*=\s*"([^"]+)"', declaration)
        type_match = re.search(r'\btype\s*=\s*"([^"]+)"', declaration)
        require(path_match is not None and type_match is not None, f"{building_id} TSCN 外部依赖声明不完整")
        value = path_match[1]
        a.check(building_id + " 仅依赖公共色板外链", value == PALETTE and type_match[1] == "Texture2D", declaration)
        isolated = resource(value, project)
        production = resource(value, GODOT)
        a.check(building_id + " 公共色板生产/隔离一致且不打包", a.read(isolated) == a.read(production))
        dependencies.append({"resource": value, "production_path": production.as_posix(), "sha256": a.inputs[production.resolve()], "packaged": False})
    require(dependencies, f"{building_id} TSCN 缺少公共色板外链")
    return {
        "building_id": building_id,
        "revision": 1,
        "source_directory": directory.as_posix(),
        "hashes": {name: digest(a.cache[path]) for name, path in paths.items() if name != "directory"},
        "files": [paths[name].as_posix() for name in BUNDLE],
        "dependencies": dependencies,
        "manifest_source_hashes": source_hashes,
        "catalog_fingerprint": manifest.get("catalog_fingerprint"),
        "formal_registration": "pending",
    }


def read_png(a: Delivery, path: Path, expected_size: tuple[int, int]):
    from PIL import Image

    raw = a.read(path)
    require(len(raw) >= 33 and raw[:8] == b"\x89PNG\r\n\x1a\n" and raw[12:16] == b"IHDR", f"不是真实 PNG：{path}")
    dimensions = struct.unpack(">II", raw[16:24])
    require(dimensions == expected_size, f"PNG 尺寸错误：{path}，{dimensions}，预期 {expected_size}")
    with Image.open(io.BytesIO(raw)) as image:
        require(image.format == "PNG" and image.size == dimensions, "PNG 解码格式或尺寸不一致")
        image.verify()
    with Image.open(io.BytesIO(raw)) as image:
        image.load()
        return image.convert("RGB"), {"source": path.as_posix(), "sha256": digest(raw), "width": dimensions[0], "height": dimensions[1], "art_accepted": False}


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
    from PIL import Image, ImageDraw, ImageFont

    project = evidence["project"]
    labels = {
        "architecture_rect_parapet": "rect女儿墙",
        "architecture_l_railing": "L栏杆",
        "architecture_t_terrace": "T退台",
        "architecture_u_mixed": "U混合",
        "architecture_window_detail": "平开窗细节",
    }
    images: dict[str, Image.Image] = {}
    pending: list[tuple[Path, Path, dict[str, Any]]] = []
    copied_names: set[str] = set()
    for sample in summary["architecture_samples"]:
        candidates = [resource(value, project).resolve() for value in sample["artifacts"] if str(value).lower().endswith(".png")]
        require(len(candidates) == 2, f"{sample['key']} 必须从 artifactlist 得到两张 PNG")
        model_path = editor_path = None
        for path in candidates:
            raw = a.read(path)
            dimensions = struct.unpack(">II", raw[16:24]) if len(raw) >= 24 and raw[:8] == b"\x89PNG\r\n\x1a\n" and raw[12:16] == b"IHDR" else None
            if dimensions == (1400, 1100):
                require(model_path is None, f"{sample['key']} 有多张模型图")
                model_path = path
            elif dimensions == (1600, 1000):
                require(editor_path is None, f"{sample['key']} 有多张编辑器图")
                editor_path = path
            else:
                raise ValueError(f"{sample['key']} PNG 必须为 1400x1100 或 1600x1000：{path}")
        require(model_path is not None and editor_path is not None, f"{sample['key']} 缺少模型图或编辑器图")
        model_image, model_row = read_png(a, model_path, (1400, 1100))
        editor_image, editor_row = read_png(a, editor_path, (1600, 1000))
        model_name = model_path.name
        editor_name = editor_path.name
        require(model_name not in copied_names and editor_name not in copied_names, "不同样例 PNG basename 冲突")
        copied_names.update((model_name, editor_name))
        model_target = output / model_name
        editor_target = output / editor_name
        model_row.update({"local_path": model_target.as_posix(), "copy_status": new_file(model_target, a.cache[model_path])})
        editor_row.update({"local_path": editor_target.as_posix(), "copy_status": new_file(editor_target, a.cache[editor_path])})
        summary["png_local_copies"].extend((model_row, editor_row))
        images[sample["key"]] = model_image
        pending.append((model_path, model_target, model_row))
        pending.append((editor_path, editor_target, editor_row))
    font_path = next((path for path in (Path("C:/Windows/Fonts/msyh.ttc"), Path("C:/Windows/Fonts/msyhbd.ttc")) if path.is_file()), None)
    require(font_path is not None, "找不到实际存在的 Microsoft YaHei 字体")
    a.read(font_path)
    title_font = ImageFont.truetype(str(font_path), 30)
    note_font = ImageFont.truetype(str(font_path), 18)
    canvas = Image.new("RGB", (1500, 1100), "#edf0f3")
    draw = ImageDraw.Draw(canvas)
    cell_w, cell_h = 480, 480
    for index, key in enumerate(ARCHITECTURE_KEYS):
        row, column = divmod(index, 3)
        left = 20 + column * 495
        top = 20 + row * 525
        draw.text((left, top), labels[key], font=title_font, fill="#263348")
        image = images[key].copy()
        image.thumbnail((cell_w, cell_h - 55), Image.Resampling.LANCZOS)
        box_left = left + (cell_w - image.width) // 2
        box_top = top + 52 + (cell_h - 55 - image.height) // 2
        canvas.paste(image, (box_left, box_top))
    draw.text((20, 1060), "五个真实模型渲染等比缩放；仅作目检联络图，不代签 UI clearance 或专业美术终验。", font=note_font, fill="#445064")
    stream = io.BytesIO()
    canvas.save(stream, format="PNG")
    contact_path = output / "variants_contact_sheet.png"
    new_file(contact_path, stream.getvalue())
    summary["contact_sheet"] = {"path": contact_path.as_posix(), "sha256": digest(stream.getvalue()), "width": 1500, "height": 1100, "font": font_path.as_posix(), "grid": "3列2行", "art_accepted": False}


def install(a: Delivery, bundles: list[dict[str, Any]], requested: bool) -> list[dict[str, Any]]:
    parent = GODOT / "scenes"
    require(parent.is_dir(), f"必须先确认 ROOT/godot/scenes 父目录已存在：{parent}")
    plain_path(parent)
    candidate_root = parent / "workshop_buildings"
    plans = []
    for row in bundles:
        building_id = row["building_id"]
        require(re.fullmatch(r"[A-Za-z0-9_-]+", building_id) is not None, f"候选 ID 不安全：{building_id}")
        target = candidate_root / building_id / "revision_0001"
        plain_path(target)
        if target.exists():
            require(target.is_dir() and {item.name for item in target.iterdir()} == set(BUNDLE), f"候选目录不是精确五件：{target}")
            for name in BUNDLE:
                path = target / name
                require(path.is_file() and digest(path.read_bytes()) == row["hashes"][name], f"已有候选存在差异，拒绝覆盖：{path}")
            status = "identical"
        elif target.parent.exists():
            require(target.parent.is_dir() and not any(target.parent.iterdir()), f"拒绝向已有不同内容目录追加：{target.parent}")
            status = "not_installed"
        else:
            status = "not_installed"
        plans.append({"building_id": building_id, "directory": target.as_posix(), "files": [(target / name).as_posix() for name in BUNDLE], "status": status, "formal_registration": "pending"})
    if not requested:
        return plans
    require(a.ok(), "安装前必要校验未通过")
    for row, plan in zip(bundles, plans):
        target = Path(plan["directory"])
        if target.exists():
            continue
        for directory in (candidate_root, target.parent, target):
            plain_path(directory)
            require(directory.parent.is_dir(), f"创建前父目录不存在：{directory.parent}")
            if not directory.exists():
                directory.mkdir()
            require(directory.is_dir(), f"不是目录：{directory}")
        for name in BUNDLE:
            source = Path(row["source_directory"]) / name
            new_file(target / name, a.cache[source.resolve()])
            require(digest((target / name).read_bytes()) == row["hashes"][name], f"安装后 hash 不匹配：{target / name}")
        plan["status"] = "installed_candidate_only"
    return plans


def package(a: Delivery, bundles: list[dict[str, Any]], output: Path, summary: dict[str, Any]) -> dict[str, Any]:
    members: dict[str, bytes] = {}
    for row in bundles:
        for name in BUNDLE:
            members[f"{row['building_id']}/revision_0001/{name}"] = a.cache[(Path(row["source_directory"]) / name).resolve()]
    candidate_report = {
        "kind": KIND + "_candidates",
        "schema_version": 1,
        "candidate_validation_passed": True,
        "formal_registration": "pending",
        "bundles": bundles,
        "artifact_paths": summary.get("artifact_paths", {}),
        "known_limits": KNOWN_LIMITS,
        "public_palette_packaged": False,
        "note": "仅包含五个候选目录的五件文件和本报告；不包含公共色板，不写 ZIP 自身 hash，避免自引用。",
    }
    members["architecture_candidates_report.json"] = json_bytes(candidate_report)
    require(all(Path(name).suffix in (".json", ".tscn") for name in members), "ZIP 只能包含 JSON/TSCN")
    require(not any(Path(name).suffix.lower() in (".md", ".readme") for name in members), "ZIP 禁止 README/md")
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, raw in sorted(members.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, raw)
    raw = stream.getvalue()
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        require(archive.testzip() is None and set(archive.namelist()) == set(members), "ZIP 完整性验证失败")
        require(all(archive.read(name) == content for name, content in members.items()), "ZIP 内容变化")
    target = output / "architecture_candidates.zip"
    state = new_file(target, raw)
    return {"path": target.as_posix(), "sha256": digest(raw), "status": state, "members": [{"path": name, "sha256": digest(content)} for name, content in sorted(members.items())], "bundle_count": len(bundles), "files_per_bundle": len(BUNDLE), "public_palette_packaged": False, "self_hash_included": False}


def contract_status(a: Delivery, path: Path, summary: dict[str, Any]) -> None:
    recorded = a.obj(path)
    require(recorded.get("passed") is True or recorded.get("passed") is False, "契约状态必须明确 passed 布尔值")
    summary["whole_project_contracts"] = {"requested": True, "path": path.as_posix(), "sha256": a.inputs[path.resolve()], "passed": recorded["passed"], "status": "passed" if recorded["passed"] else "failed", "recorded": recorded, "scope": "独立列示已有全工程结果，不运行、不修复、不覆盖架构专项结论"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-report", required=True, type=Path, help="真实 editor 外层 runner report.json")
    parser.add_argument("--geometry-report", required=True, type=Path, help="真实 architecture geometry 外层 runner report.json")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT, help="工程外交付输出目录")
    parser.add_argument("--install-candidates", action="store_true", help="全部校验通过后安装五个新候选，不正式登记")
    parser.add_argument("--contracts-status", "--contract-status", dest="contracts_status", type=Path, help="可选，只读已有全工程契约状态 JSON")
    args = parser.parse_args()
    a = Delivery()
    summary: dict[str, Any] = {
        "kind": KIND,
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "passed": False,
        "status": "failed",
        "engine_executed": False,
        "formal_registration": "pending",
        "known_limits": KNOWN_LIMITS,
        "architecture_samples": [],
        "bundles": [],
        "png_local_copies": [],
        "artifact_paths": {},
        "source_hashes": {},
        "candidate_installations": [],
        "install_requested": args.install_candidates,
        "zip": None,
        "whole_project_contracts": {"requested": bool(args.contracts_status), "status": "not_provided", "passed": None},
    }
    try:
        output = absolute(args.output_root)
        editor_path = absolute(args.editor_report)
        geometry_path = absolute(args.geometry_report)
        require(editor_path != geometry_path, "两个 CLI 输入必须为不同外层 runner report")
        require(not within(output, ROOT) and not within(ROOT, output), "output-root 必须位于正式工程外")
        for path in (editor_path, geometry_path, *([absolute(args.contracts_status)] if args.contracts_status else [])):
            require(not within(path, output), "输出目录不能包含输入报告")
        for path in (editor_path, geometry_path):
            require(not within(output, path.parent) and not within(path.parent, output), "输出目录不能与 runner 证据目录重叠")
        plain_path(output)
        require(output.parent.is_dir(), "output-root 的父目录必须已存在")
        if not output.exists():
            output.mkdir()
        require(output.is_dir(), "output-root 必须是目录")
        report_path = output / "architecture_delivery_report.json"
        plain_path(report_path)
        if report_path.exists():
            previous = json.loads(report_path.read_text(encoding="utf-8-sig"))
            require(isinstance(previous, dict) and previous.get("kind") == KIND, "拒绝覆盖其他类型交付报告")
    except Exception as exc:
        print(json.dumps({"passed": False, "status": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 2
    summary["output"] = report_path.as_posix()
    editor = a.stage("读取真实 editor 外层/内层报告", lambda: runner(a, editor_path, "editor-workshop", True))
    geometry = a.stage("读取真实 architecture geometry 外层/内层报告", lambda: runner(a, geometry_path, "workshop-architecture", False))
    for label, evidence in (("editor", editor), ("geometry", geometry)):
        if evidence:
            summary[label + "_evidence"] = {key: value.as_posix() if isinstance(value, Path) else value for key, value in evidence.items() if key != "inner"}
    if geometry:
        summary["geometry_statistics"] = a.stage("核对实际 workshop-architecture report 与日志 marker", lambda: geometry_report(a, geometry))
    if editor:
        samples = a.stage("核对五个实际 architecture_samples", lambda: editor_report(a, editor))
        if samples:
            summary["architecture_samples"] = samples
            all_artifacts = {resource(value, editor["project"]).resolve() for value in editor["inner"].get("artifacts", [])}
            for sample in samples:
                row = a.stage("核对架构候选五件：" + sample["building_id"], lambda s=sample: save_bundle(a, editor["project"], s, all_artifacts))
                if row:
                    summary["bundles"].append(row)
            summary["artifact_paths"] = {sample["key"]: list(sample.get("artifacts", [])) for sample in samples}
            summary["source_hashes"] = {path: digest((GODOT / path).read_bytes()) for path in SOURCE_FILES if (GODOT / path).is_file()}
            a.check("五个候选均记录实际 source hashes", len(summary["source_hashes"]) == len(SOURCE_FILES))
            a.stage("核验并复制十张真实 PNG，生成五图联络图", lambda: visuals(a, editor, output, summary))
    if args.contracts_status:
        path = absolute(args.contracts_status)
        a.stage("读取可选全工程契约状态", lambda: contract_status(a, path, summary))
    a.check("五个架构候选、十张 PNG、联络图完整", len(summary["bundles"]) == 5 and len(summary["png_local_copies"]) == 10 and bool(summary.get("contact_sheet")))
    summary["input_hash_guard"] = a.guard()
    if a.ok():
        summary["zip"] = a.stage("生成五个候选目录 ZIP", lambda: package(a, summary["bundles"], output, summary))
        if a.ok() and summary["zip"]:
            summary["candidate_installations"] = a.stage("候选安装白名单预检及可选安装", lambda: install(a, summary["bundles"], args.install_candidates)) or []
    else:
        summary["installation_blocked"] = "真实报告、文件、hash 或 PNG 校验未通过；不安装、不生成 ZIP"
    summary["input_hash_guard"] = a.guard()
    failed = [row for row in a.checks if row["passed"] is not True]
    passed = not failed and summary["zip"] is not None
    summary["counts"] = {
        "editor_checks_actual": editor.get("log_checks") if editor else None,
        "geometry_checks_actual": geometry.get("log_checks") if geometry else None,
        "geometry_failures_actual": geometry.get("log_failures") if geometry else None,
        "architecture_samples": len(summary["architecture_samples"]),
        "bundles": len(summary["bundles"]),
        "model_pngs": sum(1 for row in summary["png_local_copies"] if row.get("width") == 1400 and row.get("height") == 1100),
        "editor_pngs": sum(1 for row in summary["png_local_copies"] if row.get("width") == 1600 and row.get("height") == 1000),
        "source_files": len(summary["source_hashes"]),
    }
    summary.update({"passed": passed, "status": "passed" if passed else "failed", "checks": a.checks, "checks_count": len(a.checks), "failed_count": len(failed), "failed": failed, "passed_definition": "五个真实架构样例、实际保存五件、实际 geometry/editor 完成标记、PNG/hash/外链候选边界和 ZIP 全部通过；美术/土木/导航仅列限制"})
    summary["path_list"] = [report_path.as_posix(), *[row["local_path"] for row in summary["png_local_copies"]], *([summary["contact_sheet"]["path"]] if summary.get("contact_sheet") else []), *([summary["zip"]["path"]] if summary.get("zip") else []), *[path for row in summary["bundles"] for path in row["files"]], *[path for row in summary["candidate_installations"] if row["status"] != "not_installed" for path in row["files"]]]
    try:
        plain_path(report_path)
        report_path.write_bytes(json_bytes(summary))
    except Exception as exc:
        print(json.dumps({"passed": False, "status": "report_write_failed", "error": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps({key: summary[key] for key in ("passed", "status", "output", "counts", "failed_count", "failed", "path_list", "whole_project_contracts")}, ensure_ascii=False, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
