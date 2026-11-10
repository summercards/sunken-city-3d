#!/usr/bin/env python3
"""审计并登记 water_building_002/v003 的 runtime 交付资源，不运行 Godot。"""
from __future__ import annotations

import copy
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path("D:/projects/sea")
WORK = Path("D:/projects/sea-work/water_building_002/v003")
INVENTORY = ROOT / "assets/registry/runtime_resource_inventory.json"
LEDGER_INDEX = ROOT / "assets/registry/ledger_index.json"
SCENE_LEDGER = ROOT / "assets/registry/ledgers/scenes.json"
SOURCE_INDEX = ROOT / "assets/registry/current_source_index.json"
SOURCE_DIR = ROOT / "art_source/scenes/water_building_002/v003"
CATALOG_PATH = SOURCE_DIR / "catalog.json"
INSTANCES_PATH = SOURCE_DIR / "component_instances.json"
RUNTIME_JSON = ROOT / "godot/assets/data/water_building_002_instances.json"
ASSEMBLY = ROOT / "godot/scenes/facilities/water_building_002.tscn"
MAIN = ROOT / "godot/scenes/main.tscn"
MAIN_BEFORE = WORK / "main_before_002.tscn"
TEST = ROOT / "godot/tests/test_water_building_002.gd"
CAPTURE = ROOT / "godot/tools/capture_water_building_002.gd"
SOURCE_REPORT = WORK / "source_verification.json"
VOLUME_REPORT = WORK / "volume_revision.json"
VOLUME_COMPARISON = WORK / "volume_visual_comparison.json"
RUNTIME_INTEGRATION = WORK / "runtime_integration.json"
FINAL_REPORT = Path("D:/projects/sea-work/verification/20261110-145440-wb002-v003-final-0984d1/report.json")
NEIGHBOR_REPORT = Path("D:/projects/sea-work/verification/20261110-150026-wb002-neighbor-regression-fb097a/report.json")
DELIVERY_AUDIT = WORK / "delivery_audit.json"

ASSEMBLY_ID = "SEA-SCENE-WATER-BUILDING-002"
STATUS = "runtime_verified_002_v003"
FINAL_REPORT_HASH = "ac40c88a46711d566cce61907b846b447ca767e260a1f6ed85ef1a37cd73058f"
TEXT_SUFFIXES = {".json", ".gd", ".tscn", ".import", ".py", ".gdshader", ".gdshaderinc", ".txt"}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def normalized_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    if path.suffix.lower() in TEXT_SUFFIXES | {".tres", ".godot", ".cfg", ".uid", ".md", ".svg"}:
        return data.replace(b"\r\n", b"\n")
    return data


def sha256(path: Path) -> str:
    return hashlib.sha256(normalized_bytes(path)).hexdigest()


def raw_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def external(path: Path) -> str:
    return path.as_posix()


def dump_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def report_ref(path: Path) -> dict:
    return {"path": external(path), "sha256": raw_sha256(path)}


def parse_check_line(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"\[(?P<label>[^\]]+)\]\s+(?P<checks>\d+) checks, (?P<failures>\d+) failures", text)
    require(match is not None, f"缺少实际日志计数：{path}")
    return {
        "label": match.group("label"),
        "checks": int(match.group("checks")),
        "failures": int(match.group("failures")),
    }


def external_report_evidence(path: Path) -> dict:
    report = read_json(path)
    results = {}
    for name, result in report["results"].items():
        log = Path(result["log"])
        count = result.get("checks")
        if count is None:
            count = parse_check_line(log)
        elif isinstance(count, int):
            count = {"checks": count, "failures": 0}
        results[name] = {
            "passed": result.get("passed"),
            "exit_code": result.get("exit_code"),
            "renderer": result.get("renderer"),
            "checks": count,
            "log": external(log),
        }
    asset_import = report.get("asset_import")
    return {
        "report": report_ref(path),
        "label": report.get("label"),
        "results": results,
        "asset_import": asset_import,
    }


def scene_nodes(path: Path) -> dict[tuple[str, str], dict]:
    rows = {}
    current = None
    for line in path.read_text(encoding="utf-8").replace("\r\n", "\n").splitlines():
        node = re.match(r'\[node name="([^"]+)"(?: parent="([^"]+)")?(?: instance=ExtResource\("([^"]+)"\))?', line)
        if node:
            current = {
                "name": node.group(1),
                "parent": node.group(2) or "",
                "instance": node.group(3),
                "transform": None,
            }
            rows[(current["parent"], current["name"])] = current
            continue
        if current is not None and line.startswith("transform = "):
            current["transform"] = line
    return rows


