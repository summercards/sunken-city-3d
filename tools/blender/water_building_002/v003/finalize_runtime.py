#!/usr/bin/env python3
"""将 water_building_002/v003 的已验证 runtime 证据收敛到 registry。"""
from __future__ import annotations

import copy
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
WORK = Path("D:/projects/sea-work/water_building_002/v003")
RUN_DIR = Path("D:/projects/sea-work/verification/20261110-145440-wb002-v003-final-0984d1")
REPORT_PATH = RUN_DIR / "report.json"
OUTPUT_DIR = RUN_DIR / "project/outputs"
SOURCE_DIR = ROOT / "art_source/scenes/water_building_002/v003"
CATALOG_PATH = SOURCE_DIR / "catalog.json"
EXPORT_PATH = SOURCE_DIR / "export/v003/export_manifest.json"
SOURCE = SOURCE_DIR / "water_building_002_v003.blend"
OPTIMIZED = SOURCE_DIR / "export/v003/water_building_002_optimized_v003.blend"
PALETTE = ROOT / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
LEDGER = ROOT / "assets/registry/ledgers/scenes.json"
SOURCE_INDEX = ROOT / "assets/registry/current_source_index.json"
ABOVE_VIEW = ROOT / "assets/registry/views/buildings_above_water.json"
ASSEMBLY_ID = "SEA-SCENE-WATER-BUILDING-002"
STAGE = "runtime_integrated_user_art_review_pending"
VERSION = "v003"
PENDING = [
    "user_final_art_acceptance",
    "commercial_authorization",
    "global_seams_exhaustive",
    "performance_playtest",
]


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def external(path: Path) -> str:
    return path.as_posix()


def dump_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def parse_check_line(path: Path, label: str) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    pattern = re.compile(rf"\[{re.escape(label)}\]\s+(\d+) checks, (\d+) failures")
    match = pattern.search(text)
    assert match, f"缺少验证计数：{label}"
    return {"checks": int(match.group(1)), "failures": int(match.group(2))}


