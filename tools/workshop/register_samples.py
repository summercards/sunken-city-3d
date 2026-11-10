#!/usr/bin/env python3
"""登记楼房工坊原生 Godot 样例；默认预检，--copy 复制正式副本，--write 才写账本。"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import shutil
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
INDEX_REL = Path("assets/registry/ledger_index.json")
SOURCE_INDEX_REL = Path("assets/registry/current_source_index.json")
SAMPLE_IDS = ("workshop_sample_001", "workshop_sample_002")
ASSET_IDS = tuple("SEA-SCENE-WORKSHOP-SAMPLE-" + value[-3:] for value in SAMPLE_IDS)
LEDGER_DOMAIN = "scenes"
FORMAL_ROOT_REL = Path("art_source/scenes/building_workshop/v001")
PROVENANCE_RELS = (
    Path("godot/src/workshop/generator.gd"),
    Path("godot/src/workshop/store.gd"),
    Path("godot/src/workshop/recipe.gd"),
    Path("godot/src/workshop/catalog.gd"),
)
REPORT_FILES = ("building.recipe.json", "building.tscn", "candidate_manifest.json", "catalog_snapshot.json", "ledger.json")
PROPOSAL_NAME = "workshop_samples_registration_proposal.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def real_path(value: str | Path) -> Path:
    return Path(value).expanduser().resolve()


def path_text(path: Path) -> str:
    return path.as_posix()


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def formal_bundle(sample_id: str) -> dict[str, Path]:
    directory = ROOT / FORMAL_ROOT_REL / sample_id
    return {
        "directory": directory,
        "recipe": directory / "building.recipe.json",
        "scene": directory / "building.tscn",
        "manifest": directory / "candidate_manifest.json",
        "catalog": directory / "catalog_snapshot.json",
        "ledger": directory / "ledger.json",
    }


def report_row(report: dict[str, Any], sample_id: str, errors: list[str]) -> dict[str, Any]:
    row = next((value for value in report.get("samples", []) if value.get("building_id") == sample_id), None)
    require(isinstance(row, dict), f"report缺少 {sample_id}", errors)
    return row if isinstance(row, dict) else {}


def report_bundle(report: dict[str, Any], sample_id: str, samples_root: Path, errors: list[str]) -> dict[str, Path]:
    row = report_row(report, sample_id, errors)
    directory_value = row.get("directory_filesystem_path") or row.get("directory")
    require(directory_value is not None, f"{sample_id} report缺少真实目录", errors)
    directory = real_path(str(directory_value)) if directory_value is not None else samples_root / sample_id
    require(directory.is_relative_to(samples_root), f"{sample_id} 输出目录不在samples-root下", errors)
    result: dict[str, Path] = {"directory": directory}
    paths = row.get("paths", {})
    for filename in REPORT_FILES:
        entry = paths.get(filename, {}) if isinstance(paths, dict) else {}
        value = entry.get("filesystem_path") if isinstance(entry, dict) else None
        path = real_path(str(value)) if value else directory / filename
        require(path.name == filename and path.parent == directory, f"{sample_id} report路径不匹配 {filename}", errors)
        result[Path(filename).stem] = path
    # Path("building.recipe.json").stem 是 building.recipe；统一使用逻辑键。
    result = {"directory": directory, **{key: directory / name for key, name in {
        "recipe": "building.recipe.json", "scene": "building.tscn", "manifest": "candidate_manifest.json",
        "catalog": "catalog_snapshot.json", "ledger": "ledger.json",
    }.items()}}
    for filename, key in zip(REPORT_FILES, ("recipe", "scene", "manifest", "catalog", "ledger")):
        entry = paths.get(filename, {}) if isinstance(paths, dict) else {}
        value = entry.get("filesystem_path") if isinstance(entry, dict) else None
        if value:
            result[key] = real_path(str(value))
    return result


def validate_bundle(samples_root: Path, sample_id: str, report: dict[str, Any], errors: list[str]) -> tuple[dict[str, Path], dict[str, Any]]:
    bundle = report_bundle(report, sample_id, samples_root, errors)
    for key, path in bundle.items():
        if key != "directory":
            require(path.is_file(), f"{sample_id} 缺少 {path.name}", errors)
    if any(not path.is_file() for key, path in bundle.items() if key != "directory"):
        return bundle, {}
    try:
        recipe = load_json(bundle["recipe"])
        manifest = load_json(bundle["manifest"])
        catalog = load_json(bundle["catalog"])
        ledger = load_json(bundle["ledger"])
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"{sample_id} 输出JSON读取失败: {exc}")
        return bundle, {}
    for value, label in ((recipe, "配方"), (manifest, "manifest"), (catalog, "catalog"), (ledger, "ledger")):
        require(isinstance(value, dict), f"{sample_id} {label}不是对象", errors)
    if not all(isinstance(value, dict) for value in (recipe, manifest, catalog, ledger)):
        return bundle, {}
    require(recipe.get("building_id") == sample_id, f"{sample_id} 配方building_id不匹配", errors)
    require(manifest.get("building_id") == sample_id, f"{sample_id} manifest building_id不匹配", errors)
    require(manifest.get("static_scene") is True, f"{sample_id} 不是static_scene", errors)
    require(manifest.get("has_workshop_rebuild_script") is False, f"{sample_id} 含工坊重建脚本", errors)
    require(ledger.get("status") == "candidate_only", f"{sample_id} ledger状态不是candidate_only", errors)
    row = report_row(report, sample_id, errors)
    report_hashes = row.get("hashes", {})
    for key, path in bundle.items():
        if key != "directory":
            require(report_hashes.get(path.name) == digest(path), f"{sample_id} report中{path.name} hash不匹配", errors)
    return bundle, {"recipe": recipe, "manifest": manifest, "catalog": catalog, "ledger": ledger}


def read_state() -> tuple[dict[str, Any], dict[str, Any], dict[str, list[dict[str, Any]]], dict[str, bytes]]:
    index = load_json(ROOT / INDEX_REL)
    books: dict[str, list[dict[str, Any]]] = {}
    snapshots: dict[str, bytes] = {}
    for domain, route in index["domains"].items():
        rel = route["ledger"]
        path = ROOT / rel
        snapshots[rel] = path.read_bytes()
        book = load_json(path)
        books[domain] = book[route["asset_key"]]
    snapshots[path_text(SOURCE_INDEX_REL)] = (ROOT / SOURCE_INDEX_REL).read_bytes()
    scene_route = index["domains"][LEDGER_DOMAIN]
    for view_path in scene_route.get("building_views", {}).values():
        snapshots[view_path] = (ROOT / view_path).read_bytes()
    return index, load_json(ROOT / SOURCE_INDEX_REL), books, snapshots


def load_rules() -> Any:
    path = ROOT / "tools/apply_water_layer.py"
    spec = importlib.util.spec_from_file_location("workshop_water_rules", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("无法加载 apply_water_layer.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def source_provenance(errors: list[str]) -> list[dict[str, str]]:
    result = []
    for rel in PROVENANCE_RELS:
        path = ROOT / rel
        require(path.is_file(), f"缺少工坊源码 {rel}", errors)
        if path.is_file():
            result.append({"path": path_text(rel), "sha256": digest(path)})
    return result


def formal_files(sample_id: str, candidate: dict[str, Path], use_formal: bool, errors: list[str]) -> dict[str, Path]:
    if not use_formal:
        return candidate
    formal = formal_bundle(sample_id)
    require(formal["directory"].is_dir(), f"{sample_id} 正式样例目录不存在，请先使用 --copy", errors)
    for key in ("recipe", "scene", "manifest", "catalog", "ledger"):
        require(formal[key].is_file(), f"{sample_id} 正式副本缺少 {formal[key].name}", errors)
        if formal[key].is_file() and candidate[key].is_file():
            require(formal[key].read_bytes() == candidate[key].read_bytes(), f"{sample_id} 正式副本不是输出原封字节: {key}", errors)
    return formal


def copy_formal_bundles(bundles: dict[str, dict[str, Path]], errors: list[str]) -> None:
    parent = ROOT / "art_source/scenes"
    require(parent.is_dir(), f"正式源父路径不存在: {parent}", errors)
    version_root = ROOT / FORMAL_ROOT_REL
    if version_root.exists() and not version_root.is_dir():
        errors.append(f"正式版本路径不是目录: {version_root}")
        return
    # 先完整预检，任何已有差异都会拒绝，不覆盖差异文件。
    for sample_id in SAMPLE_IDS:
        source = bundles[sample_id]
        target = formal_bundle(sample_id)
        for key in ("recipe", "scene", "manifest", "catalog", "ledger"):
            if target[key].exists():
                require(target[key].is_file() and target[key].read_bytes() == source[key].read_bytes(), f"{sample_id} 正式副本存在差异，拒绝覆盖: {key}", errors)
    if errors:
        return
    version_root.mkdir(parents=True, exist_ok=True)
    for sample_id in SAMPLE_IDS:
        source = bundles[sample_id]
        target = formal_bundle(sample_id)
        target["directory"].mkdir(parents=True, exist_ok=True)
        for key in ("recipe", "scene", "manifest", "catalog", "ledger"):
            if not target[key].exists():
                shutil.copyfile(source[key], target[key])
            require(target[key].read_bytes() == source[key].read_bytes(), f"{sample_id} 复制后字节校验失败: {key}", errors)


def make_rows(index: dict[str, Any], bundles: dict[str, dict[str, Any]], errors: list[str], use_formal: bool) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[tuple[str, dict[str, Any]]]]:
    route = index["domains"][LEDGER_DOMAIN]
    ledger_ref = route["ledger"]
    provenance = source_provenance(errors)
    rows: list[dict[str, Any]] = []
    source_rows: list[dict[str, Any]] = []
    manifests: list[tuple[str, dict[str, Any]]] = []
    for sample_id, asset_id in zip(SAMPLE_IDS, ASSET_IDS):
        candidate_files = bundles[sample_id]["files"]
        data = bundles[sample_id]["data"]
        recipe = data["recipe"]
        candidate_manifest = data["manifest"]
        files = formal_files(sample_id, candidate_files, use_formal, errors)
        candidate_hashes = {path.name: digest(path) for key, path in candidate_files.items() if key != "directory"}
        hashes = {path.name: digest(path) for key, path in files.items() if key != "directory"}
        registry_manifest = f"assets/registry/manifests/{asset_id.lower()}.json"
        asset_ledger = ledger_ref + "#" + asset_id
        row: dict[str, Any] = {
            "asset_id": asset_id,
            "source_id": "SRC-" + asset_id,
            "name": str(recipe["display_name"]),
            "display_name": str(recipe["display_name"]),
            "domain": LEDGER_DOMAIN,
            "suite": "sea_workshop_v1",
            "scope": "native_godot_static_candidate",
            "category": "building_assembly",
            "classification": {"category": "building", "subcategory": "workshop_sample", "family": "workshop_sample", "status": "classified"},
            "building_class": "above_water",
            "water_layer": "surface",
            "water_layer_role": "entity",
            "stage": "native_godot_candidate_exported_runtime_pending",
            "source": files["recipe"].relative_to(ROOT).as_posix() if use_formal else path_text(files["recipe"]),
            "source_sha256": hashes["building.recipe.json"],
            "manifest": registry_manifest,
            "version": "v001",
            "runtime_path": None,
            "runtime_sha256": None,
            "static_scene": files["scene"].relative_to(ROOT).as_posix() if use_formal else path_text(files["scene"]),
            "static_scene_sha256": hashes["building.tscn"],
            "prefab": None,
            "license": "project_authored_procedural_source",
            "consumer_features": ["SEA-WORKSHOP", "SEA-ASSET"],
            "asset_ledger": asset_ledger,
            "candidate_source": path_text(candidate_files["recipe"]),
            "candidate_files": {key: path_text(path) for key, path in candidate_files.items() if key != "directory"},
            "candidate_hashes": candidate_hashes,
            "catalog_snapshot": files["catalog"].relative_to(ROOT).as_posix() if use_formal else path_text(files["catalog"]),
            "catalog_snapshot_sha256": hashes["catalog_snapshot.json"],
            "catalog_id": str(recipe.get("catalog_id", "")),
            "recipe_fingerprint": candidate_manifest.get("recipe_fingerprint", ""),
            "catalog_fingerprint": candidate_manifest.get("catalog_fingerprint", ""),
            "source_provenance": provenance,
            "geometry": candidate_manifest.get("geometry", {}),
            "stats": candidate_manifest.get("stats", {}),
            "validation": {"source": "registered_and_hash_checked", "runtime": "pending", "visual": "pending", "collision": "pending", "navigation": "pending", "user_art_acceptance": "pending"},
            "verification": "tools/workshop/register_samples.py",
            "note": "正式代码来源为 Godot Native 参数生成器；静态TSCN是候选产物，不冒称已被Godot运行时消费，不伪造Blender或GLB来源。",
        }
        registry_manifest_value = {
            "asset_id": asset_id,
            "source_id": row["source_id"],
            "asset_ledger": asset_ledger,
            "source_type": "project_authored_native_Godot_source_no_Blender_or_GLB",
            "version": "v001",
            "building_id": sample_id,
            "display_name": row["display_name"],
            "source": row["source"],
            "source_sha256": row["source_sha256"],
            "static_scene": row["static_scene"],
            "static_scene_sha256": row["static_scene_sha256"],
            "runtime_path": None,
            "candidate_source": row["candidate_source"],
            "candidate_files": row["candidate_files"],
            "candidate_hashes": row["candidate_hashes"],
            "catalog_snapshot": row["catalog_snapshot"],
            "catalog_snapshot_sha256": row["catalog_snapshot_sha256"],
            "source_provenance": provenance,
            "recipe": recipe,
            "generator_manifest": candidate_manifest,
            "candidate_ledger": data["ledger"],
            "classification": row["classification"],
            "building_class": row["building_class"],
            "water_layer": row["water_layer"],
            "water_layer_role": row["water_layer_role"],
            "validation": row["validation"],
        }
        rows.append(row)
        source_rows.append({"asset_id": asset_id, "source": row["source"], "source_sha256": row["source_sha256"], "manifest": registry_manifest})
        manifests.append((registry_manifest, registry_manifest_value))
    require(len({row["asset_id"] for row in rows}) == len(rows), "本轮AssetID重复", errors)
    return rows, source_rows, manifests


def array_bounds(raw: str, key: str) -> tuple[int, int]:
    marker = re.search(r'"' + re.escape(key) + r'"\s*:\s*\[', raw)
    if marker is None:
        raise ValueError(f"找不到JSON数组 {key}")
    start = raw.find("[", marker.start())
    depth = 0
    quoted = False
    escaped = False
    for index in range(start, len(raw)):
        char = raw[index]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return start, index
    raise ValueError(f"JSON数组 {key} 未闭合")


def array_object_bytes(raw: bytes, key: str) -> list[bytes]:
    text = raw.decode("utf-8")
    start, close = array_bounds(text, key)
    result: list[bytes] = []
    object_start = -1
    depth = 0
    quoted = False
    escaped = False
    for index in range(start + 1, close):
        char = text[index]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == '"':
            quoted = True
        elif char == "{" and depth == 0:
            object_start = index
            depth = 1
        elif char == "{" and depth > 0:
            depth += 1
        elif char == "}" and depth > 0:
            depth -= 1
            if depth == 0:
                result.append(text[object_start:index + 1].encode("utf-8"))
                object_start = -1
    return result


def append_array_entries(raw: bytes, key: str, values: list[dict[str, Any]]) -> bytes:
    text = raw.decode("utf-8")
    _, close = array_bounds(text, key)
    insert_at = close
    while insert_at > 0 and text[insert_at - 1].isspace():
        insert_at -= 1
    rendered = ",\n".join(json.dumps(value, ensure_ascii=False, indent=2) for value in values).replace("\n", "\n    ")
    return (text[:insert_at] + ",\n    " + rendered + text[insert_at:]).encode("utf-8")


def insert_source_entries_before(raw: bytes, source_ids: list[str], scene_count: int, values: list[dict[str, Any]]) -> bytes:
    text = raw.decode("utf-8")
    _, close = array_bounds(text, "sources")
    if not values:
        return raw
    if scene_count == len(source_ids):
        return append_array_entries(raw, "sources", values)
    target = source_ids[scene_count]
    target_match = re.search(r'\n    \{\n      "asset_id": ' + re.escape(json.dumps(target)) + r',', text)
    if target_match is None or target_match.start() >= close:
        raise ValueError(f"current_source_index找不到场景边界 {target}")
    rendered = ",\n".join(json.dumps(value, ensure_ascii=False, indent=2) for value in values).replace("\n", "\n    ")
    return (text[:target_match.start() + 1] + "    " + rendered + ",\n" + text[target_match.start() + 1:]).encode("utf-8")


def old_objects_preserved(before: bytes, after: bytes, key: str, new_ids: set[str], errors: list[str]) -> None:
    old_objects = array_object_bytes(before, key)
    new_objects = array_object_bytes(after, key)
    kept = []
    for value in new_objects:
        parsed = json.loads(value)
        if parsed.get("asset_id") not in new_ids:
            kept.append(value)
    require(kept == old_objects, f"{key}中旧JSON对象字节发生变化", errors)


def build_proposal(samples_root: Path, report_path: Path, rows: list[dict[str, Any]], manifests: list[tuple[str, dict[str, Any]]], errors: list[str], copied: bool = False) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "kind": "targeted_asset_registration_proposal",
        "tool": "tools/workshop/register_samples.py",
        "samples_root": path_text(samples_root),
        "report": path_text(report_path),
        "domain": LEDGER_DOMAIN,
        "asset_ids": [row["asset_id"] for row in rows],
        "manifest_paths": [path for path, _ in manifests],
        "classification": {"family": "workshop_sample", "status": "classified", "building_class": "above_water", "water_layer": "surface", "water_layer_role": "entity"},
        "formal_copies_checked_or_created": copied,
        "write_scope": ["最多2条新AssetID主记录", "最多2个新registry manifest", "最多2条新source-index行", "两个building view派生"],
        "existing_rows_rewritten": False,
        "existing_hashes_refreshed": False,
        "main_scene_modified": False,
        "blender_source_claimed": False,
        "errors": list(errors),
        "status": "blocked" if errors else "ready_for_explicit_write",
    }


def backup_targets(report_path: Path, targets: dict[str, bytes], errors: list[str]) -> Path | None:
    backup_dir = report_path.parent / "registration_backup"
    backup_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for rel, raw in targets.items():
        name = Path(rel).name
        path = backup_dir / name
        if path.exists():
            require(path.is_file() and path.read_bytes() == raw, f"已有备份与当前目标不一致: {path}", errors)
        else:
            path.write_bytes(raw)
        records.append({"target": rel, "backup": path_text(path), "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)})
    manifest = {"schema_version": 1, "report": path_text(report_path), "targets": records}
    manifest_path = backup_dir / "backup_manifest.json"
    payload = dump_json(manifest).encode("utf-8")
    if manifest_path.exists():
        require(manifest_path.read_bytes() == payload, f"已有backup_manifest与当前目标不一致: {manifest_path}", errors)
    else:
        manifest_path.write_bytes(payload)
    return backup_dir


def assert_target_snapshots(snapshots: dict[str, bytes], target_rels: set[str], errors: list[str]) -> None:
    for rel in target_rels:
        path = ROOT / rel
        require(path.is_file() and path.read_bytes() == snapshots[rel], f"并发修改，拒绝写入: {rel}", errors)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples-root", required=True, type=Path, help="工程外真实 workshop_samples 输出目录")
    parser.add_argument("--report", type=Path, help="真实 workshop_samples_report.json 路径")
    parser.add_argument("--copy", action="store_true", help="把report中的五件输出原封复制到正式 art_source 目录")
    parser.add_argument("--write", action="store_true", help="预检通过后写入两条新增记录及派生view")
    args = parser.parse_args()

    samples_root = real_path(args.samples_root)
    report_path = real_path(args.report) if args.report else samples_root.parent / "workshop_samples_report.json"
    errors: list[str] = []
    require(samples_root.is_dir(), "samples-root必须是存在的工程外目录", errors)
    require(not samples_root.is_relative_to(ROOT), "samples-root必须位于工程外", errors)
    require(report_path.is_file(), "真实 workshop_samples_report.json 不存在", errors)
    if errors:
        print(json.dumps({"status": "blocked", "errors": errors}, ensure_ascii=False, indent=2))
        return 2

    report = load_json(report_path)
    require(report.get("marker") == "workshop-samples", "report marker不是workshop-samples", errors)
    require(report.get("status") == "passed", "report不是passed", errors)
    require(report.get("failures") == [], "report包含失败", errors)
    require(int(report.get("checks", 0)) > 0, "report没有checks", errors)
    bundles: dict[str, dict[str, Any]] = {}
    for sample_id in SAMPLE_IDS:
        try:
            files, data = validate_bundle(samples_root, sample_id, report, errors)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            errors.append(f"{sample_id} 输出校验异常: {exc}")
            continue
        bundles[sample_id] = {"files": files, "data": data}
    if len(bundles) != len(SAMPLE_IDS):
        errors.append("两栋样例输出未全部通过校验")

    if args.copy and not errors:
        copy_formal_bundles({sample_id: value["files"] for sample_id, value in bundles.items()}, errors)

    try:
        index, source_index, books, snapshots = read_state()
        rules = load_rules()
    except (OSError, KeyError, json.JSONDecodeError, RuntimeError) as exc:
        errors.append(f"仓库规则或账本读取失败: {exc}")
        print(json.dumps({"status": "blocked", "errors": errors}, ensure_ascii=False, indent=2))
        return 2
    for asset_id in ASSET_IDS:
        try:
            require(rules.classify(asset_id) == ("surface", "entity"), f"规则未将{asset_id}分类为surface/entity", errors)
            require(rules.classify_building(asset_id) == "above_water", f"规则未将{asset_id}分类为above_water", errors)
        except KeyError:
            errors.append(f"规则模块缺少样例family: {asset_id}")

    all_rows = [asset for assets in books.values() for asset in assets]
    all_ids = [asset["asset_id"] for asset in all_rows]
    require(len(all_ids) == len(set(all_ids)), "全库已有AssetID重复，拒绝新增", errors)
    existing_by_id = {row["asset_id"]: row for row in books[LEDGER_DOMAIN]}
    for asset_id in ASSET_IDS:
        other = next((row for row in all_rows if row["asset_id"] == asset_id and row not in books[LEDGER_DOMAIN]), None)
        require(other is None, f"目标AssetID已存在于其他分账本: {asset_id}", errors)

    use_formal = args.copy or args.write
    if not errors:
        rows, source_rows, manifests = make_rows(index, bundles, errors, use_formal)
    else:
        rows, source_rows, manifests = [], [], []

    route = index["domains"][LEDGER_DOMAIN]
    ledger_rel = route["ledger"]
    source_rel = path_text(SOURCE_INDEX_REL)
    scene_ids = [asset["asset_id"] for asset in books[LEDGER_DOMAIN]]
    source_ids = [row["asset_id"] for row in source_index.get("sources", [])]
    require(source_ids[:len(scene_ids)] == scene_ids, "current_source_index场景前缀与scenes ledger不一致", errors)
    require(len(source_ids) == len(set(source_ids)), "current_source_index已有AssetID重复", errors)

    existing_source = {row["asset_id"]: row for row in source_index.get("sources", [])}
    existing_manifests = {path: (ROOT / path).read_bytes() for path, _ in manifests if (ROOT / path).is_file()}
    new_rows: list[dict[str, Any]] = []
    new_source_rows: list[dict[str, Any]] = []
    new_manifests: list[tuple[str, dict[str, Any]]] = []
    for row, source_row, manifest_item in zip(rows, source_rows, manifests):
        asset_id = row["asset_id"]
        old = existing_by_id.get(asset_id)
        if old is not None:
            for key in ("source", "source_sha256", "manifest"):
                require(old.get(key) == row.get(key), f"旧同id的{key}不一致，拒绝: {asset_id}", errors)
            old_source = existing_source.get(asset_id)
            require(old_source is not None, f"旧同id缺少source index行: {asset_id}", errors)
            if old_source is not None:
                for key in ("source", "source_sha256", "manifest"):
                    require(old_source.get(key) == source_row.get(key), f"旧source index的{key}不一致，拒绝: {asset_id}", errors)
            manifest_path, manifest_value = manifest_item
            expected = dump_json(manifest_value).encode("utf-8")
            require(manifest_path in existing_manifests and existing_manifests[manifest_path] == expected, f"旧同id manifest不一致，拒绝: {asset_id}", errors)
        else:
            new_rows.append(row)
            new_source_rows.append(source_row)
            new_manifests.append(manifest_item)

    final_scene_assets = list(books[LEDGER_DOMAIN]) + new_rows
    try:
        derived_views = rules.building_views(final_scene_assets, ledger_rel)
    except Exception as exc:
        errors.append(f"building_views派生失败: {exc}")
        derived_views = {}
    view_paths = route.get("building_views", {})
    desired_views: dict[str, bytes] = {}
    for name, value in derived_views.items():
        rel = view_paths.get(name)
        if rel:
            desired_views[rel] = dump_json(value).encode("utf-8")
    changed_views = [rel for rel, raw in desired_views.items() if snapshots.get(rel) != raw]
    require(len(changed_views) <= 1 and (not changed_views or changed_views[0] == view_paths.get("above_water")), "本轮预期只能改变above_water派生view", errors)

    proposal = build_proposal(samples_root, report_path, rows, manifests, errors, copied=args.copy)
    proposal_path = report_path.parent / PROPOSAL_NAME
    proposal_path.write_text(dump_json(proposal), encoding="utf-8")
    print(json.dumps(proposal, ensure_ascii=False, indent=2))
    if errors:
        return 2
    if not args.write:
        return 0

    ledger_raw = snapshots[ledger_rel]
    source_raw = snapshots[source_rel]
    new_ledger_raw = append_array_entries(ledger_raw, route["asset_key"], new_rows)
    new_source_raw = insert_source_entries_before(source_raw, source_ids, len(scene_ids), new_source_rows)
    old_scene_count = len(scene_ids)
    scene_after = json.loads(new_ledger_raw.decode("utf-8"))[route["asset_key"]]
    source_after = json.loads(new_source_raw.decode("utf-8"))["sources"]
    require([row["asset_id"] for row in scene_after][-len(new_rows):] == [row["asset_id"] for row in new_rows] if new_rows else True, "写入后scenes顺序不正确", errors)
    require([row["asset_id"] for row in source_after][old_scene_count:old_scene_count + len(new_source_rows)] == [row["asset_id"] for row in new_source_rows], "写入后source index顺序不正确", errors)
    require([row["asset_id"] for row in source_after][:old_scene_count] == scene_ids, "写入后旧source index顺序变化", errors)
    old_objects_preserved(ledger_raw, new_ledger_raw, route["asset_key"], {row["asset_id"] for row in new_rows}, errors)
    old_objects_preserved(source_raw, new_source_raw, "sources", {row["asset_id"] for row in new_source_rows}, errors)

    target_jsons: dict[str, bytes] = {ledger_rel: new_ledger_raw, source_rel: new_source_raw}
    for rel, raw in desired_views.items():
        if raw != snapshots[rel]:
            target_jsons[rel] = raw
    if not new_rows and not new_source_rows and not changed_views and not new_manifests:
        print(json.dumps({"status": "idempotent", "new_assets": 0, "asset_ids": list(ASSET_IDS)}, ensure_ascii=False, indent=2))
        return 0
    require(len(target_jsons) == 3, f"本轮目标JSON应为3个，实际{len(target_jsons)}个", errors)
    if errors:
        return 2

    target_rels = set(snapshots) & set(target_jsons)
    assert_target_snapshots(snapshots, target_rels, errors)
    for sample_id, bundle in bundles.items():
        selected = formal_files(sample_id, bundle["files"], True, errors)
        for key in ("recipe", "scene", "manifest", "catalog", "ledger"):
            if selected[key].is_file():
                require(selected[key].read_bytes() == bundle["files"][key].read_bytes(), f"写入前正式副本并发变化: {sample_id}/{key}", errors)
    for manifest_path, manifest_value in new_manifests:
        path = ROOT / manifest_path
        require(not path.exists(), f"新manifest已存在，拒绝覆盖: {manifest_path}", errors)
        if path.exists():
            require(path.read_bytes() == dump_json(manifest_value).encode("utf-8"), f"manifest同名内容不同: {manifest_path}", errors)
    if errors:
        return 2

    backup_targets(report_path, {rel: snapshots[rel] for rel in target_jsons}, errors)
    assert_target_snapshots(snapshots, target_rels, errors)
    if errors:
        return 2
    for manifest_path, manifest_value in new_manifests:
        path = ROOT / manifest_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(dump_json(manifest_value).encode("utf-8"))
    (ROOT / ledger_rel).write_bytes(new_ledger_raw)
    (ROOT / source_rel).write_bytes(new_source_raw)
    for rel, raw in desired_views.items():
        if raw != snapshots[rel]:
            (ROOT / rel).write_bytes(raw)
    print(json.dumps({"status": "written", "new_assets": len(new_rows), "asset_ids": list(ASSET_IDS), "backup": path_text(report_path.parent / "registration_backup"), "legacy_records_rehashed": False, "legacy_objects_byte_preserved": True}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