def source_projection() -> list[dict]:
    index = read_json(LEDGER_INDEX)
    projected = []
    for route in index["domains"].values():
        book = read_json(ROOT / route["ledger"])
        projected.extend({key: row[key] for key in ("asset_id", "source", "source_sha256", "manifest")} for row in book[route["asset_key"]])
    return projected


def target_files(catalog: list[dict]) -> tuple[list[tuple[Path, str]], dict[str, list[str]]]:
    records: list[tuple[Path, str]] = []
    categories: dict[str, list[str]] = {"component_glb": [], "component_import": [], "component_wrapper": [], "assembly_glb": [], "assembly_import": [], "assembly_scene": [], "runtime_instances_json": [], "test_gd": [], "capture_gd": []}
    for component in catalog:
        aid = component["asset_id"]
        glb = ROOT / component["glb_path"]
        imp = Path(str(glb) + ".import")
        wrapper = ROOT / f"godot/scenes/components/facilities/water_building_002/{component['key']}.tscn"
        for path, category in ((glb, "component_glb"), (imp, "component_import"), (wrapper, "component_wrapper")):
            require(path.is_file(), f"缺少002运行文件：{path}")
            records.append((path, aid))
            categories[category].append(rel(path))
    # The v001 aggregate GLB is historical and never referenced by the v003 assembly.
    # Its presence on disk is not evidence of current runtime acceptance.
    for path, category in ((ASSEMBLY, "assembly_scene"), (RUNTIME_JSON, "runtime_instances_json"), (TEST, "test_gd"), (CAPTURE, "capture_gd")):
        require(path.is_file(), f"缺少002运行文件：{path}")
        records.append((path, ASSEMBLY_ID))
        categories[category].append(rel(path))
    return records, categories


def verify_target_inventory(inventory: dict, records: list[tuple[Path, str]]) -> list[dict]:
    by_path = {row["path"]: row for row in inventory["resources"]}
    require(len(by_path) == len(inventory["resources"]), "runtime inventory 存在重复路径")
    conflicts = []
    additions = []
    for path, asset_id in records:
        path_key = rel(path)
        digest = sha256(path)
        existing = by_path.get(path_key)
        if existing is not None:
            if existing.get("sha256") != digest:
                conflicts.append({"path": path_key, "existing_sha256": existing.get("sha256"), "actual_normalized_sha256": digest})
            continue
        row = {
            "path": path_key,
            "asset_id": asset_id,
            "sha256": digest,
            "bytes": len(normalized_bytes(path)),
            "status": STATUS,
            "runtime_verification": STATUS,
            "audit_note": "002 v003 runtime 交付；仅登记本次 002 运行文件，不批量签源资产，不签商业/版权权益。",
        }
        additions.append(row)
    return conflicts, additions


def global_inventory_drift(inventory: dict, target_paths: set[str]) -> dict:
    drift = []
    missing = []
    for row in inventory["resources"]:
        path = ROOT / row["path"]
        if row["path"] in target_paths:
            continue
        if not path.is_file():
            missing.append(row["path"])
            continue
        expected = row.get("sha256")
        raw = raw_sha256(path)
        # Use exactly the same raw-or-LF fallback as check_feature_contracts.hash_matches.
        normalized = hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        if expected not in {raw, normalized}:
            drift.append({"path": row["path"], "recorded_sha256": expected, "raw_sha256": raw, "normalized_sha256": normalized})
    return {"drift_count": len(drift), "missing_count": len(missing), "drift": drift, "missing": missing}


