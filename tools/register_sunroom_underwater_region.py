#!/usr/bin/env python3
"""阳光房独立水下总成登记：默认只读计划，--write 仅新增本轮白名单。

不执行Godot、Blender或sync/check；不生成建筑视图。仅新增本轮源和运行白名单，证据晋升严格核对隔离报告及副本哈希。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ASSET_ID = "SEA-SCENE-SUNROOM-UNDERWATER-REGION"
SCENE = "godot/scenes/underwater/sunroom_region.tscn"
ECOLOGY = "godot/scenes/underwater/sunroom_region/ecology.tscn"
SOURCE_PATHS = (
    SCENE, ECOLOGY, "godot/src/diving/sunroom_region.gd",
    "godot/src/ambient/sunroom_underwater_ecology.gd",
    "godot/shaders/sunroom_underwater_surface.gdshader",
    "godot/shaders/sunroom_underwater_lamp.gdshader",
)
MANIFEST = "assets/registry/manifests/scene_components/sea-scene-sunroom-underwater-region.json"
INDEX = "assets/registry/ledger_index.json"
SOURCE_INDEX = "assets/registry/current_source_index.json"
POLICY = "tools/apply_water_layer.py"
DOCUMENT = "docs/development/2026-11-07_sunroom_underwater_region.md"
POLICY_ANCHOR = "def classify(asset_id):\n"
POLICY_ADDITION = (
    "    # 独立水下预览总成：不承担海上建筑空间职责。\n"
    f"    if asset_id == '{ASSET_ID}':\n"
    "        return 'none', 'none'\n"
)


def require(ok, message):
    if not ok:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def project_path(relative):
    path = (ROOT / relative).resolve()
    require(path.is_relative_to(ROOT), "路径越出工程：" + relative)
    return path


def text(raw):
    return raw.decode("utf-8-sig")


def dumps(value):
    return json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)


def splice_array(raw, key, row, position):
    """只插入一个数组元素，既有JSON字节不重排、不重新序列化。"""
    source = text(raw)
    decoder = json.JSONDecoder()
    cursor = source.index("{") + 1
    while True:
        while source[cursor].isspace() or source[cursor] == ',':
            cursor += 1
        require(source[cursor] != '}', "缺少顶层数组：" + key)
        name, cursor = decoder.raw_decode(source, cursor)
        while source[cursor].isspace():
            cursor += 1
        require(source[cursor] == ':', "无效JSON键")
        cursor += 1
        while source[cursor].isspace():
            cursor += 1
        start = cursor
        value, end = decoder.raw_decode(source, start)
        if name == key:
            break
        cursor = end
    require(isinstance(value, list) and 0 <= position <= len(value), "数组或插入位置无效")
    cursor = start + 1
    spans = []
    for _ in value:
        while source[cursor].isspace() or source[cursor] == ',':
            cursor += 1
        item_start = cursor
        _, cursor = decoder.raw_decode(source, cursor)
        spans.append((item_start, cursor))
    newline = "\r\n" if b"\r\n" in raw else "\n"
    encoded = dumps(row).replace("\n", newline + "    ")
    if not spans:
        source = source[:start + 1] + newline + "    " + encoded + newline + "  " + source[end - 1:]
    elif position == len(spans):
        at = spans[-1][1]
        source = source[:at] + "," + newline + "    " + encoded + source[at:]
    else:
        at = spans[position][0]
        source = source[:at] + encoded + "," + newline + "    " + source[at:]
    expected = json.loads(text(raw))
    expected[key].insert(position, row)
    require(json.loads(source) == expected, "精确插入后语义不符")
    return (b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b"") + source.encode("utf-8")


def register(write, evidence_path=None):
    before = {}

    def read(relative, optional=False):
        path = project_path(relative)
        require(optional or path.is_file(), "缺少输入：" + relative)
        raw = path.read_bytes() if path.exists() else None
        require(path not in before or before[path] == raw, "读取期间输入变化：" + relative)
        before[path] = raw
        return raw

    index = json.loads(read(INDEX))
    route = index["domains"]["scenes"]
    ledger_relative, asset_key = route["ledger"], route["asset_key"]
    ledger_raw = read(ledger_relative)
    book = json.loads(ledger_raw)
    rows = book[asset_key]
    require(isinstance(rows, list), "scenes路由不是资产数组")
    all_ids = {}
    for domain, routing in index["domains"].items():
        domain_book = book if domain == "scenes" else json.loads(read(routing["ledger"]))
        for row in domain_book[routing["asset_key"]]:
            aid = row["asset_id"]
            require(aid not in all_ids, "跨域重复AssetID：" + aid)
            all_ids[aid] = (domain, row)
    authored = [{"path": path, "sha256": digest(read(path))} for path in SOURCE_PATHS]
    require(project_path(DOCUMENT).is_file(), "缺少本轮开发说明")
    reused_ids = ["SEA-SCENE-SCITY-ASSEMBLY", "SEA-SCENE-SCITY-SEABED",
                  "SEA-SCENE-BLB-ASSEMBLY", "SEA-DECO-ANIMAL-FISH-SCHOOL",
                  "SEA-SCENE-SCITY-STREET-LAMP", "SEA-SCENE-GKS-DECK-LIGHT",
                  "SEA-SCENE-GKS-SPOTLIGHT"]
    require(all(aid in all_ids for aid in reused_ids), "复用AssetID缺失，须先人工审阅")
    validation = {name: "pending" for name in (
        "source_review", "runtime", "visual", "performance", "user_art_acceptance",
        "commercial_rights", "original_provenance", "reuse_optimization_evidence_consistency")}
    evidence = None
    if evidence_path:
        evidence_file = Path(evidence_path).resolve()
        evidence = json.loads(evidence_file.read_text(encoding="utf-8"))
        for key in ("sunroom-underwater", "visual-sunroom-underwater"):
            result = evidence["results"][key]
            require(result["passed"] and result["exit_code"] == 0 and not result["unexpected_errors"], "运行证据未通过: " + key)
        snapshot = evidence_file.parent / "project"
        for item in authored:
            tested = snapshot / Path(item["path"]).relative_to("godot")
            require(tested.is_file() and digest(tested.read_bytes()) == item["sha256"], "当前源与隔离验收不一致: " + item["path"])
        validation["runtime"] = "passed_standalone_only"
        validation["visual"] = "captured_and_reviewed_standalone_only_user_acceptance_pending"
    row = {
        "asset_id": ASSET_ID, "source_id": "SRC-" + ASSET_ID,
        "name": "阳光房下独立水下区域（含生态子装配）", "domain": "scenes", "version": "v001",
        "stage": "source_scene_registered_runtime_final_pending",
        "source": SCENE, "source_sha256": authored[0]["sha256"],
        "source_paths": list(SOURCE_PATHS), "authored_files": authored,
        "source_type": "native_Godot_assembly_and_baked_geometry_reuse_no_new_blend_or_GLB",
        "manifest": MANIFEST, "prefab": SCENE, "prefab_sha256": authored[0]["sha256"],
        "runtime_path": SCENE, "runtime_sha256": authored[0]["sha256"],
        "classification": {"category": "decoration", "subcategory": "underwater_region_assembly"},
        "building_class": None, "water_layer": "none", "water_layer_role": "none",
        "placement_water_layer": "submerged", "visual_only": True,
        "collision": False, "interactive": False, "blocks_actor": False, "blocks_water": False,
        "walkable": False, "has_landing": False, "navigation_obstacle": False,
        "resource_output": False, "gameplay_state": False, "shoreline_source": False,
        "standalone_only": True, "production_route_integrated": False, "runtime_verified": evidence is not None,
        "consumer_features": ["SEA-DIVE", "SEA-AMBIENT", "SEA-ASSET"],
        "license": "pending_legacy_and_user_reference_rights_review",
        "commercial_rights_status": "pending", "reference_rights_verified": False,
        "validation": validation, "verification": [], "development_record": DOCUMENT,
        "reused_asset_ids": reused_ids,
        "reused_prefabs": ["godot/scenes/world/sunken_city.tscn", "godot/scenes/world/sunken_seabed.tscn",
                           "godot/scenes/facilities/solar_cabin_submerged_base.tscn"],
        "ecology": {"prefab": ECOLOGY, "source_script": SOURCE_PATHS[3],
                    "coral_definition_count": 12, "coral_cluster_count": 32,
                    "fish_group_count": 8, "fish_count": 138,
                    "light_assembly_count": 24, "street_lamp_count": 8, "deck_light_count": 8,
                    "spotlight_fixture_count": 8, "omni_count": 16, "spot_count": 8,
                    "local_light_shadow_count": 0,
                    "coral_source_paths": ["godot/assets/baked/underwater/" + name for name in
                                           ("scene.json", "geoms.bin", "geoms_idx.bin", "instances.bin")],
                    "coral_provenance": "旧web baked reef原株小单体几何提取，不是新Blender模型"},
        "dimensions": {"city_logical_xz": [240, 240], "terrain_xz": [1024, 1024],
                       "water_plane_xz": [1280, 1280], "water_level": 1.12,
                       "city_root_y": 43.487442, "lowest_seabed_y": -62.0,
                       "maximum_seabed_depth_m": 63.12, "actual_city_geometry_bounds": None,
                       "actual_city_geometry_bounds_status": "pending_parent_runtime_test",
                       "base_transform": [1.4501, 0, 0, 0, 1, 0, 0, 0, 1.4308, -1.5113, -0.3, 1.5988]},
        "blend": None, "optimized_blend": None, "glb_export": None,
        "optimization": {"mode": "existing_formal_resource_reuse_no_new_export",
                         "evidence_consistency": "pending", "round_02b_signed": False},
        "note": "独立运行证据与生产接入分开；9来源不变、未接生产；既有源hash/优化许可均不重签。",
        "standalone_verification_report": str(Path(evidence_path).resolve()) if evidence_path else None,
    }
    if evidence is not None:
        row["stage"] = "standalone_runtime_verified_provenance_and_production_pending"
        row["verification"] = ["sunroom-underwater", "visual-sunroom-underwater"]
        observed = json.loads((Path(evidence_path).parent / "project/outputs/sunroom-underwater-report.json").read_text(encoding="utf-8"))
        row["dimensions"]["actual_city_geometry_bounds"] = observed["city_bounds"]
        row["dimensions"]["actual_city_geometry_bounds_status"] = "observed_standalone"
    manifest = dict(row, asset_ledger=ledger_relative + "#" + ASSET_ID)
    source_raw = read(SOURCE_INDEX)
    sources = json.loads(source_raw)["sources"]
    projected = {key: row[key] for key in ("asset_id", "source", "source_sha256", "manifest")}
    plans = {}
    old = all_ids.get(ASSET_ID)
    if old:
        require(old == ("scenes", row), "总成已登记且内容/哈希不同；禁止覆盖或隐式晋升")
        require(sum(item["asset_id"] == ASSET_ID for item in sources) == 1
                and next(item for item in sources if item["asset_id"] == ASSET_ID) == projected,
                "已有总成的来源索引不一致，须人工审阅")
    else:
        require(not any(item["asset_id"] == ASSET_ID for item in sources), "来源索引存在孤立同ID")
        plans[project_path(ledger_relative)] = splice_array(ledger_raw, asset_key, row, len(rows))
        scene_ids = [item["asset_id"] for item in rows]
        positions = [i for i, item in enumerate(sources) if item["asset_id"] in set(scene_ids)]
        require([sources[i]["asset_id"] for i in positions] == scene_ids,
                "现有scenes来源索引缺行/顺序漂移；拒绝全量重建")
        require(not positions or positions == list(range(positions[0], positions[-1] + 1)),
                "scenes来源行不连续，拒绝猜测插入点")
        at = positions[-1] + 1 if positions else 0
        plans[project_path(SOURCE_INDEX)] = splice_array(source_raw, "sources", projected, at)
    manifest_raw = read(MANIFEST, optional=True)
    if manifest_raw is None:
        plans[project_path(MANIFEST)] = (dumps(manifest) + "\n").encode("utf-8")
    else:
        require(json.loads(manifest_raw) == manifest, "manifest已存在且不同；不覆盖父线程证据")
    policy_raw = read(POLICY)
    newline = "\r\n" if b"\r\n" in policy_raw else "\n"
    policy = text(policy_raw).replace("\r\n", "\n")
    if POLICY_ANCHOR + POLICY_ADDITION not in policy:
        require(ASSET_ID not in policy and policy.count(POLICY_ANCHOR) == 1,
                "分类规则已有不同定义或入口不唯一，拒绝覆盖")
        anchor = POLICY_ANCHOR.replace("\n", newline).encode()
        addition = POLICY_ADDITION.replace("\n", newline).encode()
        plans[project_path(POLICY)] = policy_raw.replace(anchor, anchor + addition, 1)
    # Only the newly authored runtime files; never refresh existing fingerprints.
    runtime_relative = index["runtime_inventory"]
    runtime_raw = read(runtime_relative)
    runtime_rows = json.loads(runtime_raw)["resources"]
    runtime_result = runtime_raw
    for item in authored:
        existing_runtime = next((entry for entry in runtime_rows if entry["path"] == item["path"]), None)
        new_runtime = {"path":item["path"], "bytes":project_path(item["path"]).stat().st_size,
                       "sha256":item["sha256"], "asset_id":ASSET_ID,
                       "status":"standalone_verified_production_and_rights_pending" if evidence is not None else "source_registered_runtime_pending"}
        if existing_runtime is not None:
            require(existing_runtime == new_runtime, "新增文件运行登记已存在且不同: " + item["path"])
        else:
            runtime_result = splice_array(runtime_result, "resources", new_runtime, len(runtime_rows))
            runtime_rows.append(new_runtime)
    if runtime_result != runtime_raw: plans[project_path(runtime_relative)] = runtime_result
    allowed = {project_path(path) for path in (ledger_relative, SOURCE_INDEX, MANIFEST, POLICY, runtime_relative)}
    require(set(plans) <= allowed, "写入越出白名单")
    staged, committed = {}, []

    def unchanged():
        for path, expected in before.items():
            if path in committed:
                expected = plans[path]
            actual = path.read_bytes() if path.exists() else None
            require(actual == expected, "并行修改，停止登记：" + path.relative_to(ROOT).as_posix())

    try:
        unchanged()
        if write:
            for path, data in plans.items():
                require(path.parent.is_dir(), "写入父目录不存在：" + str(path.parent))
                with tempfile.NamedTemporaryFile(dir=path.parent, prefix="." + path.name + ".", delete=False) as stream:
                    staged[path] = Path(stream.name)
                    stream.write(data)
                    stream.flush()
                    os.fsync(stream.fileno())
            # 每次替换前检查全部读取快照；遇到并行变化只停止，不回滚覆盖他人新内容。
            for path in plans:
                unchanged()
                os.replace(staged[path], path)
                committed.append(path)
            unchanged()
        print(dumps({"mode": "write" if write else "dry_run", "asset_id": ASSET_ID,
                     "registration_changes": [p.relative_to(ROOT).as_posix() for p in plans],
                     "runtime_inventory_written": write and runtime_result != runtime_raw, "building_views_written": False,
                     "verification_status": validation["runtime"], "production_route_integrated": False}))
    except Exception:
        if committed:
            print("登记中断；以下文件已写，请父线程核对，未强制回滚：" +
                  ", ".join(p.relative_to(ROOT).as_posix() for p in committed), file=sys.stderr)
        raise
    finally:
        for path in staged.values():
            path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="显式写入新增总成、manifest、source index、精确分类规则及新增运行白名单")
    parser.add_argument("--evidence", type=Path, help="隔离runner最终报告；严格核对本轮源文件副本哈希")
    args = parser.parse_args()
    try:
        register(args.write, args.evidence)
    except (ValueError, KeyError, TypeError, OSError) as error:
        print("登记阻断：" + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