def import_settings(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    values = {}
    for key in ("meshes/generate_lods", "meshes/create_shadow_meshes", "meshes/ensure_tangents", "materials/extract"):
        match = re.search(rf"^{re.escape(key)}=(.*)$", text, re.MULTILINE)
        assert match, f"缺少 import 设置：{path} {key}"
        values[key] = match.group(1)
    assert values["meshes/generate_lods"] == "false"
    assert values["meshes/create_shadow_meshes"] == "true"
    return values


def command_evidence(report: dict) -> dict:
    results = report["results"]
    return {
        name: {
            "command": result["command"],
            "log": result["log"].replace("\\", "/"),
            "renderer": result["renderer"],
            "exit_code": result["exit_code"],
            "checks": parse_check_line(RUN_DIR / Path(result["log"]).name, {
                "water-building-002": "water-building-002",
                "visual-water-building-002": "water-building-002-render",
                "water-layer": "water-layer",
            }[name]),
        }
        for name, result in results.items()
    }


def main() -> dict:
    for path in (REPORT_PATH, OUTPUT_DIR, SOURCE, OPTIMIZED, PALETTE, LEDGER, SOURCE_INDEX, CATALOG_PATH, EXPORT_PATH):
        assert path.exists(), f"缺少 runtime 输入：{path}"

    report = read_json(REPORT_PATH)
    assert report["asset_import"]["exit_code"] == 0
    assert report["asset_import"]["unexpected_errors"] == []
    for result in report["results"].values():
        assert result["exit_code"] == 0 and result["passed"] is True
        assert result["unexpected_errors"] == [] and result["failure_labels"] == []

    screenshots = []
    for name in ("water-building-002-hero.png", "water-building-002-back.png", "water-building-002-roof.png", "water-building-002-shop-context.png"):
        path = OUTPUT_DIR / name
        assert path.is_file(), f"缺少实际截图：{path}"
        screenshots.append({"path": external(path), "sha256": sha256(path)})
    evidence_path = OUTPUT_DIR / "water-building-002-evidence.json"
    assert evidence_path.is_file()
    evidence = {"path": external(evidence_path), "sha256": sha256(evidence_path)}
    runner_report = {"path": external(REPORT_PATH), "sha256": sha256(REPORT_PATH)}
    commands = command_evidence(report)
    assert commands["water-building-002"]["checks"] == {"checks": 1441, "failures": 0}
    assert commands["visual-water-building-002"]["checks"] == {"checks": 12, "failures": 0}
    assert commands["water-layer"]["checks"] == {"checks": 1794, "failures": 0}

    catalog = read_json(CATALOG_PATH)["components"]
    export = read_json(EXPORT_PATH)
    assert len(catalog) == 28 and len(export["components"]) == 28
    source_hashes = {
        "parent_source_sha256": sha256(SOURCE),
        "optimized_source_sha256": sha256(OPTIMIZED),
        "palette_sha256": sha256(PALETTE),
    }
    assert source_hashes["parent_source_sha256"] == export["source"]["sha256"]
    assert source_hashes["optimized_source_sha256"] == export["optimized"]["sha256"]
    assert source_hashes["palette_sha256"] == read_json(SOURCE_DIR / "component_packages" / catalog[0]["key"] / "asset_manifest.json")["palette_sha256"]
    assert export["source"]["expanded_instances"] == 167
    assert export["source"]["expanded_triangles_depsgraph"] == 10342
    assert export["source"]["expanded_polygons_depsgraph"] == 6293

    source_qa_path = WORK / "source_verification.json"
    source_qa = read_json(source_qa_path)
    assert source_qa["failures"] == [] and source_qa["source_sha256_after"] == source_hashes["parent_source_sha256"]
    optimization_manifest_path = SOURCE_DIR / "export/v003/optimization_manifest.json"
    optimization_records = {}
    for component in catalog:
        key = component["key"]
        item = copy.deepcopy(source_qa["optimized"]["optimization_by_component"][key])
        before_triangles = item["before"]["triangles"]
        after_triangles = item["after"]["triangles"]
        assert after_triangles == export["components"][key]["triangles"]
        item.update({
            "asset_id": component["asset_id"], "version": VERSION,
            "source_path": rel(SOURCE), "source_sha256_before": source_qa["source_sha256_before"],
            "source_sha256_after": source_qa["source_sha256_after"],
            "optimized_path": rel(OPTIMIZED), "optimized_sha256": source_hashes["optimized_source_sha256"],
            "triangles_before": before_triangles, "triangles_after": after_triangles,
            "reduction_ratio": (before_triangles - after_triangles) / before_triangles if before_triangles else None,
            "component_budget": None, "budget_source": "user target approx 10000 per assembled scene; no per-component quotas supplied",
            "glb_path": component["glb_path"], "glb_sha256": component["glb_sha256"],
            "fidelity": {"source_vertices_and_topology": "independently_verified_no_change", "actual_runtime_matrices_materials_triangles": "passed", "visuals": "hero_back_roof_context_reviewed", "user_art_acceptance": "pending"},
        })
        optimization_records[key] = item
    optimization_manifest = {"schema": "sea.component_optimization_manifest", "asset_id": ASSEMBLY_ID, "version": VERSION, "source_report": external(source_qa_path), "source_sha256": source_hashes["parent_source_sha256"], "optimized_sha256": source_hashes["optimized_source_sha256"], "source_protected": True, "palette_protected": True, "components": optimization_records}
    if not optimization_manifest_path.parent.is_dir():
        raise RuntimeError("optimized export parent missing")
    dump_json(optimization_manifest_path, optimization_manifest)

    import_records = []
    component_data = []
    for component in catalog:
        key = component["key"]
        source_path = ROOT / component["component_source"]
        package_manifest_path = ROOT / component["package_manifest"]
        glb_path = ROOT / component["glb_path"]
        prefab_path = ROOT / f"godot/scenes/components/facilities/water_building_002/{key}.tscn"
        import_path = glb_path.with_suffix(glb_path.suffix + ".import")
        assert source_path.is_file() and package_manifest_path.is_file() and glb_path.is_file()
        assert prefab_path.is_file() and import_path.is_file()
        package_hash = sha256(source_path)
        glb_hash = sha256(glb_path)
        assert package_hash == component["package_sha256"] == component["package_sha256_before_reopen"]
        assert package_hash == component["package_sha256_after_reopen"] if "package_sha256_after_reopen" in component else True
        assert glb_hash == component["glb_sha256"] == export["components"][key]["sha256"]
        package_manifest = read_json(package_manifest_path)
        assert package_manifest["package_sha256_before_reopen"] == package_hash
        assert package_manifest["package_sha256_after_reopen"] == package_hash
        assert package_manifest["source_sha256"] == package_hash
        settings = import_settings(import_path)
        import_records.append({
            "component_key": key,
            "asset_id": component["asset_id"],
            "import_path": rel(import_path),
            "glb_path": component["glb_path"],
            "glb_sha256": glb_hash,
            "images": export["components"][key]["images"],
            "lod": settings["meshes/generate_lods"] == "true",
            "shadow_mesh": settings["meshes/create_shadow_meshes"] == "true",
            "settings": settings,
        })
        assert import_records[-1]["images"] == 0 and import_records[-1]["lod"] is False
        component_data.append({
            "component": component,
            "source_path": source_path,
            "manifest_path": package_manifest_path,
            "glb_path": glb_path,
            "prefab_path": prefab_path,
            "package_sha256": package_hash,
            "glb_sha256": glb_hash,
            "prefab_sha256": sha256(prefab_path),
        })

    assembly_prefab = ROOT / "godot/scenes/facilities/water_building_002.tscn"
    assert assembly_prefab.is_file()
    assembly_prefab_sha = sha256(assembly_prefab)
    runtime_integration_path = WORK / "runtime_integration.json"
    runtime_evidence = {
        "runner_report": runner_report,
        "commands": commands,
        "screenshots": screenshots,
        "evidence": evidence,
        "runtime_prefab": {
            "path": rel(assembly_prefab),
            "sha256": assembly_prefab_sha,
        },
        "assembly_model": {
            "type": "28_component_glbs",
            "component_count": 28,
            "glb_paths": [item["glb_path"] for item in import_records],
        },
        "import_settings": {
            "component_count": 28,
            "images": 0,
            "lod": False,
            "records": import_records,
        },
        "verification_summary": {
            "asset_import": {"exit_code": 0, "unexpected_errors": []},
            "water_building_002": {"checks": 1441, "failures": 0},
            "visual_water_building_002": {"checks": 12, "failures": 0, "screenshots": 4},
            "water_layer": {"checks": 1794, "failures": 0},
        },
    }

    ledger_before = read_json(LEDGER)
    source_index_before = read_json(SOURCE_INDEX)
    above_before = read_json(ABOVE_VIEW)
    existing_rows = {row["asset_id"]: row for row in ledger_before["assets"]}
    target_ids = {component["asset_id"] for component in catalog} | {ASSEMBLY_ID}
    assert len(target_ids) == 29
    assert existing_rows["SEA-SCENE-WATER-BUILDING-001"]["runtime_integrated"] is False
    assert existing_rows["SEA-SCENE-WATER-BUILDING-001"]["stage"] == "source_registered_runtime_validation_pending"
    source_index_before_bytes = SOURCE_INDEX.read_bytes()
    source_index_rows = {row["asset_id"]: row for row in source_index_before["sources"]}
    for asset_id in target_ids:
        ledger_row = existing_rows[asset_id]
        index_row = source_index_rows[asset_id]
        assert {key: index_row[key] for key in ("asset_id", "source", "source_sha256", "manifest")} == {
            key: ledger_row[key] for key in ("asset_id", "source", "source_sha256", "manifest")
        }
    assert ASSEMBLY_ID in above_before["asset_ids"]
    assert {component["asset_id"] for component in catalog if component["group"] != "plant"}.issubset(above_before["asset_ids"])

    common_evidence = {
        "optimization_manifest": {"path": rel(optimization_manifest_path), "sha256": sha256(optimization_manifest_path)},
        "runtime_integration": external(runtime_integration_path),
        "runner_report": runner_report,
        "commands": commands,
        "screenshots": screenshots,
        "evidence": evidence,
    }
    updated_manifests = {}
    updated_rows = {}
    for item in component_data:
        component = item["component"]
        key = component["key"]
        asset_id = component["asset_id"]
        instance_count = sum(row["key"] == key for row in read_json(SOURCE_DIR / "component_instances.json")["instances"])
        runtime_path = component["glb_path"]
        prefab = rel(item["prefab_path"])
        flags = {
            "standalone_load": "passed",
            "material": "passed",
            "shadow": "passed",
        }
        item_evidence = {
            **common_evidence,
            "runtime_prefab": {"path": prefab, "sha256": item["prefab_sha256"]},
            "component": {"key": key, "glb_path": runtime_path, "glb_sha256": item["glb_sha256"]},
            "import_settings": next(record for record in import_records if record["component_key"] == key),
        }
        manifest = read_json(item["manifest_path"])
        manifest.update({
            "version": VERSION,
            "instance_count": instance_count,
            "stage": STAGE,
            "consumer_features": ["SEA-ASSET", "SEA-WORLD"],
            "runtime_path": runtime_path,
            "runtime_sha256": item["glb_sha256"],
            "prefab": prefab,
            "runtime_prefab_sha256": item["prefab_sha256"],
            "runtime_integrated": True,
            "runtime": "passed_current_import_and_specialist_tests",
            "runtime_flags": flags,
            "import_settings": {"images": 0, "lod": False, "shadow_mesh": True},
            "collision": "no_actor_n/a",
            "navigation": "assembly_owned_no_component_navigation",
            "water_blocker_validated": False,
            "nav_footprint_collected": False,
            "boat_blocking": "not_applicable_component_no_independent_blocker",
            "boat_route_e2e": "not_run",
            "verification_pending": PENDING,
            "evidence": item_evidence,
            "runtime_manifest_binding": {
                "source": component["component_source"],
                "source_sha256": item["package_sha256"],
                "runtime_path": runtime_path,
                "prefab": prefab,
            },
        })
        updated_manifests[item["manifest_path"]] = manifest

        row = copy.deepcopy(existing_rows[asset_id])
        row.update({
            "version": VERSION,
            "instance_count": instance_count,
            "stage": STAGE,
            "consumer_features": ["SEA-ASSET", "SEA-WORLD"],
            "runtime_path": runtime_path,
            "runtime_sha256": item["glb_sha256"],
            "prefab": prefab,
            "runtime_prefab_sha256": item["prefab_sha256"],
            "runtime_integrated": True,
            "runtime": "passed_current_import_and_specialist_tests",
            "runtime_flags": flags,
            "import_settings": {"images": 0, "lod": False, "shadow_mesh": True},
            "collision": "no_actor_n/a",
            "navigation": "assembly_owned_no_component_navigation",
            "water_blocker_validated": False,
            "nav_footprint_collected": False,
            "boat_blocking": "not_applicable_component_no_independent_blocker",
            "boat_route_e2e": "not_run",
            "verification_pending": PENDING,
            "evidence": item_evidence,
            "runtime_manifest_binding": {
                "source": component["component_source"],
                "source_sha256": item["package_sha256"],
                "runtime_path": runtime_path,
                "prefab": prefab,
            },
        })
        updated_rows[asset_id] = row

    assembly_manifest_path = SOURCE_DIR / "asset_manifest.json"
    assembly_manifest_before = read_json(assembly_manifest_path)
    assembly_evidence = {
        **common_evidence,
        "runtime_prefab": {"path": rel(assembly_prefab), "sha256": assembly_prefab_sha},
        "assembly_model": runtime_evidence["assembly_model"],
        "import_settings": runtime_evidence["import_settings"],
    }
    assembly_manifest = copy.deepcopy(assembly_manifest_before)
    assembly_manifest.update({
        "version": VERSION,
        "stage": STAGE,
        "consumer_features": ["SEA-ASSET", "SEA-WORLD"],
        "runtime_path": rel(assembly_prefab),
        "prefab": rel(assembly_prefab),
        "runtime_sha256": assembly_prefab_sha,
        "runtime_prefab_sha256": assembly_prefab_sha,
        "runtime_integrated": True,
            "runtime": "passed_current_import_and_specialist_tests",
        "runtime_flags": {"standalone_load": "passed", "material": "passed", "shadow": "passed", "component_glbs": 28},
        "runtime_components": runtime_evidence["assembly_model"]["glb_paths"],
        "collision": "no_actor_n/a",
        "water_blocker_validated": True,
        "nav_footprint_collected": True,
        "boat_blocking": "passed",
        "navigation": "boat_blocking_passed_end_to_end_boatroute_pending",
        "boat_route_e2e": "not_run",
        "verification_pending": PENDING,
        "evidence": assembly_evidence,
        "runtime_manifest_binding": {
            "source": rel(SOURCE),
            "source_sha256": source_hashes["parent_source_sha256"],
            "runtime_path": rel(assembly_prefab),
            "prefab": rel(assembly_prefab),
        },
    })
    updated_rows[ASSEMBLY_ID] = copy.deepcopy(existing_rows[ASSEMBLY_ID])
    updated_rows[ASSEMBLY_ID].update({
        "version": VERSION,
        "stage": STAGE,
        "consumer_features": ["SEA-ASSET", "SEA-WORLD"],
        "runtime_path": rel(assembly_prefab),
        "prefab": rel(assembly_prefab),
        "runtime_sha256": assembly_prefab_sha,
        "runtime_prefab_sha256": assembly_prefab_sha,
        "runtime_integrated": True,
            "runtime": "passed_current_import_and_specialist_tests",
        "runtime_flags": {"standalone_load": "passed", "material": "passed", "shadow": "passed", "component_glbs": 28},
        "runtime_components": runtime_evidence["assembly_model"]["glb_paths"],
        "collision": "no_actor_n/a",
        "water_blocker_validated": True,
        "nav_footprint_collected": True,
        "boat_blocking": "passed",
        "navigation": "boat_blocking_passed_end_to_end_boatroute_pending",
        "boat_route_e2e": "not_run",
        "verification_pending": PENDING,
        "evidence": assembly_evidence,
        "runtime_manifest_binding": {
            "source": rel(SOURCE),
            "source_sha256": source_hashes["parent_source_sha256"],
            "runtime_path": rel(assembly_prefab),
            "prefab": rel(assembly_prefab),
        },
    })

    ledger_after = copy.deepcopy(ledger_before)
    for row in ledger_after["assets"]:
        asset_id = row["asset_id"]
        if asset_id in updated_rows:
            row.clear()
            row.update(updated_rows[asset_id])
    unrelated_before = {aid: copy.deepcopy(row) for aid, row in existing_rows.items() if aid not in target_ids}
    unrelated_after = {row["asset_id"]: row for row in ledger_after["assets"] if row["asset_id"] not in target_ids}
    assert unrelated_before == unrelated_after
    assert ledger_after["assets"]

    target_files = [LEDGER, assembly_manifest_path, *updated_manifests]
    before_bytes = {path: path.read_bytes() for path in target_files}
    protected_hashes = {
        SOURCE: source_hashes["parent_source_sha256"],
        OPTIMIZED: source_hashes["optimized_source_sha256"],
        PALETTE: source_hashes["palette_sha256"],
    }
    protected_hashes.update({item["source_path"]: item["package_sha256"] for item in component_data})
    protected_hashes.update({item["glb_path"]: item["glb_sha256"] for item in component_data})
    for path, expected in protected_hashes.items():
        assert sha256(path) == expected, f"写入前源/包/GLB哈希变化：{path}"
    assert SOURCE_INDEX.read_bytes() == source_index_before_bytes
    assert existing_rows["SEA-SCENE-WATER-BUILDING-001"] == {row["asset_id"]: row for row in ledger_after["assets"]}["SEA-SCENE-WATER-BUILDING-001"]

    dump_json(LEDGER, ledger_after)
    for path, value in updated_manifests.items():
        dump_json(path, value)
    dump_json(assembly_manifest_path, assembly_manifest)
    dump_json(runtime_integration_path, runtime_evidence)

    assert SOURCE_INDEX.read_bytes() == source_index_before_bytes
    for path, expected in protected_hashes.items():
        assert sha256(path) == expected, f"写入后源/包/GLB哈希变化：{path}"
    ledger_written = read_json(LEDGER)
    rows_written = {row["asset_id"]: row for row in ledger_written["assets"]}
    assert len(rows_written) == 1027
    assert sum(1 for asset_id in target_ids if rows_written[asset_id]["runtime_integrated"] is True) == 29
    assert rows_written["SEA-SCENE-WATER-BUILDING-001"]["runtime_integrated"] is False
    assert {aid: rows_written[aid] for aid in unrelated_before} == unrelated_before
    assert all(read_json(path)["runtime_integrated"] is True for path in updated_manifests)
    assert read_json(assembly_manifest_path)["runtime_integrated"] is True

    final_report = {
        "passed": True,
        "conclusion_written": False,
        "registered_rows": 29,
        "component_rows": 28,
        "assembly_rows": 1,
        "unrelated_changes": 0,
        "unrelated_ledger_rows": len(unrelated_before),
        "ledger_rows_after": len(rows_written),
        "source_index_written": False,
        "source_index_four_fields_asserted": True,
        "source_hashes": source_hashes,
        "package_hashes_verified": 28,
        "glb_hashes_verified": 28,
        "runtime_prefab_hashes_verified": 29,
        "import_settings_verified": {"components": 28, "images": 0, "lod": False},
        "verification": runtime_evidence["verification_summary"],
        "stage": STAGE,
        "version": VERSION,
        "navigation": "boat_blocking_passed_end_to_end_boatroute_pending",
        "verification_pending": PENDING,
        "001_runtime_integrated": False,
        "target_files": [rel(LEDGER), rel(assembly_manifest_path), *[rel(path) for path in updated_manifests]],
        "w3_runtime_integration": external(runtime_integration_path),
        "before_write_snapshots": {rel(path): hashlib.sha256(data).hexdigest() for path, data in before_bytes.items()},
    }
    dump_json(WORK / "runtime_integration_registration.json", final_report)
    print(json.dumps(final_report, ensure_ascii=False, sort_keys=True))
    return final_report


if __name__ == "__main__":
    main()