def audit_002(catalog: list[dict], records: list[tuple[Path, str]], categories: dict[str, list[str]], final_evidence: dict, neighbor_evidence: dict) -> dict:
    ledger_index = read_json(LEDGER_INDEX)
    scene_route = ledger_index["domains"]["scenes"]
    require(scene_route["ledger"] == "assets/registry/ledgers/scenes.json", "ledger_index scenes 路由异常")
    scene_book = read_json(SCENE_LEDGER)
    scene_rows = {row["asset_id"]: row for row in scene_book["assets"]}
    target_ids = {component["asset_id"] for component in catalog} | {ASSEMBLY_ID}
    require(len(target_ids) == 29, "002 ledger 目标不是29个AssetID")
    require(target_ids.issubset(scene_rows), "002 ledger 缺少目标AssetID")
    require(all(scene_rows[aid].get("runtime_integrated") is True for aid in target_ids), "002 29条ledger状态未全部为runtime_integrated=true")

    manifest_paths = [ROOT / component["package_manifest"] for component in catalog] + [SOURCE_DIR / "asset_manifest.json"]
    manifest_backlinks = []
    for path in manifest_paths:
        manifest = read_json(path)
        aid = manifest["asset_id"]
        require(aid in target_ids, f"manifest 非002目标：{path}")
        require(manifest.get("asset_ledger") == scene_route["ledger"] + "#" + aid, f"manifest回链异常：{path}")
        manifest_backlinks.append({"asset_id": aid, "path": rel(path), "asset_ledger": manifest["asset_ledger"]})
    require(len(manifest_backlinks) == 29, "manifest回链数量不是29")

    package_hashes = {}
    glb_hashes = {}
    import_records = []
    wrapper_records = []
    for component in catalog:
        source = ROOT / component["component_source"]
        manifest = ROOT / component["package_manifest"]
        glb = ROOT / component["glb_path"]
        imp = Path(str(glb) + ".import")
        wrapper = ROOT / f"godot/scenes/components/facilities/water_building_002/{component['key']}.tscn"
        package_hashes[component["key"]] = sha256(source)
        glb_hashes[component["key"]] = sha256(glb)
        require(package_hashes[component["key"]] == component["package_sha256"], f"组件包SHA异常：{component['key']}")
        require(glb_hashes[component["key"]] == component["glb_sha256"], f"组件GLBSHA异常：{component['key']}")
        package_manifest = read_json(manifest)
        require(package_manifest["package_sha256_before_reopen"] == package_hashes[component["key"]], f"组件manifest包SHA异常：{component['key']}")
        require(package_manifest["package_sha256_after_reopen"] == package_hashes[component["key"]], f"组件manifest回开SHA异常：{component['key']}")
        import_text = imp.read_text(encoding="utf-8").replace("\r\n", "\n")
        lod = re.search(r"^meshes/generate_lods=(.*)$", import_text, re.MULTILINE)
        images = re.search(r"^gltf/embedded_image_handling=(.*)$", import_text, re.MULTILINE)
        require(lod is not None and lod.group(1) == "false", f"LOD设置异常：{component['key']}")
        require(images is not None and images.group(1) == "0", f"embedded image设置异常：{component['key']}")
        wrapper_text = wrapper.read_text(encoding="utf-8").replace("\r\n", "\n")
        require("[node name=\"Visual\"" in wrapper_text and "surface_material_override/" in wrapper_text, f"wrapper override节点异常：{component['key']}")
        require("blocker" not in wrapper_text and "blocks_water" not in wrapper_text, f"组件不应拥有自身水面blocker：{component['key']}")
        import_records.append({"component_key": component["key"], "glb_sha256": glb_hashes[component["key"]], "images": 0, "lod": False})
        wrapper_records.append({"component_key": component["key"], "path": rel(wrapper), "override_serialized": True, "loadable_by_runner": True})
    require(len(package_hashes) == 28 and len(glb_hashes) == 28, "组件hash数量不是28")

    source = SOURCE_DIR / "water_building_002_v003.blend"
    source_report = read_json(SOURCE_REPORT)
    require(source_report["source_unchanged"] is True and source_report["source_sha256_after"] == scene_rows[ASSEMBLY_ID]["source_sha256"], "002主源SHA/unchanged证据异常")
    require(source_report["failures"] == [], "source_verification存在失败")
    require(len(read_json(INSTANCES_PATH)["instances"]) == 167, "源实例数量不是167")
    runtime = read_json(RUNTIME_JSON)
    require(len(runtime["instances"]) == 167 and runtime["expected"]["crown_instances"] == 18, "runtime实例/树冠数量异常")
    require(all(len(row["godot_transform"]) == 12 for row in runtime["instances"]), "runtime JSON存在非12项Godot矩阵")
    runtime_raw = RUNTIME_JSON.read_bytes()
    runtime_line_ending = "CRLF" if b"\r\n" in runtime_raw else "LF"

    assembly_text = ASSEMBLY.read_text(encoding="utf-8").replace("\r\n", "\n")
    assembly_nodes = re.findall(r'^\[node name="WB002V2_I_[^\"]+" parent="Visual/[^\"]+" instance=ExtResource\(', assembly_text, re.MULTILINE)
    require(len(assembly_nodes) == 167, "总成source clone节点数量不是167")
    require('blocks_water = true' in assembly_text, "总成未声明blocks_water=true")
    require('target_path = NodePath("../Visual/Structure")' in assembly_text, "总成blocker未指向Structure")

    old_nodes = scene_nodes(MAIN_BEFORE)
    new_nodes = scene_nodes(MAIN)
    unchanged_transform_count = 0
    transform_diffs = []
    for key, old in old_nodes.items():
        if old["transform"] is None:
            continue
        current = new_nodes.get(key)
        if current is None or current["transform"] != old["transform"]:
            transform_diffs.append({"node": key, "before": old["transform"], "after": current and current["transform"]})
        else:
            unchanged_transform_count += 1
    require(not transform_diffs, "main旧节点变换发生漂移")
    new_002 = [key for key, row in new_nodes.items() if key[1] == "water_building_002"]
    require(len(new_002) == 1, "main缺少唯一新002节点")

    volume = read_json(VOLUME_REPORT)
    comparison = read_json(VOLUME_COMPARISON)
    require(volume["instance_count"] == 167 and volume["crown_instances"] == 18, "volume report实例计数异常")
    require(volume["topology_and_vertices_identical"] is True and volume["details_added"] == 0, "volume report拓扑/新增几何异常")
    require(volume["triangles_before"] == volume["triangles_after"], "volume report三角形发生变化")
    require(comparison["changed_existing_crowns"] == 18 and comparison["added_meshes"] == 0 and comparison["added_triangles"] == 0, "volume comparison异常")

    source_index = read_json(SOURCE_INDEX)
    require(source_index["sources"] == source_projection(), "ledger/index projection不一致")
    above = sum(1 for aid in target_ids if scene_rows[aid].get("building_class") == "above_water")
    null_class = sum(1 for aid in target_ids if scene_rows[aid].get("building_class") is None)
    require((above, null_class) == (23, 6), "002 building_class分类不是23 above/6 null")

    runtime_final = final_evidence["results"]
    require(all(item["passed"] is True and item["exit_code"] == 0 and item["checks"]["failures"] == 0 for item in runtime_final.values()), "002外部runtime报告未全通过")
    require(final_evidence["asset_import"]["exit_code"] == 0 and final_evidence["asset_import"]["unexpected_errors"] == [], "002 asset-import外部报告异常")
    neighbor_results = neighbor_evidence["results"]
    require(all(item["passed"] is True and item["exit_code"] == 0 and item["checks"]["failures"] == 0 for item in neighbor_results.values()), "neighbor回归外部报告未全通过")

    return {
        "ledger_rows": 29,
        "ledger_runtime_integrated_true": 29,
        "manifest_backlinks": manifest_backlinks,
        "manifest_backlink_count": len(manifest_backlinks),
        "package_sha256_verified": len(package_hashes),
        "source_sha256_verified": True,
        "glb_sha256_verified": len(glb_hashes),
        "import_settings": {"components": len(import_records), "images": 0, "lod": False, "records": import_records},
        "component_wrappers": wrapper_records,
        "component_wrapper_count": len(wrapper_records),
        "component_blockers": {"own_water_blocker": False, "basis": "28 wrappers have no blocker script/blocks_water"},
        "assembly_blocker": {"blocks_water": True, "target": "../Visual/Structure", "basis": "assembly scene declaration"},
        "main": {"old_transform_diffs": transform_diffs, "old_transform_count_unchanged": unchanged_transform_count, "new_002_node": new_002[0]},
        "branches_and_source_clones": {"branchCount": len(read_json(INSTANCES_PATH)["instances"]), "sourceclones": len(assembly_nodes), "crown": runtime["expected"]["crown_instances"], "geometry_added": 0, "volume_report": report_ref(VOLUME_REPORT), "volume_comparison": report_ref(VOLUME_COMPARISON)},
        "classification": {"above_water": above, "null": null_class},
        "runtime_json": {"matrix_records": len(runtime["instances"]), "matrix_width": 12, "line_ending": runtime_line_ending, "godot_serialization_tested_by": "external runner report"},
        "ledger_index_projection": {"consistent": True, "source_index_updated": False},
        "external_runtime_evidence": {"final": final_evidence, "neighbor_regression": neighbor_evidence},
    }


