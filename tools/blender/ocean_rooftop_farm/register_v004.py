"""准备并按门禁登记 ocean_rooftop_farm/v004；默认只做预检，不写入登记文件。"""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / "art_source/scenes/ocean_rooftop_farm/v004"
CATALOG_PATH = SOURCE_DIR / "component_catalog.json"
PLAN_PATH = SOURCE_DIR / "component_plan.json"
INSTANCES_PATH = SOURCE_DIR / "component_instances.json"
UPGRADE_STATES_PATH = SOURCE_DIR / "upgrade_states.json"
ASSEMBLY_SOURCE = SOURCE_DIR / "ocean_rooftop_farm_v004.blend"
BASE_BUILDING_SOURCE = SOURCE_DIR / "base_building.blend"
QA_DIR = ROOT.parent / "sea-work/ocean_rooftop_farm/v004"
SOURCE_QA_PATH = QA_DIR / "source_verification.json"
SKILL_QA_PATH = QA_DIR / "skill_verification.json"
LEDGER_INDEX_PATH = ROOT / "assets/registry/ledger_index.json"
SOURCE_INDEX_PATH = ROOT / "assets/registry/current_source_index.json"
BASE_BUILDING_MANIFEST_PATH = SOURCE_DIR / "base_building_asset_manifest.json"
PREFIX = "SEA-SCENE-ORF2-"
ASSEMBLY_ID = "SEA-SCENE-ORF2-ASSEMBLY"
BASE_BUILDING_ID = "SEA-SCENE-ORF2-BASE-BUILDING"
SOURCE_VERIFICATION_LABEL = "passed_source_and_skill_verification"
REMOVED_KEYS = {"bed", "field", "cabbage", "seedling", "tomato", "greenhouse", "tank"}
UPGRADE_KEYS = {
    "greenhouse_unbuilt",
    "greenhouse_complete",
    "water_tower_unbuilt",
    "water_tower_complete",
}
SUPERSEDED_BY = {
    "SEA-SCENE-ORF2-GREENHOUSE": [
        "SEA-SCENE-ORF2-GREENHOUSE_UNBUILT",
        "SEA-SCENE-ORF2-GREENHOUSE_COMPLETE",
    ],
    "SEA-SCENE-ORF2-TANK": [
        "SEA-SCENE-ORF2-WATER_TOWER_UNBUILT",
        "SEA-SCENE-ORF2-WATER_TOWER_COMPLETE",
    ],
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def rel(path):
    return path.relative_to(ROOT).as_posix()


def source_row(record):
    return {key: record[key] for key in ["asset_id", "source", "source_sha256", "manifest"]}


def require_file(path, label):
    if not path.is_file():
        raise AssertionError(f"缺少{label}：{path}")


def component_record(component, package, manifest_path, package_sha, previous, upgrade):
    record = {
        "asset_id": component["asset_id"],
        "name": component["name"],
        "domain": "scenes",
        "stage": "source_verified_runtime_pending",
        "source": rel(package),
        "source_sha256": package_sha,
        "manifest": rel(manifest_path),
        "version": "v004",
        "runtime_path": None,
        "prefab": None,
        "license": "pending_user_reference_rights_review",
        "geometry_fingerprint": component.get("geometry_fingerprint"),
        "consumer_features": ["SEA-ASSET"],
        "category": component["category"],
        "building_class": "above_water",
        "water_layer": "surface",
        "water_layer_role": "part",
        "scope": "scene_local",
        "source_verification": SOURCE_VERIFICATION_LABEL,
        "verification_pending": [
            "Godot",
            "collision",
            "commercial_authorization",
            "final_art_review",
        ],
        "note": (
            "海上屋顶农场 v004 45组件；移除屋顶菜畦、作物及主屋顶6块太阳能，"
            "保留上层露台2块太阳能；greenhouse/tank 改为四个独立升级状态。"
        ),
    }
    if upgrade is not None:
        record.update(
            {
                "upgrade_family": upgrade["family"],
                "upgrade_state": upgrade["state"],
                "upgrade_pair": upgrade["upgrade_id"],
                "upgrade_pair_asset_ids": upgrade["asset_ids"],
                "game_logic_pending": True,
                "verification_pending": record["verification_pending"] + ["game_logic"],
            }
        )
    if previous is not None:
        history = list(previous.get("previous_sources", []))
        history.append(
            {
                key: previous[key]
                for key in ["source", "source_sha256", "manifest", "version"]
                if key in previous
            }
        )
        record["previous_sources"] = history
    return record


def assembly_record(source_sha, manifest_path, plan, instances, previous):
    record = {
        "asset_id": ASSEMBLY_ID,
        "name": "六十米海上屋顶农场 v004",
        "domain": "scenes",
        "stage": "source_verified_runtime_pending",
        "source": rel(ASSEMBLY_SOURCE),
        "source_sha256": source_sha,
        "manifest": rel(manifest_path),
        "version": "v004",
        "runtime_path": None,
        "prefab": None,
        "license": "pending_user_reference_rights_review",
        "geometry_fingerprint": None,
        "consumer_features": ["SEA-ASSET"],
        "category": "scene_assembly",
        "building_class": "above_water",
        "water_layer": "surface",
        "water_layer_role": "entity",
        "scope": "scene_local",
        "runtime_status": "pending",
        "source_verification": SOURCE_VERIFICATION_LABEL,
        "verification_pending": [
            "Godot",
            "collision",
            "navigation",
            "game_logic",
            "commercial_authorization",
            "final_art_review",
        ],
        "note": (
            "v004 主总成；catalog仅计45个组件，不计base building assembly；"
            "四个升级状态由upgrade_states.json成对切换，默认unbuilt，game logic pending。"
        ),
    }
    if previous is not None:
        history = list(previous.get("previous_sources", []))
        history.append(
            {
                key: previous[key]
                for key in ["source", "source_sha256", "manifest", "version"]
                if key in previous
            }
        )
        record["previous_sources"] = history
    return record


def base_building_record(source_sha, manifest_path):
    return {
        "asset_id": BASE_BUILDING_ID,
        "name": "海上屋顶农场独立主楼 v004",
        "domain": "scenes",
        "stage": "source_verified_runtime_pending",
        "source": rel(BASE_BUILDING_SOURCE),
        "source_sha256": source_sha,
        "manifest": rel(manifest_path),
        "version": "v004",
        "runtime_path": None,
        "prefab": None,
        "license": "pending_user_reference_rights_review",
        "geometry_fingerprint": None,
        "consumer_features": ["SEA-ASSET"],
        "category": "scene_component",
        "component_family": "base_building",
        "building_class": "above_water",
        "water_layer": "surface",
        "water_layer_role": "part",
        "scope": "scene_local",
        "assembly_id": ASSEMBLY_ID,
        "catalog_counted": False,
        "upgrade_states_excluded": True,
        "source_verification": SOURCE_VERIFICATION_LABEL,
        "verification_pending": [
            "Godot",
            "collision",
            "navigation",
            "commercial_authorization",
            "final_art_review",
        ],
        "note": "独立base building源；不计入45组件catalog，不包含greenhouse/water_tower四个升级态。",
    }


def upgrade_by_asset_id(upgrade_states):
    result = {}
    for pair in upgrade_states["pairs"]:
        asset_ids = [state["asset_id"] for state in pair["states"].values()]
        for state, entry in pair["states"].items():
            result[entry["asset_id"]] = {
                "upgrade_id": pair["upgrade_id"],
                "family": pair["family"],
                "state": state,
                "asset_ids": asset_ids,
            }
    return result


def validate_upgrade_states(upgrade_states, catalog_ids, instance_ids):
    assert upgrade_states.get("schema") == "sea.upgrade_asset_states"
    assert upgrade_states.get("source_only") is True
    assert upgrade_states.get("default_state") == "unbuilt"
    pairs = upgrade_states.get("pairs")
    assert isinstance(pairs, list) and len(pairs) == 2, "升级组不是2组"
    seen = set()
    for pair in pairs:
        assert pair["default_state"] == "unbuilt"
        assert pair["state_switch"] == "mutually_exclusive_replace_only"
        assert pair["runtime_logic"] == "pending_no_cost_or_production_rules_changed"
        assert pair["socket_world_blender"][2] == 60.05
        assert pair["socket_world_godot"][1] == 60.05
        assert set(pair["states"]) == {"unbuilt", "complete"}
        ids = {entry["asset_id"] for entry in pair["states"].values()}
        assert ids <= catalog_ids
        assert not seen & ids
        seen |= ids
    assert seen == {
        PREFIX + key.upper().replace("_", "_") for key in UPGRADE_KEYS
    }
    assert not (seen & instance_ids), "主总成实例清单不应直接导出四个升级态"
    constraints = set(upgrade_states.get("constraints", []))
    assert "Only one state for each family may be visible/exported at runtime" in constraints
    assert "Building base export excludes all four upgrade state meshes" in constraints


def validate_old_49(ledger_rows, source_rows):
    old_rows = [row for row in ledger_rows if str(row.get("asset_id", "")).startswith(PREFIX)]
    assert len(old_rows) == 49, f"现有ORF旧登记不是49条：{len(old_rows)}"
    assert len({row["asset_id"] for row in old_rows}) == 49, "现有ORF旧登记存在重复AssetID"
    indexed = {row["asset_id"]: row for row in source_rows if str(row.get("asset_id", "")).startswith(PREFIX)}
    assert len(indexed) == 49, f"current_source_index中的ORF旧索引不是49条：{len(indexed)}"
    for old in old_rows:
        asset_id = old["asset_id"]
        assert asset_id in indexed, f"current_source_index缺少旧记录：{asset_id}"
        assert source_row(old) == source_row(indexed[asset_id]), f"账本与来源索引不一致：{asset_id}"
        old_source = str(old["source"]).replace("\\", "/")
        old_path = ROOT / old_source
        require_file(old_path, f"旧记录源文件 {asset_id}")
        actual = sha256(old_path)
        assert actual == old["source_sha256"], f"旧源哈希漂移：{asset_id} -> {old_source}"
    return {row["asset_id"]: row for row in old_rows}


def validate_v004_inputs():
    require_file(LEDGER_INDEX_PATH, "ledger_index.json")
    require_file(SOURCE_INDEX_PATH, "current_source_index.json")
    ledger_index = read_json(LEDGER_INDEX_PATH)
    source_index = read_json(SOURCE_INDEX_PATH)
    route = ledger_index["domains"]["scenes"]
    ledger_path = ROOT / route["ledger"]
    require_file(ledger_path, "scenes ledger")
    ledger = read_json(ledger_path)
    rows = ledger[route["asset_key"]]
    old_by_id = validate_old_49(rows, source_index["sources"])

    for path, label in [
        (CATALOG_PATH, "v004 component_catalog.json"),
        (PLAN_PATH, "v004 component_plan.json"),
        (INSTANCES_PATH, "v004 component_instances.json"),
        (UPGRADE_STATES_PATH, "v004 upgrade_states.json"),
        (ASSEMBLY_SOURCE, "v004 主源"),
        (BASE_BUILDING_SOURCE, "v004 base building源"),
        (SOURCE_QA_PATH, "source_verification.json"),
        (SKILL_QA_PATH, "skill_verification.json"),
    ]:
        require_file(path, label)

    plan = read_json(PLAN_PATH)
    catalog = read_json(CATALOG_PATH)["components"]
    instances = read_json(INSTANCES_PATH)["instances"]
    upgrade_states = read_json(UPGRADE_STATES_PATH)
    source_qa = read_json(SOURCE_QA_PATH)
    skill_qa = read_json(SKILL_QA_PATH)

    assert plan["version"] == "v004"
    assert plan["design_clause"] == "SEA-ASSET-R41"
    assert plan["component_budget"]["planned"] == 45
    assert plan["component_budget"]["limit"] == 50
    assert plan["building_class"] == "above_water"
    assert plan["scope_contract"]["game_logic"] == "pending_not_changed"
    assert set(plan["scope_contract"]["remove"]) >= {
        "roof bed frames and soil",
        "outdoor crops",
        "inside-greenhouse crops",
        "six solar panels on main grass roof",
    }
    assert set(plan["scope_contract"]["keep"]) >= {"two upper-terrace solar panels not circled"}
    assert set(plan["scope_contract"]["upgrade_pairs"]) == {"greenhouse", "water_tower"}

    assert len(catalog) == 45, f"v004组件数不是45：{len(catalog)}"
    catalog_ids = {component["asset_id"] for component in catalog}
    catalog_keys = {component["key"] for component in catalog}
    assert len(catalog_ids) == 45 and len(catalog_keys) == 45
    assert all(asset_id.startswith(PREFIX) for asset_id in catalog_ids)
    assert ASSEMBLY_ID not in catalog_ids and BASE_BUILDING_ID not in catalog_ids
    assert not catalog_keys & REMOVED_KEYS
    assert UPGRADE_KEYS <= catalog_keys
    assert sum(component["key"] == "solar" for component in catalog) == 1
    solar = next(component for component in catalog if component["key"] == "solar")
    assert solar["instance_count"] == 2

    instance_ids = {entry["component_id"] for entry in instances}
    validate_upgrade_states(upgrade_states, catalog_ids, instance_ids)
    upgrade_map = upgrade_by_asset_id(upgrade_states)

    assert source_qa.get("passed") is True, "source_verification.json 未通过"
    assert skill_qa.get("passed") is True, "skill_verification.json 未通过"
    assert source_qa.get("source_sha256") == sha256(ASSEMBLY_SOURCE), "v004主源哈希不匹配"
    skill_rows = skill_qa.get("components")
    assert isinstance(skill_rows, list) and len(skill_rows) == 45, "skill_verification.json组件数不是45"
    assert all(row.get("passed") is True for row in skill_rows), "存在未通过的技能验证组件"
    skill_by_id = {row.get("asset_id"): row for row in skill_rows if row.get("asset_id")}

    for component in catalog:
        key = component["key"]
        expected = SOURCE_DIR / "component_packages" / key / f"{key}.blend"
        actual_source = ROOT / component["component_source"].replace("\\", "/")
        assert actual_source == expected, f"组件源路径不是v004独立包：{key}"
        require_file(expected, f"组件包 {key}")
        package_sha = sha256(expected)
        assert component.get("source_sha256") == package_sha, f"组件包哈希不匹配：{key}"
        skill_row = skill_by_id.get(component["asset_id"])
        if skill_row is not None:
            if skill_row.get("source_sha256") is not None:
                assert skill_row["source_sha256"] == package_sha, f"技能验证包哈希不匹配：{key}"
            if skill_row.get("source") is not None:
                assert str(skill_row["source"]).replace("\\", "/") == rel(expected), f"技能验证包路径不匹配：{key}"
        if key in UPGRADE_KEYS:
            assert component["asset_id"] in upgrade_map

    old_by_id = validate_old_49(rows, source_index["sources"])
    old_component_keys = {key for key in catalog_keys if key not in UPGRADE_KEYS}
    expected_replaced_ids = {
        PREFIX + key.upper() for key in old_component_keys
    } | {component["asset_id"] for component in catalog if component["asset_id"] not in old_by_id}
    assert len(expected_replaced_ids) == 45

    return {
        "plan": plan,
        "catalog": catalog,
        "instances": instances,
        "upgrade_states": upgrade_states,
        "upgrade_map": upgrade_map,
        "source_qa": source_qa,
        "skill_qa": skill_qa,
        "ledger_index": ledger_index,
        "source_index": source_index,
        "ledger_path": ledger_path,
        "ledger": ledger,
        "old_by_id": old_by_id,
        "old_rows": rows,
    }


def manifest_for_component(component, package, package_sha, route):
    manifest_path = package.parent / "asset_manifest.json"
    old_manifest = read_json(manifest_path) if manifest_path.is_file() else {}
    if old_manifest.get("source_sha256") is not None:
        assert old_manifest["source_sha256"] == package_sha, f"组件manifest哈希不匹配：{component['key']}"
    manifest = dict(old_manifest)
    manifest.update(
        {
            "schema": "sea.scene.component_manifest",
            "asset_id": component["asset_id"],
            "name": component["name"],
            "asset_ledger": route["ledger"] + "#" + component["asset_id"],
            "source": rel(package),
            "source_sha256": package_sha,
            "version": "v004",
            "category": component["category"],
            "component_family": component["component_family"],
            "building_class": "above_water",
            "water_layer": "surface",
            "water_layer_role": "part",
            "scope": "scene_local",
            "source_verification": SOURCE_VERIFICATION_LABEL,
            "license": "pending_user_reference_rights_review",
        }
    )
    return manifest_path, manifest


def execute(preflight):
    plan = preflight["plan"]
    catalog = preflight["catalog"]
    instances = preflight["instances"]
    upgrade_states = preflight["upgrade_states"]
    source_qa = preflight["source_qa"]
    ledger_index = preflight["ledger_index"]
    source_index = preflight["source_index"]
    ledger_path = preflight["ledger_path"]
    ledger = preflight["ledger"]
    old_by_id = preflight["old_by_id"]
    rows = preflight["old_rows"]
    route = ledger_index["domains"]["scenes"]
    source_sha = sha256(ASSEMBLY_SOURCE)
    base_sha = sha256(BASE_BUILDING_SOURCE)

    route_records = []
    for component in catalog:
        package = ROOT / component["component_source"].replace("\\", "/")
        package_sha = sha256(package)
        manifest_path, manifest = manifest_for_component(component, package, package_sha, route)
        write_json(manifest_path, manifest)
        route_records.append(
            component_record(
                component,
                package,
                manifest_path,
                package_sha,
                old_by_id.get(component["asset_id"]),
                preflight["upgrade_map"].get(component["asset_id"]),
            )
        )

    assembly_manifest_path = SOURCE_DIR / "asset_manifest.json"
    assembly_manifest = {
        "schema": "sea.scene.assembly_manifest",
        "asset_id": ASSEMBLY_ID,
        "name": "六十米海上屋顶农场 v004",
        "asset_ledger": route["ledger"] + "#" + ASSEMBLY_ID,
        "source": rel(ASSEMBLY_SOURCE),
        "source_sha256": source_sha,
        "version": "v004",
        "category": "scene_assembly",
        "building_class": "above_water",
        "water_layer": "surface",
        "water_layer_role": "entity",
        "runtime_status": "pending",
        "source_verification": SOURCE_VERIFICATION_LABEL,
        "license": "pending_user_reference_rights_review",
        "component_catalog": "component_catalog.json",
        "component_plan": "component_plan.json",
        "component_instances": "component_instances.json",
        "upgrade_states": "upgrade_states.json",
        "base_building_asset_id": BASE_BUILDING_ID,
        "catalog_excludes_base_building": True,
        "component_count": len(catalog),
        "instance_count": len(instances),
        "default_upgrade_state": "unbuilt",
        "game_logic_pending": True,
        "excluded": plan["excluded"],
        "verification_pending": [
            "Godot",
            "collision",
            "navigation",
            "game_logic",
            "commercial_authorization",
            "final_art_review",
        ],
        "revision_summary": [
            "移除屋顶菜畦、作物、温室内作物及主屋顶6块太阳能",
            "保留未圈出的上层露台2块太阳能",
            "greenhouse/tank替换为两组四个独立upgrade state，socket Z=60.05，默认unbuilt",
            "基础建筑导出不含四个升级态，base building独立登记且不计入catalog assembly",
        ],
        "note": "v004 不执行Godot接入或game logic；仅在源级与技能级验证通过后登记。",
    }
    if source_qa.get("reference_sha256") is not None:
        reference_path = SOURCE_DIR / plan["reference"]
        require_file(reference_path, "v004参考图")
        assert source_qa["reference_sha256"] == sha256(reference_path), "参考图哈希不匹配"
        assembly_manifest["reference"] = plan["reference"]
        assembly_manifest["reference_sha256"] = source_qa["reference_sha256"]
    write_json(assembly_manifest_path, assembly_manifest)
    route_records.append(
        assembly_record(source_sha, assembly_manifest_path, plan, instances, old_by_id.get(ASSEMBLY_ID))
    )

    base_manifest = {
        "schema": "sea.scene.component_manifest",
        "asset_id": BASE_BUILDING_ID,
        "name": "海上屋顶农场独立主楼 v004",
        "asset_ledger": route["ledger"] + "#" + BASE_BUILDING_ID,
        "source": rel(BASE_BUILDING_SOURCE),
        "source_sha256": base_sha,
        "version": "v004",
        "category": "scene_component",
        "component_family": "base_building",
        "building_class": "above_water",
        "water_layer": "surface",
        "water_layer_role": "part",
        "scope": "scene_local",
        "assembly_id": ASSEMBLY_ID,
        "catalog_counted": False,
        "upgrade_states_excluded": True,
        "source_verification": SOURCE_VERIFICATION_LABEL,
        "license": "pending_user_reference_rights_review",
    }
    write_json(BASE_BUILDING_MANIFEST_PATH, base_manifest)
    route_records.append(base_building_record(base_sha, BASE_BUILDING_MANIFEST_PATH))

    target_ids = {record["asset_id"] for record in route_records}
    by_id = {record["asset_id"]: record for record in route_records}
    retained = []
    for row in rows:
        if row["asset_id"] in SUPERSEDED_BY:
            row = dict(row)
            row["superseded_by"] = SUPERSEDED_BY[row["asset_id"]]
        if row["asset_id"] not in target_ids:
            retained.append(row)
    ledger[route["asset_key"]] = retained
    ledger[route["asset_key"]].extend(by_id[component["asset_id"]] for component in catalog)
    ledger[route["asset_key"]].append(by_id[ASSEMBLY_ID])
    ledger[route["asset_key"]].append(by_id[BASE_BUILDING_ID])
    write_json(ledger_path, ledger)

    new_source_rows = {record["asset_id"]: source_row(record) for record in route_records}
    source_rows = []
    seen = set()
    for row in source_index["sources"]:
        asset_id = row["asset_id"]
        if asset_id in target_ids:
            if asset_id not in seen:
                source_rows.append(new_source_rows[asset_id])
                seen.add(asset_id)
        else:
            source_rows.append(row)
    for asset_id in [component["asset_id"] for component in catalog] + [ASSEMBLY_ID, BASE_BUILDING_ID]:
        if asset_id not in seen:
            source_rows.append(new_source_rows[asset_id])
            seen.add(asset_id)
    assert len({row["asset_id"] for row in source_rows}) == len(source_rows)
    source_index["sources"] = source_rows
    write_json(SOURCE_INDEX_PATH, source_index)

    print(
        json.dumps(
            {
                "registered_components": len(catalog),
                "registered_assembly": ASSEMBLY_ID,
                "registered_base_building": BASE_BUILDING_ID,
                "source_suite_records": len(catalog) + 2,
                "version": "v004",
                "source_verification": "passed",
                "skill_verification": "passed",
                "old_49_hashes_checked": True,
                "historical_crop_bed_field_rows_preserved": True,
                "superseded_greenhouse_tank_rows_preserved": True,
                "unrelated_source_index_rows_preserved": True,
            },
            ensure_ascii=False,
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true", help="在全部门禁通过后写入登记与来源索引")
    parser.add_argument("--confirm-final", action="store_true", help="确认v004主源及组件包最终稳定")
    args = parser.parse_args()
    if args.execute and not args.confirm_final:
        parser.error("执行登记必须同时提供 --confirm-final；默认不执行登记")
    preflight = validate_v004_inputs()
    if not args.execute:
        print(
            json.dumps(
                {
                    "ready_for_registration": True,
                    "registration_executed": False,
                    "version": "v004",
                    "planned_component_records": 45,
                    "planned_source_suite_records": 47,
                    "old_49_hashes_checked": True,
                },
                ensure_ascii=False,
            )
        )
        return
    execute(preflight)


if __name__ == "__main__":
    main()
