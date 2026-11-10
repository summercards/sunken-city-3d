#!/usr/bin/env python3
"""只读审计真实编辑器房屋工坊交付；不运行 Godot、不登记、不刷新输入。"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
GODOT = (ROOT / "godot").resolve()
DEFAULT_OUTPUT = Path("D:/projects/sea-work/building_workshop/editor_v001/delivery_report.json")
PLUGIN = "res://addons/building_workshop/plugin.cfg"
CORE = ("recipe", "catalog", "generator", "mesh_builder", "session", "store")
BUNDLE = ("building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json")
SAMPLE_IDS = ("SEA-SCENE-WORKSHOP-SAMPLE-001", "SEA-SCENE-WORKSHOP-SAMPLE-002")
KIND = "workshop_editor_delivery_audit"
KNOWN_LIMITS = [
    "没有签署楼梯、正式导航或全楼通行能力；walk/water 仅为局部声明。",
    "复杂根系贴墙及墙面刷苔未签署。",
    "完整 SF/项目 Skill 风格、完整 Blender/GLB/02b 链及用户美术终验未签署。",
    "PNG 和真实布局断言只作编辑器证据，不以非空截图签署美术验收。",
    "只按真实报告签收隐藏/恢复；完整插件卸载重载、跨进程恢复及持续性能未签署。",
    "只证明本次审计读取前后输入 hash 不变，不证明主场景在历史或并行工作中从未修改。",
    "已有 profile/static/owner 测试只检查源码存在；本脚本不执行引擎或重跑这些测试。",
]


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def absolute(value: str | Path) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        raise ValueError(f"必须指定完整绝对路径：{value}")
    return path.resolve()


def under(path: Path, parent: Path) -> bool:
    return path == parent or path.is_relative_to(parent)


class Audit:
    def __init__(self) -> None:
        self.checks: list[dict[str, Any]] = []
        self.inputs: dict[Path, str] = {}
        self.editor_project: Path = GODOT
        self.inspected_scenes: set[Path] = set()

    def check(self, name: str, passed: bool, detail: Any = "") -> bool:
        self.checks.append({"name": name, "passed": passed is True, "detail": detail})
        return passed is True

    def read(self, path: Path) -> bytes:
        path = path.resolve()
        raw = path.read_bytes()
        current = sha(raw)
        if path in self.inputs and self.inputs[path] != current:
            raise ValueError(f"审计期间输入发生变化：{path.as_posix()}")
        self.inputs.setdefault(path, current)
        return raw

    def text(self, path: Path) -> str:
        return self.read(path).decode("utf-8-sig")

    def obj(self, path: Path) -> dict[str, Any]:
        value = json.loads(self.text(path))
        if not isinstance(value, dict):
            raise ValueError(f"JSON 必须是对象：{path.as_posix()}")
        return value

    def file(self, path: Path, name: str) -> bool:
        return self.check(name, path.is_file(), path.as_posix())

    def match(self, path: Path, expected: Any, label: str, normalize: bool = False) -> dict[str, Any]:
        raw = self.read(path)
        actual = sha(raw)
        mode = "raw" if expected == actual else "mismatch"
        normalized = sha(raw.replace(b"\r\n", b"\n")) if normalize else None
        if mode == "mismatch" and normalize and expected == normalized:
            mode = "crlf_to_lf"
        self.check(label, isinstance(expected, str) and bool(re.fullmatch(r"[0-9a-f]{64}", expected)) and mode != "mismatch",
                   {"path": path.as_posix(), "expected": expected, "actual": actual, "match_mode": mode})
        return {"path": path.as_posix(), "sha256": actual, "sha256_lf": normalized, "match_mode": mode}

    def finish_inputs(self) -> dict[str, Any]:
        changed = []
        for path, before in list(self.inputs.items()):
            try:
                after = sha(path.read_bytes())
            except OSError:
                after = None
            if before != after:
                changed.append({"path": path.as_posix(), "before": before, "after": after})
        self.check("本次审计读取前后输入 SHA256 一致", not changed, changed)
        return {"scope": "本脚本读取的输入，从首次读取至报告生成前；不是历史主场景未改声明", "same": not changed,
                "files_count": len(self.inputs), "changed": changed,
                "before_sha256": {p.as_posix(): h for p, h in sorted(self.inputs.items())}}


def resource(value: str, project: Path) -> Path:
    if not isinstance(value, str) or not value.startswith("res://"):
        raise ValueError(f"资源必须为 res:// 路径：{value}")
    suffix = value[6:]
    if not suffix or "\\" in suffix or ":" in suffix or ".." in Path(suffix).parts:
        raise ValueError(f"不安全的资源路径：{value}")
    path = (project / suffix).resolve()
    if not under(path, project):
        raise ValueError(f"资源逃逸项目目录：{value}")
    return path


def repo_path(value: Any) -> Path:
    if not isinstance(value, str) or not value or Path(value).is_absolute() or ":" in value or "\\" in value:
        raise ValueError(f"账本路由必须是工程内相对路径：{value}")
    path = (ROOT / value).resolve()
    if not under(path, ROOT):
        raise ValueError(f"账本路由逃逸工程：{value}")
    return path


def section(text: str, name: str) -> dict[str, str]:
    match = re.search(r"^\[" + re.escape(name) + r"\]\s*\n(.*?)(?=^\[|\Z)", text, re.M | re.S)
    if not match:
        return {}
    return {m.group(1).strip(): m.group(2).strip() for m in
            re.finditer(r"^([^;\s][^=\n]*)=(.*)$", match.group(1), re.M)}


def plugins(text: str) -> list[str]:
    return re.findall(r'"([^"\n]+)"', section(text, "editor_plugins").get("enabled", ""))


def audit_sources(a: Audit, project: Path) -> list[dict[str, Any]]:
    addon = GODOT / "addons/building_workshop"
    data = GODOT / "data/workshop"
    paths = sorted(set(addon.rglob("*.gd")) | set(addon.rglob("*.cfg")) |
                   {GODOT / "src/workshop" / (name + ".gd") for name in CORE} | set(data.rglob("*.json")))
    a.check("插件脚本及配置存在", bool(list(addon.glob("*.gd"))) and (addon / "plugin.cfg").is_file())
    a.check("工坊 data JSON 存在", all((data / name).is_file() for name in
                                           ("catalog_v1.json", "standards_v1.json", "palette_cells_v1.json")))
    result = []
    for path in paths:
        if not a.file(path, "本轮源存在：" + path.relative_to(GODOT).as_posix()):
            continue
        raw = a.read(path)
        rel = path.relative_to(GODOT)
        copied = (project / rel).resolve()
        if not under(copied, project):
            raise ValueError(f"隔离源路径逃逸：{copied}")
        item = {"path": path.as_posix(), "resource_path": "res://" + rel.as_posix(), "sha256": sha(raw),
                "sha256_lf": sha(raw.replace(b"\r\n", b"\n")), "editor_copy": copied.as_posix()}
        if a.file(copied, "真实隔离副本源存在：" + rel.as_posix()):
            copied_raw = a.read(copied)
            a.check("隔离副本与本轮源码一致：" + rel.as_posix(),
                    raw.replace(b"\r\n", b"\n") == copied_raw.replace(b"\r\n", b"\n"),
                    {"production_sha256": sha(raw), "copy_sha256": sha(copied_raw), "comparison": "CRLF 转 LF"})
            item["editor_copy_sha256"] = sha(copied_raw)
        if path.suffix == ".json":
            a.obj(path)
        if rel.as_posix() in {"src/workshop/" + name + ".gd" for name in CORE}:
            a.check("共享内核支持编辑期 @tool：" + rel.as_posix(),
                    re.search(r"^\s*@tool\s*$", raw.decode("utf-8-sig"), re.M) is not None)
        result.append(item)
    return result


def audit_retained(a: Audit) -> dict[str, Any]:
    config_path = GODOT / "project.godot"
    enabled = plugins(a.text(config_path))
    required = ["res://addons/" + name + "/plugin.cfg" for name in
                ("material_guard", "proton_scatter", "terrain_3d", "building_workshop")]
    a.check("生产 enabled 保留原三插件并包含第四工坊插件", all(p in enabled for p in required)
            and len(enabled) == len(set(enabled)), enabled)
    for value in required:
        a.file(resource(value, GODOT), "生产插件配置保留：" + value)
    paths = [GODOT / "src/workshop" / (name + ".gd") for name in ("panel", "host", "preview")]
    paths += [GODOT / "src/bootstrap/main.gd", GODOT / "src/ui/island_menu.gd", GODOT / "scenes/tools/building_workshop.tscn"]
    texts = {}
    for path in paths:
        if a.file(path, "runtime 入口保留：" + path.relative_to(GODOT).as_posix()):
            texts[path.name] = a.text(path)
    a.check("Main 保留菜单命令与 Host 接线", all(token in texts.get("main.gd", "") for token in
                                                    ('"building_workshop"', "workshop_host.open()", "WorkshopHostScript", "_setup_workshop()")))
    a.check("游戏菜单保留工坊命令", 'button("building_workshop"' in texts.get("island_menu.gd", ""))
    a.check("游戏内版独立 scene 入口仍存在", 'res://src/workshop/panel.gd' in texts.get("building_workshop.tscn", "")
            and re.search(r"^standalone\s*=\s*true\s*$", texts.get("building_workshop.tscn", ""), re.M) is not None)
    rules = GODOT / "tests/test_workshop_rules.gd"
    deep = GODOT / "tests/test_workshop_deep.gd"
    rule_text, deep_text = a.text(rules), a.text(deep)
    for label, exists in (
        ("profile 测试源码存在（未执行）", 'spatial_profile="scenic_underwater"' in rule_text
         and "scenic has no space responsibilities" in rule_text and "above water collision" in rule_text),
        ("static 测试源码存在（未执行）", "static scene independently loads" in rule_text and "baked root no rebuild script" in rule_text),
        ("owner 测试源码存在（未执行）", "node.owner == metadata_root" in deep_text and "node.get_script() == null" in deep_text),
    ):
        a.check(label, exists)
    return {"enabled": enabled, "runtime_paths": [p.as_posix() for p in paths],
            "tests": [{"path": p.as_posix(), "sha256": a.inputs[p.resolve()], "executed": False} for p in (rules, deep)]}


def no_script(a: Audit, path: Path) -> None:
    path = path.resolve()
    if path in a.inspected_scenes:
        return
    a.inspected_scenes.add(path)
    text = a.text(path)
    unsafe = re.search(r'\btype\s*=\s*"(?:[^"]*Script)"|^\s*script\s*=|path\s*=\s*"[^"\n]*\.(?:gd|cs|gdextension)"', text, re.M | re.I)
    a.check("TSCN 无 Script 声明：" + path.as_posix(), unsafe is None,
            unsafe.group(0) if unsafe else "文本静态审计；真实递归资源及 owner 以 editor checks 为准")
    for dependency in re.findall(r'\[ext_resource\b[^\]]*\bpath="([^"]+)"', text):
        target = resource(dependency, path_project(a, path))
        if a.file(target, "TSCN 依赖存在：" + dependency):
            a.read(target)
            if target.suffix == ".tscn":
                no_script(a, target)


def path_project(a: Audit, path: Path) -> Path:
    # TSCN 只允许属于正式 Godot 或已审核的隔离项目。
    project = a.editor_project
    if under(path, project):
        return project
    if under(path, GODOT):
        return GODOT
    raise ValueError(f"TSCN 不属于允许项目：{path}")


def catalog_dependencies(a: Audit, catalog: dict[str, Any], project: Path, label: str) -> None:
    components = catalog.get("components")
    a.check(label + " catalog components 非空", isinstance(components, dict) and bool(components))
    if isinstance(components, dict):
        for component_id, definition in components.items():
            if isinstance(definition, dict) and definition.get("kind") == "prefab":
                prefab = resource(definition.get("prefab"), project)
                version = definition.get("version", "")
                a.check(label + " prefab 版本记录 SHA256：" + component_id,
                        isinstance(version, str) and version.startswith("sha256:"))
                a.match(prefab, version[7:] if isinstance(version, str) else None,
                        label + " prefab 目录绑定 hash：" + component_id)
    def visit(value: Any) -> None:
        if isinstance(value, dict):
            for entry in value.values():
                visit(entry)
        elif isinstance(value, list):
            for entry in value:
                visit(entry)
        elif isinstance(value, str) and value.startswith("res://"):
            dependency = resource(value, project)
            if a.file(dependency, label + " catalog 依赖存在：" + value):
                a.read(dependency)
                if dependency.suffix == ".tscn":
                    no_script(a, dependency)
    visit(catalog)


def audit_bundles(a: Audit, editor: dict[str, Any], project: Path, artifacts: set[Path]) -> list[dict[str, Any]]:
    buildids = editor.get("buildids")
    a.check("编辑器报告包含唯一 building IDs", isinstance(buildids, list) and bool(buildids)
            and all(isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9_-]+", v) for v in buildids)
            and len(buildids) == len(set(buildids)))
    if not isinstance(buildids, list) or not buildids:
        return []
    result = []
    for building_id in buildids:
        if not isinstance(building_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", building_id):
            raise ValueError("非法 building ID")
        versions = []
        for revision in (1, 2):
            directory = resource(f"res://outputs/workshop_editor/{building_id}/revision_{revision:04d}", project)
            files = {name: (directory / name).resolve() for name in BUNDLE}
            hashes = {}
            for name, path in files.items():
                if not under(path, directory):
                    raise ValueError(f"bundle 路径逃逸：{path}")
                a.check("五件均来自真实 artifacts：" + path.as_posix(), path in artifacts)
                if a.file(path, "五件落盘：" + path.as_posix()):
                    hashes[name] = sha(a.read(path))
            if len(hashes) != len(BUNDLE):
                continue
            recipe, catalog, manifest, ledger = (a.obj(files[name]) for name in
                                                ("building.recipe.json", "catalog_snapshot.json", "candidate_manifest.json", "ledger.json"))
            a.check("bundle building/revision 身份：" + directory.as_posix(), all(v.get("building_id") == building_id
                    and v.get("revision") == revision for v in (recipe, manifest, ledger)))
            a.check("manifest 五件文件清单：" + directory.as_posix(), sorted(manifest.get("file_list", [])) == sorted(BUNDLE))
            a.check("编辑器候选边界：" + directory.as_posix(), manifest.get("authoring_context") == "editor"
                    and manifest.get("noMain") is True and manifest.get("formal_registry_written") is False
                    and ledger.get("status") == "candidate_only" and manifest.get("static_scene") is True
                    and manifest.get("has_workshop_rebuild_script") is False and manifest.get("preview_camera_lights_packed") is False)
            recorded = manifest.get("source_hashes", {})
            for name in ("building.recipe.json", "catalog_snapshot.json", "building.tscn"):
                a.match(files[name], recorded.get(name), "manifest SHA256：" + files[name].as_posix())
            a.match(files["building.tscn"], manifest.get("hash"), "manifest 场景总 hash：" + directory.as_posix())
            sources = manifest.get("authoring_source_hashes", {})
            a.check("authoring_source_hashes 非空：" + directory.as_posix(), isinstance(sources, dict) and bool(sources))
            for value, expected in sources.items():
                a.match(resource(value, project), expected, "创作来源 hash：" + value)
            a.check("recipe/catalog ID 绑定一致：" + directory.as_posix(), bool(catalog.get("catalog_id"))
                    and recipe.get("catalog_id") == catalog.get("catalog_id") == manifest.get("catalog_id"))
            catalog_dependencies(a, catalog, project, directory.as_posix())
            no_script(a, files["building.tscn"])
            versions.append({"revision": revision, "directory": directory.as_posix(), "hashes": hashes,
                             "identity": {key: recipe.get(key) for key in ("building_id", "catalog_id", "schema", "schema_version")}})
        a.check("每楼两个独立 revision 且历史身份一致：" + building_id, len(versions) == 2
                and versions[0]["directory"] != versions[1]["directory"] and versions[0]["identity"] == versions[1]["identity"])
        result.append({"building_id": building_id, "revisions": versions})
    return result


def audit_components(a: Audit, project: Path, artifacts: set[Path], buildids: list[str]) -> list[dict[str, Any]]:
    root = resource("res://scenes/components/workshop_modules", project)
    scenes = sorted(p for p in artifacts if under(p, root) and p.suffix == ".tscn")
    a.check("artifacts 包含真实导出单槽组件", bool(scenes))
    result = []
    for scene in scenes:
        if not a.file(scene, "导出单槽 TSCN 存在"):
            continue
        no_script(a, scene)
        # fixture 的 manifest 可能名为 candidate_manifest；读取实际文件，不假定返回了另一个名字。
        candidates = {p for p in artifacts if p.parent == scene.parent and p.suffix == ".json"}
        candidates |= {scene.parent / name for name in ("component_manifest.json", "candidate_manifest.json")
                       if (scene.parent / name).is_file()}
        manifests = [(p.resolve(), a.obj(p)) for p in sorted(candidates)]
        manifests = [(p, m) for p, m in manifests if m.get("scene_path") == "res://" + scene.relative_to(project).as_posix()
                     and "source_slot_id" in m and "source_component_id" in m]
        a.check("单槽 manifest 按实际 scene_path 唯一匹配：" + scene.as_posix(), len(manifests) == 1,
                [p.as_posix() for p, _ in manifests])
        if len(manifests) == 1:
            a.check("单槽 manifest 来自 editorreport artifacts：" + scene.as_posix(), manifests[0][0] in artifacts)
        if len(manifests) != 1:
            continue
        path, manifest = manifests[0]
        a.check("单槽候选边界", manifest.get("authoring_context") == "editor" and manifest.get("noMain") is True
                and manifest.get("status") == "candidate_only" and manifest.get("formal_registry_written") is False)
        a.match(scene, manifest.get("source_hashes", {}).get(scene.name), "单槽 manifest 场景 hash")
        identity_keys = ("component_id", "building_id", "source_slot_id", "source_component_id", "front_axis")
        identity = {key: manifest.get(key) for key in identity_keys}
        a.check("单槽来源身份完整", all(isinstance(v, str) and bool(v) for v in identity.values())
                and manifest.get("building_id") in buildids and manifest.get("front_axis") == "-Z")
        revision = manifest.get("revision")
        a.check("单槽目录与 revision 身份一致", type(revision) is int and revision > 0
                and scene.parent.name == f"revision{revision:04d}"
                and scene.parent.parent.name == manifest.get("source_slot_id")
                and scene.parent.parent.parent.name == manifest.get("building_id"))
        history = []
        for old_dir in sorted(scene.parent.parent.glob("revision[0-9][0-9][0-9][0-9]")):
            if old_dir.resolve() == scene.parent or not old_dir.is_dir():
                continue
            for filename in ("component_manifest.json", "candidate_manifest.json"):
                old_path = (old_dir / filename).resolve()
                if not under(old_path, root):
                    raise ValueError(f"历史组件路径逃逸：{old_path}")
                if not old_path.is_file():
                    continue
                old = a.obj(old_path)
                old_identity = {key: old.get(key) for key in identity_keys}
                a.check("单槽历史 revision 来源身份不漂移：" + old_path.as_posix(), old_identity == identity)
                old_scene = resource(old["scene_path"], project)
                a.check("历史单槽 scene 属于本版本", old_scene.parent == old_dir.resolve())
                a.check("历史单槽 scene artifact 已列出", old_scene in artifacts)
                a.match(old_scene, old.get("source_hashes", {}).get(old_scene.name), "历史单槽 hash")
                no_script(a, old_scene)
                history.append({"manifest": old_path.as_posix(), "manifest_sha256": sha(a.read(old_path)), "identity": old_identity})
        result.append({"scene": scene.as_posix(), "scene_sha256": sha(a.read(scene)), "manifest": path.as_posix(),
                       "manifest_sha256": sha(a.read(path)), "manifest_listed_in_artifacts": path in artifacts,
                       "identity": identity, "history": history, "history_comparison": "已核对现存历史" if history else "没有历史版本；不声称跨版本验证通过"})
    return result


def audit_registry(a: Audit) -> dict[str, Any]:
    index = a.obj(ROOT / "assets/registry/ledger_index.json")
    domains = index.get("domains", {})
    a.check("JSON routes 非空", isinstance(domains, dict) and bool(domains))
    all_rows = []
    scene_rows = []
    routes = []
    for domain, route in domains.items():
        path = repo_path(route["ledger"])
        rows = a.obj(path)[route["asset_key"]]
        if not isinstance(rows, list):
            raise ValueError(f"账本主数组格式错误：{path}")
        all_rows.extend(rows)
        if domain == "scenes":
            scene_rows = rows
        routes.append({"domain": domain, "ledger": path.as_posix(), "rows": len(rows)})
    ids = [row.get("asset_id") for row in all_rows]
    a.check("JSON routes 全局 AssetID 唯一", all(isinstance(v, str) and bool(v) for v in ids) and len(ids) == len(set(ids)))
    source_index = a.obj(ROOT / "assets/registry/current_source_index.json")
    sources = source_index.get("sources", [])
    source_ids = [row.get("asset_id") for row in sources]
    a.check("source index AssetID 唯一", len(source_ids) == len(set(source_ids)))
    samples = []
    for asset_id in SAMPLE_IDS:
        rows = [row for row in scene_rows if row.get("asset_id") == asset_id]
        source_rows = [row for row in sources if row.get("asset_id") == asset_id]
        a.check("旧样例已登记且 source index 唯一：" + asset_id, len(rows) == len(source_rows) == 1)
        if len(rows) != 1 or len(source_rows) != 1:
            continue
        row, source_row = rows[0], source_rows[0]
        formal = a.obj(repo_path(row["manifest"]))
        sample_id = "workshop_sample_" + asset_id[-3:]
        expected = (ROOT / "art_source/scenes/building_workshop/v001" / sample_id / "building.recipe.json").resolve()
        source = repo_path(row["source"])
        a.check("旧样例仍指向原 art_source recipe：" + asset_id, source == expected and formal.get("source") == row["source"]
                and source_row.get("source") == row["source"] and formal.get("asset_id") == asset_id)
        a.check("旧样例 runtime_path 仍未宣称接入：" + asset_id, "runtime_path" in row and row["runtime_path"] is None
                and "runtime_path" in formal and formal["runtime_path"] is None)
        recipe = a.obj(source)
        a.check("旧样例 recipe 可读且身份保留：" + asset_id, recipe.get("building_id") == sample_id)
        matches = [a.match(source, item.get("source_sha256"), "旧样例 source hash：" + asset_id + ":" + label, True)
                   for item, label in ((row, "ledger"), (formal, "manifest"), (source_row, "source_index"))]
        samples.append({"asset_id": asset_id, "source": source.as_posix(), "hash_matches": matches})
    return {"routes": routes, "global_asset_count": len(ids), "samples": samples, "registration_executed": False,
            "new_asset_ids_created": 0, "existing_hashes_refreshed": False}


def contracts(output: Path, enabled: bool) -> dict[str, Any]:
    status: dict[str, Any] = {"kind": "workshop_editor_contract_status", "requested": enabled,
                              "status": "not_run", "passed": None, "results": []}
    if not enabled:
        prior = output.parent / "contract_status.json"
        if prior.is_file():
            recorded = json.loads(prior.read_text(encoding="utf-8"))
            recorded["reused_evidence"] = prior.as_posix()
            return recorded
        return status
    commands = [("sync", [sys.executable, str((ROOT / "scripts/check_feature_contracts.py").resolve()), "--sync"]),
                ("check", [sys.executable, str((ROOT / "scripts/check_feature_contracts.py").resolve())])]
    for name, command in commands:
        log = (output.parent / f"contracts_{name}.log").resolve()
        if log.exists():
            raise ValueError(f"拒绝覆盖已有契约日志，请使用新的 output 目录：{log}")
        with log.open("x", encoding="utf-8") as stream:
            try:
                code = subprocess.run(command, cwd=str(ROOT), stdout=stream, stderr=subprocess.STDOUT,
                                      check=False).returncode
                error = None
            except OSError as exc:
                code, error = None, str(exc)
                stream.write(error + "\n")
        status["results"].append({"name": name, "command": command, "exit_code": code,
                                  "passed": code == 0, "log": log.as_posix(), "error": error})
    status["passed"] = all(row["passed"] for row in status["results"])
    status["status"] = "passed" if status["passed"] else "failed"
    write_json(output.parent / "contract_status.json", status)
    return status


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path, help="真实 runner report.json 的完整绝对路径")
    parser.add_argument("--editor-project", type=Path, help="真实隔离项目完整路径；默认从 runner command 的 --path 读取")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="工程外交付报告完整路径")
    parser.add_argument("--contracts", action="store_true", help="实际运行 sync --check 和契约检查，不修复、不刷新")
    args = parser.parse_args()
    a = Audit()
    summary: dict[str, Any] = {"kind": KIND, "schema_version": 1, "created_at": datetime.now(timezone.utc).isoformat(),
                               "known_limits": KNOWN_LIMITS, "visualpaths": [], "visual_acceptance": "not_signed",
                               "whole_project_contracts": {"requested": args.contracts, "status": "not_run", "passed": None},
                               "engine_executed_by_audit": False}
    try:
        report_path, output = absolute(args.report), absolute(args.output)
        if under(report_path, ROOT) or under(output, ROOT):
            raise ValueError("runner report 和 output 都必须在正式工程外")
        if report_path.name != "report.json" or not report_path.is_file():
            raise ValueError("--report 必须指向存在的真实 runner report.json")
        runner = a.obj(report_path)
        result = runner.get("results", {}).get("editor-workshop", {})
        command = result.get("command")
        if not isinstance(command, list) or not command or not all(isinstance(v, str) for v in command):
            raise ValueError("runner 缺少真实 editor-workshop command 数组")
        if command.count("--path") != 1 or command.index("--path") + 1 >= len(command):
            raise ValueError("真实 command 必须包含唯一 --path")
        command_project = absolute(command[command.index("--path") + 1])
        project = absolute(args.editor_project) if args.editor_project else command_project
        if under(project, ROOT) or under(ROOT, project) or not project.is_dir():
            raise ValueError("editor-project 必须是独立于正式工程的真实目录")
        if project != command_project:
            raise ValueError("--editor-project 与 runner 实际 --path 不一致")
        run_dir = absolute(runner["run_dir"])
        if run_dir != report_path.parent or project != (run_dir / "project").resolve():
            raise ValueError("runner run_dir/report/project 三者不匹配")
        editor_path = resource("res://outputs/workshop_editor_report.json", project)
        if under(output, project) or output in (report_path, editor_path):
            raise ValueError("output 不能覆盖隔离项目或输入报告")
        if output.suffix.lower() != ".json" or output.name in ("report.json", "workshop_editor_report.json", "contract_status.json"):
            raise ValueError("output 必须是独立的交付 JSON 文件")
        if output.exists():
            previous = json.loads(output.read_text(encoding="utf-8-sig"))
            if not isinstance(previous, dict) or previous.get("kind") != KIND:
                raise ValueError("拒绝覆盖非本脚本交付报告")
        # 固定名字的附产物也必须在工程外，且不得覆盖输入或已有任意文件。
        for name in ("contracts_sync.log", "contracts_check.log", "contract_status.json") if args.contracts else ():
            target = (output.parent / name).resolve()
            if target.exists() or under(target, ROOT) or under(target, project) or target == report_path:
                raise ValueError(f"契约输出已存在或不安全：{target}")
        output.parent.mkdir(parents=True, exist_ok=True)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"passed": False, "status": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 2

    a.editor_project = project
    summary.update({"report": report_path.as_posix(), "editor_project": project.as_posix(), "editor_report": editor_path.as_posix(),
                    "output": output.as_posix(), "runner_head": runner.get("head"), "runner_working_tree": runner.get("working_tree"),
                    "command": command, "sources": [], "bundles": [], "components": []})
    editor_passed = False
    try:
        engine_args = command[1:command.index("--")] if "--" in command else command[1:]
        a.check("实际 command 使用 --editor 且非 --script", "--editor" in engine_args
                and not any(v in ("--script", "-s", "--headless") or v.startswith("--script=") for v in engine_args), command)
        a.check("实际 command 启用编辑器专项验证", "--" in command and "--workshop-editor-verify" in command[command.index("--") + 1:])
        runner_passed = result.get("passed") is True and result.get("exit_code") == 0
        a.check("runner editor-workshop passed 且真实 exit 0", runner_passed, result)
        a.check("runner 失败标记为空", result.get("failure_markers", []) == [] and not result.get("unexpected_errors", []))
        a.check("runner 无 unexpected_errors 且完成标记存在", result.get("unexpected_errors") == [] and result.get("completion_marker") is True)
        if "passed" in runner:
            a.check("runner 顶层 passed", runner["passed"] is True)
        log_path = absolute(result["log"])
        a.check("runner 日志属于本批次", under(log_path, run_dir) and not under(log_path, project))
        log = a.text(log_path)
        completion = re.search(r"\[workshop-editor\]\s+(\d+)\s+checks,\s+(\d+)\s+failures", log)
        a.check("真实日志 editor 完成标记及零失败", completion is not None and int(completion.group(1)) > 0 and int(completion.group(2)) == 0)
        config = a.text(project / "project.godot")
        a.check("隔离 config 没有 Autoload", not section(config, "autoload"))
        a.check("隔离 config noMain", section(config, "application").get("run/main_scene", '""') == '""')
        a.check("隔离 config onlyPlugin", plugins(config) == [PLUGIN])
        editor = a.obj(editor_path)
        a.check("内层报告 project_path 对应真实隔离项目", absolute(editor["project_path"]) == project)
        checks = editor.get("checks", [])
        a.check("内层 checks 是非空逐项数组", isinstance(checks, list) and bool(checks))
        if not isinstance(checks, list):
            raise ValueError("内层 checks 不能用计数或源码断言冒充")
        for index, row in enumerate(checks):
            a.check(f"editor check[{index}]：" + str(row.get("name", "")) if isinstance(row, dict) else f"editor check[{index}] 无效",
                    isinstance(row, dict) and isinstance(row.get("name"), str) and bool(row.get("name")) and row.get("passed") is True, row)
        failures = editor.get("failures")
        a.check("editor failures 为零", failures == [])
        flags = {"enginehint": True, "is_playing": False, "root_paused_unchanged": True, "scene_unchanged": True}
        for key, expected in flags.items():
            a.check("editor 状态：" + key, editor.get(key) is expected, editor.get(key))
        a.check("editor 没有未满足依赖", editor.get("dependencies") == [])
        a.check("editor 未连接游戏存档", editor.get("game_save_connected") is False)
        names = {row.get("name") for row in checks if isinstance(row, dict) and row.get("passed") is True}
        required = ("真实 --editor 非 --script", "隔离项目没有 Autoload", "隔离项目没有 Main 入口", "只启用楼房工坊插件",
                    "fixture 只能写隔离副本", "编辑器树没有启动 Main", "旧 revision 内容不变", "选中槽独立成功替件",
                    "真实生成槽使用独立替件且尺寸不变", "预览实际实例化替件 PackedScene")
        for name in required:
            a.check("专项必要实测断言：" + name, name in names)
        for label in ("revision1", "revision2"):
            for suffix in ("真实 PackedScene 重载", "实例化前递归确认无 Script", "静态实例无脚本相机灯光", "两次实例化 geometry hash 一致",
                           "导出实例与实际预览 geometry hash 一致"):
                a.check("专项静态必要实测断言：" + label + " " + suffix, label + " " + suffix in names)
        a.check("日志 checks 与真实 JSON 逐项数一致", completion is not None and int(completion.group(1)) == len(checks))
        editor_passed = editor.get("passed") is True and failures == [] and bool(checks) and all(
            isinstance(row, dict) and row.get("passed") is True for row in checks) and all(editor.get(k) is v for k, v in flags.items())
        a.check("内层 editor passed", editor_passed)
        summary["editor"] = {"passed": editor_passed, "checks_count": len(checks), "failed": failures,
                             **{k: editor.get(k) for k in flags}, "input_method": editor.get("input_method"),
                             "lifecycle_scope": editor.get("lifecycle_scope")}
        raw_artifacts = editor.get("artifacts")
        if not isinstance(raw_artifacts, list) or not all(isinstance(v, str) for v in raw_artifacts):
            raise ValueError("editor artifacts 必须是真实 res:// 路径数组")
        artifacts = {resource(value, project) for value in raw_artifacts}
        for path in sorted(artifacts):
            if a.file(path, "报告 artifact 存在：" + path.as_posix()):
                a.read(path)
        a.check("artifacts 包含报告自身", editor_path in artifacts)
        visuals = []
        for path in sorted(artifacts):
            if path.suffix.lower() != ".png":
                continue
            raw = a.read(path)
            valid = raw.startswith(b"\x89PNG\r\n\x1a\n") and len(raw) >= 24 and raw[12:16] == b"IHDR"
            a.check("实际 PNG 证据（非美术签收）：" + path.as_posix(), valid)
            visuals.append({"path": path.as_posix(), "sha256": sha(raw),
                            "width": int.from_bytes(raw[16:20], "big") if valid else None,
                            "height": int.from_bytes(raw[20:24], "big") if valid else None, "art_accepted": False})
        a.check("真实报告包含 PNG 视觉证据", bool(visuals))
        summary["visualpaths"] = visuals
        summary["sources"] = audit_sources(a, project)
        summary["retained"] = audit_retained(a)
        summary["bundles"] = audit_bundles(a, editor, project, artifacts)
        summary["components"] = audit_components(a, project, artifacts, editor.get("buildids", []))
        summary["registry"] = audit_registry(a)
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
        a.check("专项审计完整执行", False, f"{type(exc).__name__}: {exc}")
    try:
        summary["whole_project_contracts"] = contracts(output, args.contracts)
    except (OSError, ValueError) as exc:
        summary["whole_project_contracts"] = {"requested": args.contracts, "status": "error", "passed": False, "error": str(exc)}
    summary["input_hash_guard"] = a.finish_inputs()
    failed = [row for row in a.checks if row["passed"] is not True]
    audit_passed = not failed
    summary.update({"audit_passed": audit_passed, "editor_passed": editor_passed, "passed": audit_passed and editor_passed,
                    "status": "passed" if audit_passed and editor_passed else "failed", "checks_count": len(a.checks),
                    "failed_count": len(failed), "failed": failed, "checks": a.checks,
                    "passed_definition": "本轮专用审计 audit_passed AND 真实内层 editor_passed；全工程契约另列，不掩盖漂移"})
    write_json(output, summary)
    print(json.dumps({key: summary[key] for key in ("output", "passed", "audit_passed", "editor_passed", "checks_count", "failed_count",
                                                     "visualpaths", "whole_project_contracts")}, ensure_ascii=False, indent=2))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