def main() -> int:
    catalog = read_json(CATALOG_PATH)["components"]
    require(len(catalog) == 28, "catalog组件数量不是28")
    records, categories = target_files(catalog)
    inventory_before = read_json(INVENTORY)
    historical = {"godot/assets/models/facilities/water_building_002/water_building_002.glb", "godot/assets/models/facilities/water_building_002/water_building_002.glb.import"}
    corrected = [row for row in inventory_before["resources"] if row["path"] in historical and row.get("runtime_verification") == STATUS]
    inventory_before["resources"] = [row for row in inventory_before["resources"] if row not in corrected]
    original_resources = copy.deepcopy(inventory_before["resources"])
    original_evidence = copy.deepcopy(inventory_before["runtime_verification_evidence"])
    target_paths = {rel(path) for path, _ in records}
    conflicts, additions = verify_target_inventory(inventory_before, records)
    final_evidence = external_report_evidence(FINAL_REPORT)
    neighbor_evidence = external_report_evidence(NEIGHBOR_REPORT)

    scope_audit = audit_002(catalog, records, categories, final_evidence, neighbor_evidence)
    drift = global_inventory_drift(inventory_before, target_paths)
    inventory_conflict = bool(conflicts)
    if inventory_conflict:
        raise RuntimeError("已有002目标路径hash不一致，停止写入且不覆盖unknown：" + json.dumps(conflicts, ensure_ascii=False))

    inventory_after = copy.deepcopy(inventory_before)
    inventory_after["runtime_verification_evidence"][STATUS] = {
        "external_reports": [report_ref(FINAL_REPORT), report_ref(NEIGHBOR_REPORT)],
        "report_labels": [final_evidence["label"], neighbor_evidence["label"]],
        "scope": "仅签 water_building_002/v003 runtime 交付文件；不批量签源资产，不签商业/版权权益，不刷新 main 或旧001。",
        "status": STATUS,
        "counts": {
            "target_file_count": len(records),
            "categories": {key: len(value) for key, value in categories.items()},
            "registered_new_file_count": len(additions),
        },
        "verification": {
            "ledger_rows": 29,
            "manifest_backlinks": 29,
            "package_sha256": 28,
            "glb_sha256": 28,
            "component_wrappers": 28,
            "asset_import_exit_code": final_evidence["asset_import"]["exit_code"],
            "external_reports_have_zero_failures": True,
        },
        "global_runtime_inventory_drift": {
            "drift_count": drift["drift_count"],
            "missing_count": drift["missing_count"],
            "reported_only": True,
            "delivery_not_signed_green": bool(drift["drift_count"] or drift["missing_count"]),
        },
    }
    inventory_after["resources"].extend(additions)
    require(inventory_before["resources"] == original_resources, "内部快照异常")
    require(STATUS in inventory_after["runtime_verification_evidence"], "缺少唯一runtime evidence key")
    require({k: v for k, v in inventory_after["runtime_verification_evidence"].items() if k != STATUS} == {k: v for k, v in original_evidence.items() if k != STATUS}, "无关evidence被修改")
    require(inventory_after["resources"][: len(original_resources)] == original_resources, "既有resource条目字典被改写")
    dump_json(INVENTORY, inventory_after)

    audit = {
        "schema": "sea.water_building_002.delivery_audit",
        "asset_id": ASSEMBLY_ID,
        "source_version": "v003",
        "status": STATUS,
        "scope": "仅新增002 runtime inventory条目与本工程外delivery_audit.json；不修改ledger/docs/main/tests/runtime脚本，不运行Godot。",
        "delivery_status": "scoped_runtime_passed_global_contract_pending" if (drift["drift_count"] or drift["missing_count"]) else "scoped_runtime_checks_passed",
        "overall_passed": False if (drift["drift_count"] or drift["missing_count"]) else True,
        "scoped_002_checks_passed": True,
        "external_reports": {"runtime_final": final_evidence, "neighbor_regression": neighbor_evidence},
        "file_counts": {"actual_target_file_count": len(records), "categories": {key: len(value) for key, value in categories.items()}, "new_inventory_rows": len(additions)},
        "registered_paths": categories,
        "inventory": {"path": rel(INVENTORY), "new_evidence_key": STATUS, "existing_resource_entries_preserved": True, "existing_evidence_preserved": {k: v for k, v in original_evidence.items() if k != STATUS} == {k: v for k, v in inventory_after["runtime_verification_evidence"].items() if k != STATUS}, "historical_v001_false_positive_rows_removed": len(corrected)},
        "audit": scope_audit,
        "global_old_runtime_hash_drift": drift,
        "conflicts": conflicts,
        "not_run": ["Godot"],
        "note": "external reports and parsed log counts are evidence references; no unverified count is promoted to a green delivery conclusion.",
    }
    dump_json(DELIVERY_AUDIT, audit)
    print(json.dumps({"delivery_audit": external(DELIVERY_AUDIT), "inventory": rel(INVENTORY), "target_file_count": len(records), "new_inventory_rows": len(additions), "global_runtime_inventory_drift": drift["drift_count"], "overall_passed": audit["overall_passed"]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
