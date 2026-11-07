#!/usr/bin/env python3
"""阳光房水下 v002 定向升级；默认只读，永不执行 runner、sync 或全量哈希刷新。

--baseline 必须是父流程修改前的 baseline.json，含 protected/protected_files/
protected_sources/protected_hashes/baseline70 之一（70项路径→SHA256），以及旧源和
既有 region 测试的 old fingerprints。指纹可为 SHA 字符串或含 sha256 的记录；
新增文件允许 null。不会用当前磁盘补造 before。--before-project 可指定旧 Godot
副本，否则从 v001 的 standalone_verification_report 同级 project 读取旧6源和测试。
--evidence 指定最终 runner report.json，同级 project 必须逐字节匹配全部源和2测试。
--backup-dir 仅 --write 必需，必须是已存在的工程外目录；一次升级只有一个备份事务。
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile

sys.dont_write_bytecode = True

from register_sunroom_underwater_region import (
    ASSET_ID, ROOT, SCENE, MANIFEST, INDEX, SOURCE_INDEX,
    SOURCE_PATHS as ORIGINAL_PATHS, digest, dumps, require, splice_array, text,
)

DOCUMENT = "docs/development/2026-11-07_sunroom_underwater_art_r2.md"
MAIN = "godot/scenes/main.tscn"
SOURCE_PATHS = ORIGINAL_PATHS + (
    "godot/scenes/underwater/sunroom_region/atmosphere.tscn",
    "godot/src/ambient/sunroom_underwater_atmosphere.gd",
    "godot/src/diving/sunroom_region_collision.gd",
    "godot/shaders/sunroom_underwater_palette.gdshader",
    "godot/shaders/sunroom_underwater_beam.gdshader",
    "godot/shaders/sunroom_underwater_particles.gdshader",
    "godot/shaders/sunroom_underwater_sky.gdshader",
    "godot/shaders/sunroom_underwater_fog.gdshader",
    "godot/shaders/sunroom_underwater_color.gdshaderinc",
)
SOURCE_GLOBS = (
    "godot/shaders/sunroom_underwater_*.gdshader",
    "godot/shaders/sunroom_underwater_*.gdshaderinc",
    "godot/src/ambient/sunroom_underwater_*.gd",
    "godot/src/diving/sunroom_underwater_*.gd",
)
TEST_PATHS = (
    "godot/tests/test_sunroom_underwater_region.gd",
    "godot/tests/test_sunroom_underwater_collision.gd",
)
CHECKS = ("sunroom-underwater", "sunroom-collision", "visual-sunroom-underwater")
OLD_HASHES = dict(zip(ORIGINAL_PATHS, (
    "90e19265ec577c105ba7b094fdb9b6d89fdd1dee2518d6edfce1c794639582ad",
    "d2faa187ba6365374ca0abe8bbc2746da4931631c79d9749a0ce3aaf5b31a6b1",
    "4fc446dcb8feb06047189d8fcd32814473c15779b78a2f5dc34e9a37eb08278f",
    "0439e248fdfd9ed3ee3b47bac8c68ebbd810833986732024067472a9cca8e26e",
    "e1565ca9cb4df5d26bab81af96daea975359de834aa3d0bb36d06d9df1e33a47",
    "017fd6d8ddda58dccd8aa9129ecf5db88a2a6f0bc778f5ac2ad677b95c03dfd1",
)))
MAP_NAMES = ("zone1", "zone2", "zone3", "zone4", "zone5", "sea_supply",
             "rooftop_ranch", "resident_harbor", "neon_garden_quarter")
PROTECTED_REQUIRED = {
    MAIN, "godot/src/diving/dive_map_catalog.gd",
    "godot/scenes/world/sunken_city.tscn", "godot/scenes/world/sunken_seabed.tscn",
    "godot/scenes/facilities/solar_cabin_submerged_base.tscn",
    *("godot/scenes/underwater/maps/" + name + ".tscn" for name in MAP_NAMES),
}
SHA = re.compile(r"[0-9a-f]{64}\Z")


def relative_path(value):
    value = str(value).replace("\\", "/")
    if value.startswith("res://"):
        value = "godot/" + value[6:]
    candidate = Path(value)
    if candidate.is_absolute():
        require(candidate.resolve().is_relative_to(ROOT), "baseline 路径不在工程：" + value)
        value = candidate.resolve().relative_to(ROOT).as_posix()
    require(value and not value.startswith("/") and ":" not in value
            and ".." not in Path(value).parts, "不安全相对路径：" + value)
    return value


def project_path(relative):
    path = (ROOT / relative_path(relative)).resolve()
    require(path.is_relative_to(ROOT), "路径越出工程：" + str(relative))
    return path


def fingerprints(value):
    """读取父 baseline 的嵌套指纹；冲突或缺失绝不以现值回填。"""
    found = {}

    def add(path, item):
        name = relative_path(path)
        if isinstance(item, dict):
            item = item.get("sha256")
        require(item is None or isinstance(item, str) and SHA.fullmatch(item),
                "baseline 指纹无效：" + name)
        require(name not in found or found[name] == item, "baseline 多个旧指纹冲突：" + name)
        found[name] = item

    def walk(node):
        if isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, dict):
            if "path" in node and "sha256" in node:
                add(node["path"], node)
                return
            for key, item in node.items():
                if "/" in key or "\\" in key:
                    if item is None or isinstance(item, str) and SHA.fullmatch(item) \
                            or isinstance(item, dict) and "sha256" in item:
                        add(key, item)
                        continue
                if isinstance(item, (dict, list)):
                    walk(item)
    walk(value)
    return found


def array_spans(raw, key):
    source = text(raw)
    decoder = json.JSONDecoder()
    cursor = source.index("{") + 1
    while True:
        while source[cursor].isspace() or source[cursor] == ",":
            cursor += 1
        require(source[cursor] != "}", "缺少顶层数组：" + key)
        name, cursor = decoder.raw_decode(source, cursor)
        while source[cursor].isspace():
            cursor += 1
        require(source[cursor] == ":", "无效 JSON 键")
        cursor += 1
        while source[cursor].isspace():
            cursor += 1
        start = cursor
        values, end = decoder.raw_decode(source, start)
        if name == key:
            break
        cursor = end
    require(isinstance(values, list), "目标不是数组：" + key)
    cursor = start + 1
    spans = []
    for _ in values:
        while source[cursor].isspace() or source[cursor] == ",":
            cursor += 1
        begin = cursor
        _, cursor = decoder.raw_decode(source, cursor)
        spans.append((begin, cursor))
    return source, values, spans


def replace_entry(raw, key, position, row):
    source, values, spans = array_spans(raw, key)
    if values[position] == row:
        return raw
    begin, end = spans[position]
    newline = "\r\n" if b"\r\n" in raw else "\n"
    encoded = dumps(row).replace("\n", newline + "    ")
    updated = source[:begin] + encoded + source[end:]
    expected = json.loads(text(raw))
    expected[key][position] = row
    require(json.loads(updated) == expected, "条目替换后语义不符")
    # 显式证明其余元素原始字节未被重新序列化。
    result = (b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b"") + updated.encode("utf-8")
    after_source, _, after_spans = array_spans(result, key)
    for i, (left, right) in enumerate(spans):
        if i != position:
            a, b = after_spans[i]
            require(source[left:right] == after_source[a:b], "非目标元素字节变化")
    return result


def one(rows, key, value, optional=False):
    matches = [(i, row) for i, row in enumerate(rows) if row.get(key) == value]
    require(len(matches) == 1 or optional and not matches, "缺失或重复条目：" + value)
    return matches[0] if matches else (None, None)


class Inputs:
    def __init__(self):
        self.before = {}

    def read(self, path):
        path = Path(path).resolve()
        require(path.is_file(), "缺少输入：" + str(path))
        raw = path.read_bytes()
        require(path not in self.before or digest(self.before[path]) == digest(raw),
                "读取期间输入变化：" + str(path))
        self.before[path] = raw
        return raw

    def project(self, relative):
        return self.read(project_path(relative))

    def unchanged(self, committed=None):
        committed = committed or {}
        for path, before in self.before.items():
            expected = committed.get(path, before)
            require(path.is_file() and digest(path.read_bytes()) == digest(expected),
                    "并发 SHA guard 失败：" + str(path))


def discover_sources():
    paths = set(SOURCE_PATHS)
    for pattern in SOURCE_GLOBS:
        paths.update(path.relative_to(ROOT).as_posix() for path in ROOT.glob(pattern) if path.is_file())
    require(len(paths) >= 15, "缺少原6与本轮9源文件")
    return list(SOURCE_PATHS) + sorted(paths - set(SOURCE_PATHS))


def snapshot_file(snapshot, relative, protected_shared=False):
    lexical = snapshot / Path(relative).relative_to("godot")
    path = lexical.resolve()
    if protected_shared and not path.is_relative_to(snapshot):
        # The runner intentionally junctions immutable assets/terrain to the
        # original project. Permit only the identical protected source path for
        # read-only hashing, never authored files and never another location.
        require(path == project_path(relative), "受保护runner共享路径不符：" + relative)
    else:
        require(path.is_relative_to(snapshot), "隔离副本路径越界：" + relative)
    return path


def verify_protected(inputs, baseline, snapshot, paths):
    groups = [baseline[key] for key in (
        "protected", "protected_files", "protected_sources", "protected_hashes", "baseline70")
        if key in baseline]
    require(len(groups) == 1, "baseline 必须唯一指定70项保护集合，不能猜测保护范围")
    protected = fingerprints(groups[0])
    require(len(protected) == 70 and PROTECTED_REQUIRED <= protected.keys(),
            "baseline70 缺失或未覆盖 Main/原9图/catalog/city/seabed/base")
    require(not (set(paths) | set(TEST_PATHS)) & protected.keys(), "保护集合混入本轮可变源")
    require(all(SHA.fullmatch(value or "") for value in protected.values()), "保护项必须有旧 SHA")
    require(any(p.endswith(".glb") for p in protected)
            and any(p.startswith("godot/terrain/") for p in protected), "保护集合缺少 GLB/terrain")
    for relative, expected in protected.items():
        if relative == MAIN:
            continue
        require(digest(inputs.project(relative)) == expected, "受保护来源漂移：" + relative)
        if relative.startswith("godot/"):
            require(digest(inputs.read(snapshot_file(snapshot, relative, protected_shared=True))) == expected,
                    "验收副本受保护来源漂移：" + relative)
    # 保护边界只认父流程冻结的70项，不扩大为全工程依赖扫描或全量运行哈希。
    return protected


def commit_transaction(inputs, plans, old_sources, backup_dir, guard):
    backup_dir = backup_dir.resolve()
    require(backup_dir.is_dir() and not backup_dir.is_relative_to(ROOT), "备份父目录须已存在且在工程外")
    lock = backup_dir / ("sunroom-r2-" + digest(str(ROOT).encode())[:16] + ".lock")
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    staged, committed = {}, {}
    transaction = None
    try:
        os.close(descriptor)
        guard()
        transaction = Path(tempfile.mkdtemp(prefix="sunroom-underwater-v002-", dir=backup_dir))
        journal = {"asset_id": ASSET_ID, "state": "prepared", "files": []}
        for path, data in plans.items():
            relative = path.relative_to(ROOT).as_posix()
            saved = transaction / "registry_before" / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_bytes(inputs.before[path])
            require(digest(saved.read_bytes()) == digest(inputs.before[path]), "事务备份校验失败")
            journal["files"].append({"path": relative, "before": digest(inputs.before[path]), "after": digest(data)})
        for relative, raw in old_sources.items():
            saved = transaction / "source_before" / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            saved.write_bytes(raw)
            require(digest(saved.read_bytes()) == digest(raw), "旧源回滚副本校验失败：" + relative)
        journal_path = transaction / "transaction.json"
        with journal_path.open("xb") as stream:
            stream.write((dumps(journal) + "\n").encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        for path, data in plans.items():
            require(path.parent.is_dir(), "登记父目录不存在")
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix="." + path.name + ".r2-", delete=False) as stream:
                staged[path] = Path(stream.name)
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
        for path in plans:
            guard(committed)
            os.replace(staged[path], path)
            committed[path] = plans[path]
        guard(committed)
        journal["state"] = "committed"
        journal_path.write_bytes((dumps(journal) + "\n").encode("utf-8"))
        return str(transaction)
    except BaseException:
        # 只撤回仍等于本事务 after 的文件；绝不覆盖其他写入者的新字节。
        conflicts = []
        for path in reversed(list(committed)):
            try:
                require(path.is_file() and digest(path.read_bytes()) == digest(committed[path]), "回滚目标已并发变化")
                with tempfile.NamedTemporaryFile(dir=path.parent, prefix="." + path.name + ".rollback-", delete=False) as stream:
                    temporary = Path(stream.name)
                    staged[path] = temporary
                    stream.write(inputs.before[path])
                    stream.flush()
                    os.fsync(stream.fileno())
                require(digest(path.read_bytes()) == digest(committed[path]), "回滚前目标已变化")
                os.replace(temporary, path)
            except (ValueError, OSError):
                conflicts.append(str(path))
        if transaction:
            print("事务中断，工程外回滚备份：" + str(transaction), file=sys.stderr)
            if (transaction / "transaction.json").is_file():
                journal["state"] = "rollback_conflicts" if conflicts else "rolled_back"
                journal["rollback_conflicts"] = conflicts
                try:
                    (transaction / "transaction.json").write_bytes((dumps(journal) + "\n").encode("utf-8"))
                except OSError as journal_error:
                    print("事务日志更新失败：" + str(journal_error), file=sys.stderr)
        if conflicts:
            print("以下并发文件未强制回滚：" + ", ".join(conflicts), file=sys.stderr)
        raise
    finally:
        for path in staged.values():
            path.unlink(missing_ok=True)
        lock.unlink(missing_ok=True)


def register(args):
    inputs = Inputs()
    baseline_path, evidence_path = args.baseline.resolve(), args.evidence.resolve()
    require(not baseline_path.is_relative_to(ROOT) and not evidence_path.is_relative_to(ROOT),
            "baseline/evidence 必须位于工程外")
    baseline_raw = inputs.read(baseline_path)
    baseline = json.loads(baseline_raw)
    old_fingerprints = fingerprints(baseline)
    evidence_raw = inputs.read(evidence_path)
    evidence = json.loads(evidence_raw)
    for key in CHECKS:
        result = evidence["results"][key]
        require(result.get("passed") is True and type(result.get("exit_code")) is int
                and result["exit_code"] == 0 and result.get("unexpected_errors") == [],
                "最终 runner 证据未通过：" + key)
    snapshot = (evidence_path.parent / "project").resolve()
    require(snapshot.is_dir() and not snapshot.is_relative_to(ROOT), "最终隔离 project 不存在或位于工程内")
    paths = discover_sources()
    authored, tested = [], {}
    for relative in paths + list(TEST_PATHS):
        raw = inputs.project(relative)
        final_raw = inputs.read(snapshot_file(snapshot, relative))
        require(digest(final_raw) == digest(raw) and final_raw == raw,
                "源与 final project SHA/逐字节不一致：" + relative)
        tested[relative] = {"path": relative, "sha256": digest(raw)}
        if relative in paths:
            authored.append(tested[relative])
    protected = verify_protected(inputs, baseline, snapshot, paths)
    document = text(inputs.project(DOCUMENT))
    require("Main" in document and "并行" in document
            and any(note in document for note in ("不要求 Main", "Main 不要求", "Main字节不变不作", "Main 字节不变不作")),
            "开发记录须说明 Main 可能被并行修改、不要求 Main 字节不变；本工具不代写文档")
    index = json.loads(inputs.project(INDEX))
    route = index["domains"]["scenes"]
    ledger_relative, asset_key = route["ledger"], route["asset_key"]
    require(ledger_relative == "assets/registry/ledgers/scenes.json" and asset_key == "assets",
            "scenes 路由变化，须重新审阅")
    ledger_raw = inputs.project(ledger_relative)
    book = json.loads(ledger_raw)
    row_position, current_row = one(book[asset_key], "asset_id", ASSET_ID)
    for domain, routing in index["domains"].items():
        if domain != "scenes":
            rows = json.loads(inputs.project(routing["ledger"]))[routing["asset_key"]]
            require(not any(row.get("asset_id") == ASSET_ID for row in rows), "跨域重复目标 AssetID")
    manifest_raw = inputs.project(MANIFEST)
    current_manifest = json.loads(manifest_raw)
    require(current_manifest == dict(current_row, asset_ledger=ledger_relative + "#" + ASSET_ID),
            "资产行与 manifest 不一致，禁止 blind refresh")
    upgraded = current_row["version"] == "v002"
    require(current_row["version"] in ("v001", "v002"), "仅接受 v001→v002")
    if upgraded:
        history = current_row.get("history", [])
        require(history and history[-1].get("transition") == "sunroom_underwater_art_r2_v001_to_v002",
                "v002 缺少本工具原始历史，拒绝接管")
        previous = history[-1]["manifest"]
    else:
        previous = current_manifest
    require(previous["version"] == "v001" and previous["source"] == SCENE
            and previous["asset_id"] == ASSET_ID and previous["source_paths"] == list(ORIGINAL_PATHS),
            "旧 manifest 不符合原6源契约")
    old_authored = previous["authored_files"]
    require(len(old_authored) == 6 and {item["path"]: item["sha256"] for item in old_authored} == OLD_HASHES,
            "原6登记 hash 不等于已审 v001 manifest")
    for relative, expected in OLD_HASHES.items():
        require(old_fingerprints.get(relative) == expected, "baseline 旧指纹不等于 old manifest：" + relative)
    before_project = (args.before_project.resolve() if args.before_project else
                      (Path(previous["standalone_verification_report"]).parent / "project").resolve())
    require(before_project.is_dir() and not before_project.is_relative_to(ROOT), "缺少工程外旧 project 回滚源")
    old_sources = {}
    for relative, expected in OLD_HASHES.items():
        raw = inputs.read(snapshot_file(before_project, relative))
        require(digest(raw) == expected, "旧回滚源不等于 old manifest：" + relative)
        old_sources[relative] = raw
    # 既有 region 测试即使未在 runtime 登记，也必须有真实可核 before。
    region_test = TEST_PATHS[0]
    require(SHA.fullmatch(old_fingerprints.get(region_test) or ""), "baseline 缺少既有 region 测试 before")
    for relative in TEST_PATHS:
        expected = old_fingerprints.get(relative)
        if expected is not None:
            raw = inputs.read(snapshot_file(before_project, relative))
            require(digest(raw) == expected, "测试 before 副本不匹配：" + relative)
            old_sources[relative] = raw
    observed = json.loads(inputs.read(snapshot / "outputs/sunroom-underwater-report.json"))
    collision = json.loads(inputs.read(snapshot / "outputs/sunroom-collision-report.json"))
    require(collision.get("failures") == 0 and collision.get("failure_labels") == [], "碰撞明细失败")
    stats = collision["colliderstats"]
    require(stats["proxy_count"] == 758 and collision["proxy_count"] == 758
            and stats["cached_shapes"] >= stats["unique_meshes"] and stats["triangles"] == 3_115_351,
            "碰撞规模不符合758 proxy/有效形状缓存/3115351展开三角契约")
    # Headless physics test samples orthogonalized matrices on a different
    # startup ordering than real-render captures; exact float Basis keys may
    # split extra caches (observed 99 vs158), not alter per-instance geometry.
    for key in ("proxy_count", "triangles", "unique_meshes", "roles", "assemblies", "empty_meshes"):
        require(observed["blocking"][key] == stats[key], "区域与碰撞报告几何统计不一致：" + key)
    air = observed["atmosphere"]
    require((air["bubble_instances"], air["mote_instances"], air["beam_instances"]) == (192, 200, 10),
            "氛围数量不符合192泡/200尘/10射光")
    fog = observed["fog"]
    require(all(math.isclose(fog[key], expected, rel_tol=1e-6, abs_tol=1e-6)
                for key, expected in (("begin", 6.0), ("end", 110.0), ("curve", 1.3))),
            "最终雾参数不匹配")
    region_code = text(inputs.project("godot/src/diving/sunroom_region.gd"))
    fog_code = text(inputs.project("godot/shaders/sunroom_underwater_fog.gdshader"))
    color_code = re.sub(r"\s+", "", text(inputs.project("godot/shaders/sunroom_underwater_color.gdshaderinc")))
    particles = text(inputs.project("godot/shaders/sunroom_underwater_particles.gdshader"))
    require(region_code.count('pass_node.name = "WaterFogPass"') == 1
            and "environment.fog_enabled = false" in region_code
            and "hint_screen_texture" in fog_code and "ALPHA=1.0" in re.sub(r"\s+", "", fog_code)
            and "pow(smoothstep(6.0,110.0,distance_m),1.3)" in color_code
            and "smoothstep(448.0,500.0," in color_code
            and "fog_disabled" in particles and "region_fog_amount" in particles,
            "最终 shader 不符合单一屏幕雾/edge fade/透明粒子自雾契约")
    row = copy.deepcopy(previous)
    row.pop("asset_ledger", None)
    row.update(version="v002", source_paths=paths, authored_files=authored,
               source_sha256=authored[0]["sha256"], prefab_sha256=authored[0]["sha256"],
               runtime_sha256=authored[0]["sha256"], visual_only=False, collision=True,
               blocks_actor=True, interactive=False, standalone_only=True, production_route_integrated=False,
               runtime_verified=True, runtime_scope="standalone_region_local_only",
               collision_scope="standalone_region_only_not_surface_prefabs", development_record=DOCUMENT,
               verification=list(CHECKS), standalone_verification_report=str(evidence_path))
    row["validation"].update(runtime="passed_standalone_only", collision="passed_standalone_only",
                              visual="captured_standalone_only_user_acceptance_pending", performance="pending")
    row["atmosphere"] = copy.deepcopy(air)
    row["collision_statistics"] = copy.deepcopy(stats)
    row["render_capture_collision_statistics"] = copy.deepcopy(observed["blocking"])
    row["collision_cache_note"] = "精确Basis缓存key按进程浮点结果拆分；物理实测99形状、渲染快照158形状，85网格/758代理/3115351实例三角一致；不伪称两进程缓存数完全一致。"
    row["fog"] = {"mode": "one_opaque_screen_fog_pass_reference_old_maps", "near_m": 6.0,
                  "end_m": 110.0, "curve": 1.3, "terrain_edge_fade_m": [448.0, 500.0],
                  "alpha_particles": "self_fog_no_double_fog"}
    row["performance"] = {"status": "pending", "instance_triangles": stats["triangles"],
                          "note": "约3.1M展开三角；真实设备性能未签署，不以缓存数量代签。"}
    row["source_protection"] = {
        "baseline": str(baseline_path), "baseline_sha256": digest(baseline_raw),
        "protected_count": len(protected), "main_byte_identity_required": False,
        "note": "Main 可能被并行修改，不要求 Main 字节不变；见开发记录上下文。本工具不写 Main，原9图/catalog/city/seabed/base、GLB/terrain 仍按 baseline 核验。",
        "document": DOCUMENT,
    }
    row["final_evidence"] = {"path": str(evidence_path), "sha256": digest(evidence_raw),
                             "checks": list(CHECKS), "tested_files": [tested[p] for p in paths + list(TEST_PATHS)]}
    row["history"] = copy.deepcopy(previous.get("history", [])) + [{
        "transition": "sunroom_underwater_art_r2_v001_to_v002", "manifest": copy.deepcopy(previous),
    }]
    row["note"] = previous.get("note", "") + " v002仅独立区域艺术深化与本地阻挡；无新Blender源；来源/权属/02b/性能保持pending；历史hash与旧证据完整保留。"
    manifest = dict(row, asset_ledger=ledger_relative + "#" + ASSET_ID)
    for key in ("license", "commercial_rights_status", "reference_rights_verified", "optimization",
                "blend", "optimized_blend", "glb_export", "source_type", "source", "prefab", "runtime_path"):
        require(row[key] == previous[key], "不允许晋升来源/权属/02b或改变稳定入口：" + key)
    for key in ("source_review", "commercial_rights", "original_provenance", "reuse_optimization_evidence_consistency", "user_art_acceptance"):
        require(row["validation"][key] == previous["validation"][key], "不得代签 authority：" + key)
    if upgraded:
        require(current_row == row and current_manifest == manifest, "已登记 v002 与本次证据不同；不刷新未知漂移")
    source_raw = inputs.project(SOURCE_INDEX)
    sources = json.loads(source_raw)["sources"]
    source_position, source_row = one(sources, "asset_id", ASSET_ID)
    old_projection = {key: previous[key] for key in ("asset_id", "source", "source_sha256", "manifest")}
    projection = {key: row[key] for key in old_projection}
    require(source_row == (projection if upgraded else old_projection), "目标 source index 旧行漂移")
    plans = {}

    def plan(relative, data):
        path = project_path(relative)
        if inputs.before[path] != data:
            plans[path] = data
    plan(ledger_relative, replace_entry(ledger_raw, asset_key, row_position, row))
    if current_manifest != manifest:
        plan(MANIFEST, (dumps(manifest) + "\n").encode("utf-8"))
    plan(SOURCE_INDEX, replace_entry(source_raw, "sources", source_position, projection))
    runtime_relative = index["runtime_inventory"]
    require(runtime_relative == "assets/registry/runtime_resource_inventory.json", "runtime 路由发生变化")
    runtime_raw = inputs.project(runtime_relative)
    runtime_rows = json.loads(runtime_raw)["resources"]
    runtime_whitelist = set(paths) | set(TEST_PATHS)
    require(all(entry.get("path") in runtime_whitelist for entry in runtime_rows
                if entry.get("asset_id") == ASSET_ID), "目标资产有白名单外 runtime 行，拒绝接管")
    runtime_result = runtime_raw
    for relative in paths + list(TEST_PATHS):
        position, existing = one(runtime_rows, "path", relative, optional=True)
        sha = tested[relative]["sha256"]
        update = copy.deepcopy(existing) if existing else {"path": relative}
        update.update(bytes=len(inputs.before[project_path(relative)]), sha256=sha, asset_id=ASSET_ID,
                      status="standalone_verified_production_and_rights_pending")
        if existing is not None:
            if not upgraded:
                require(relative in OLD_HASHES or relative in TEST_PATHS, "新增源已有未知 runtime 行：" + relative)
                expected = old_fingerprints.get(relative)
                require(SHA.fullmatch(expected or "") and existing.get("sha256") == expected,
                        "旧 runtime SHA 不等于 baseline：" + relative)
                if relative in OLD_HASHES:
                    require(existing.get("asset_id") == ASSET_ID and expected == OLD_HASHES[relative]
                            and existing.get("bytes") == len(old_sources[relative]), "原6运行登记与旧源不一致")
                else:
                    require(existing.get("asset_id") in (None, ASSET_ID)
                            and existing.get("bytes") == len(old_sources[relative]), "测试旧登记归属/大小不符")
            else:
                require(existing == update, "v002 runtime 行发生漂移：" + relative)
            runtime_result = replace_entry(runtime_result, "resources", position, update)
            runtime_rows[position] = update
        else:
            require(not upgraded and relative not in OLD_HASHES, "既有 runtime 条目缺失：" + relative)
            runtime_result = splice_array(runtime_result, "resources", update, len(runtime_rows))
            runtime_rows.append(update)
    plan(runtime_relative, runtime_result)
    allowed = {project_path(p) for p in (ledger_relative, MANIFEST, SOURCE_INDEX, runtime_relative)}
    require(set(plans) <= allowed, "写入越出4文件白名单")

    def guard(committed=None):
        inputs.unchanged(committed)
        require(discover_sources() == paths, "并发新增/删除 sunroom 源，须重新验收")
    guard()
    transaction = None
    if args.write and plans:
        require(args.backup_dir is not None, "--write 必须提供工程外 --backup-dir")
        transaction = commit_transaction(inputs, plans, old_sources, args.backup_dir, guard)
    print(dumps({"mode": "write" if args.write else "dry_run", "asset_id": ASSET_ID,
                 "version": "v002", "planned_changes": len(plans),
                 "registration_changes": [p.relative_to(ROOT).as_posix() for p in plans],
                 "authored_files": len(paths), "runtime_whitelist_files": len(paths) + len(TEST_PATHS),
                 "backup_transaction": transaction, "main_byte_identity_required": False,
                 "production_route_integrated": False, "performance": "pending"}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--baseline", type=Path, required=True, help="父流程修改前 baseline.json")
    parser.add_argument("--evidence", type=Path, required=True, help="最终三个专项通过的 runner report.json")
    parser.add_argument("--before-project", type=Path, help="可核旧6源及既有测试的工程外 Godot project")
    parser.add_argument("--backup-dir", type=Path, help="已存在的工程外事务备份父目录，仅write使用")
    parser.add_argument("--write", action="store_true", help="严格证据通过后只更新4个登记文件")
    args = parser.parse_args()
    try:
        require(not args.write or args.backup_dir is not None, "--write 必须指定 --backup-dir")
        register(args)
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        print("v002 登记阻断：" + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
