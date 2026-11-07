#!/usr/bin/env python3
"""独立观赏鱼摆位登记；默认 dry-run，仅 --apply 写登记，不执行 Godot/Blender。

--verification 可重复提供绝对 runner report.json；--visual-review 可选，格式为
{"passed": true, "framefiles": [{"path": "绝对图片路径", "sha256": "..."}]}。
没有人工签署文件时 art_review 始终 pending，自动渲染通过不代签人工。
--record-pending 仅记录限定 SHA 的历史断言及真实阻断，不签署完整集成；
默认仍为 dry-run，只有 --record-pending --apply 才写 pending 登记。
"""

from __future__ import annotations

import argparse
import ast
import base64
from copy import deepcopy
import difflib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WORK = Path("D:/projects/sea-work/scenic_fish_distribution")
ASSET_ID = "SEA-DECO-SCENIC-SEA-FISH"
SCENE = "godot/scenes/decorations/animals/scenic_sea_fish_schools.tscn"
SURFACE = "godot/scenes/decorations/surface_animals.tscn"
MAIN = "godot/scenes/main.tscn"
FISH = "godot/scenes/decorations/animals/fish_school.tscn"
SCRIPTS = tuple("godot/src/ambient/" + name + ".gd" for name in (
    "decorative_fish_school", "animal_mesh", "fish_flock_group"))
TEST = "godot/tests/test_scenic_fish_distribution.gd"
CAPTURE = "godot/tools/capture_scenic_fish_distribution.gd"
RUNNER = "scripts/run_verification.py"
MANIFEST = "assets/registry/manifests/scene_components/sea-deco-scenic-sea-fish.json"
PROVENANCE = "authored placements reusing procedural fish; no new mesh export"
LICENSE = "pending_legacy_provenance_review"
STRUCTURES = {"scenic-fish-distribution", "visual-scenic-fish-structure"}
REQUIRED = {"visual-scenic-fish-distribution", "sea-fauna", "water-layer", "minimum-loop"}
ERROR = r"SCRIPT ERROR|SHADER ERROR|ERROR:|\bFAIL\b"


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def normalized(data):
    return data.decode("utf-8-sig").replace("\r\n", "\n")


def payload(value, before=None):
    text = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    if before and b"\r\n" in before:
        text = text.replace("\n", "\r\n")
    return text.encode("utf-8")


class Inputs:
    def __init__(self):
        self.before = {}

    def raw(self, path, optional=False):
        path = Path(path).resolve()
        require(optional or path.is_file(), "缺少文件：" + str(path))
        data = path.read_bytes() if path.exists() else None
        require(path not in self.before or self.before[path] == data,
                "读取期间输入变化：" + str(path))
        self.before[path] = data
        return data

    def json(self, path):
        return json.loads(self.raw(path).decode("utf-8-sig"))

    def digest(self, path):
        return sha(self.raw(path))

    def unchanged(self, committed=None):
        committed = committed or {}
        for path, original in self.before.items():
            expected = committed.get(path, original)
            actual = path.read_bytes() if path.exists() else None
            require(actual == expected, "写入前输入 SHA 已变化：" + str(path))


def project_path(value):
    require(isinstance(value, str) and value, "无效工程路径")
    value = "godot/" + value[6:] if value.startswith("res://") else value
    path = (ROOT / value).resolve()
    require(path.is_relative_to(ROOT.resolve()), "路径越出工程：" + value)
    return path


def absolute(value, label):
    path = Path(value)
    require(path.is_absolute(), label + " 必须使用绝对路径")
    return path.resolve()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def runner_tests(text):
    tests = {}
    tree = ast.parse(text)
    for node in ast.walk(tree):
        dictionaries = []
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "TESTS" for t in node.targets):
            dictionaries = [node.value]
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if isinstance(node.func.value, ast.Name) and node.func.value.id == "TESTS" and node.func.attr == "update":
                dictionaries = node.args
        for dictionary in dictionaries:
            require(isinstance(dictionary, ast.Dict), "runner TESTS 必须为可静态审阅的字典")
            for key, value in zip(dictionary.keys, dictionary.values):
                name, entry = ast.literal_eval(key), ast.literal_eval(value)
                require(name not in tests, "runner 重复 target：" + name)
                tests[name] = entry
    return tests


def parse_scene(text):
    resources = re.findall(r'^\[ext_resource type="([^"]+)" path="([^"]+)" id="([^"]+)"\]$', text, re.M)
    require(resources == [("Script", "res://src/ambient/fish_flock_group.gd", "group"),
                          ("PackedScene", "res://scenes/decorations/animals/fish_school.tscn", "fish")],
            "独立场景必须只复用现有 flock 脚本和 fish prefab")
    nodes = re.findall(r'^\[node ([^\n]+)\]\n([^\[]*)', text, re.M)
    require(len(nodes) == 11 and nodes[0][0] == 'name="ScenicSeaFishSchools" type="Node3D"',
            "场景必须为独立根节点及十群实例")
    require('metadata/asset_id = "' + ASSET_ID + '"' in nodes[0][1]
            and 'metadata/asset_version = "v001"' in nodes[0][1], "场景 ID/version 不符")
    groups = []
    for header, body in nodes[1:]:
        match = re.fullmatch(r'name="([^"]+)" parent="\." instance=ExtResource\("fish"\)', header)
        require(match is not None, "不允许额外节点或脱离 fish prefab")
        row = {"name": match[1]}
        for line in body.splitlines():
            if not line.strip():
                continue
            key, separator, value = line.partition(" = ")
            require(separator and key not in row, "无法解析或重复场景属性：" + line)
            vector = re.fullmatch(r'Vector([23])\(([^)]+)\)', value)
            if vector:
                parsed = [float(x.strip()) for x in vector[2].split(",")]
                require(len(parsed) == int(vector[1]), "向量维度错误")
            else:
                parsed = json.loads(value)
            row[key] = parsed
        for key in ("position", "spread_radius", "orbit_radius", "size_scale", "submerge_min", "submerge_max", "count", "instance_id"):
            require(key in row, "场景缺少显式属性：" + key)
        require(type(row["count"]) is int and row["count"] > 0, "鱼数不是正整数")
        require(len(row["position"]) == 3 and len(row["orbit_radius"]) == 2, "摆位或轨道维度错误")
        require(row.get("palette") == "surface" and row.get("profile") == "flat" and row.get("ride_water") is True,
                "只允许复用水面 flat 鱼并跟随真实主水")
        require(0.5 <= row["submerge_min"] <= row["submerge_max"] <= 1.5, "沉深越界")
        require(all(math.isfinite(v) for v in [*row["position"], *row["orbit_radius"],
                    row["spread_radius"], row["size_scale"], row["submerge_min"], row["submerge_max"]]), "场景存在非有限数值")
        groups.append(row)
    require(sum(x["count"] for x in groups) == 98, "新增鱼数必须恰为98")
    require(len({x["name"] for x in groups}) == len({x["instance_id"] for x in groups}) == 10,
            "鱼群名称/稳定ID必须唯一")
    return groups


def surface_rollback(inputs, pending=False):
    current = normalized(inputs.raw(ROOT / SURFACE))
    resource = '[ext_resource type="PackedScene" path="res://scenes/decorations/animals/scenic_sea_fish_schools.tscn" id="scenic_fish"]\n'
    node = '[node name="ScenicSeaFishSchools" parent="." instance=ExtResource("scenic_fish")]'
    require(current.count(resource) == current.count(node) == 1, "surface 必须只新增一 resource/一 node")
    require(current.endswith(node + "\n"), "新增挂载不在预期尾部或附带了覆盖属性")
    before = current.replace(resource, "", 1)
    before = before[:-len(node + "\n")].rstrip("\n") + "\n"
    match = re.match(r'\[gd_scene load_steps=(\d+) format=3\]', before)
    require(match is not None, "surface 缺少 load_steps")
    before = before.replace(match[0], '[gd_scene load_steps=%d format=3]' % (int(match[1]) - 1), 1)
    # HEAD 的历史 load_steps 可能原已欠计数；保留历史原文，不用整文件回滚覆盖其它摆位。
    head = git("rev-parse", "HEAD").decode().strip()
    original = git("show", head + ":" + SURFACE)
    history_body = re.sub(r'^\[gd_scene load_steps=\d+ format=3\]\n', "", normalized(original)).rstrip()
    before_body = re.sub(r'^\[gd_scene load_steps=\d+ format=3\]\n', "", before).rstrip()
    if not pending:
        require(history_body == before_body, "surface 除本轮挂载外还有未知内容差异，拒绝刷新登记")
    return {"git_head": head, "historical_path": SURFACE, "historical_sha256": sha(original),
            "only_scenic_mount_diff": history_body == before_body,
            "historical_source_base64": base64.b64encode(original).decode(),
            "incremental_base_sha256_lf": sha(before.encode()),
            "patch": "".join(difflib.unified_diff(before.splitlines(True), current.splitlines(True),
                                                   fromfile="a/" + SURFACE, tofile="b/" + SURFACE)),
            "instruction": "只反向应用本轮 patch；历史源码单独保留，不虚构回滚ZIP。"}


def validate_reports(inputs, paths, tests):
    covered, evidence, frames, imports = set(), [], {}, 0
    # 同时比对整个隔离场景/脚本树，禁止仅看报告布尔值或使用过期 main。
    current_files = set()
    for folder in ("scenes", "src", "scripts", "tests", "tools", "shaders"):
        base = ROOT / "godot" / folder
        current_files.update(p for p in base.rglob("*") if p.is_file() and p.suffix in {".gd", ".tscn", ".gdshader"})
    hashes = {p.relative_to(ROOT / "godot").as_posix(): inputs.digest(p) for p in sorted(current_files)}
    targets = REQUIRED | STRUCTURES
    for supplied in paths:
        path = absolute(supplied, "--verification")
        require(path.name == "report.json" and str(path) not in {x["path"] for x in evidence}, "必须是唯一的 runner report.json")
        report = inputs.json(path)
        require(absolute(report.get("run_dir", ""), "runner run_dir") == path.parent, "runner run_dir 与报告父目录不符")
        results = report.get("results")
        require(isinstance(results, dict), "runner 报告缺少 results 字典")
        relevant = set(results) & targets
        imported = report.get("asset_import")
        require(relevant or imported is not None, "报告没有所需 target 或 import 证据")
        snapshot = path.parent / "project"
        snapshot_files = set()
        for folder in ("scenes", "src", "scripts", "tests", "tools", "shaders"):
            snapshot_files.update(p.relative_to(snapshot).as_posix() for p in (snapshot / folder).rglob("*")
                                  if p.is_file() and p.suffix in {".gd", ".tscn", ".gdshader"})
        require(snapshot_files == set(hashes), "snapshot 场景/scripts 文件集合与当前不符：" + str(path))
        for name, expected in hashes.items():
            require(inputs.digest(snapshot / name) == expected, "snapshot SHA 与当前不符：" + name)
        for name in sorted(relevant):
            result = results[name]
            require(isinstance(result, dict) and result.get("passed") is True
                    and type(result.get("exit_code")) is int and result["exit_code"] == 0,
                    name + " 必须 passed:true、exit_code:0，不接受基线失败豁免")
            require(result.get("completion_marker") is True and result.get("unexpected_errors") == []
                    and not result.get("failure_labels") and not result.get("failures")
                    and not result.get("errors"), name + " 缺少完成标记或含错误")
            require(name in tests, "当前 runner 未定义 target：" + name)
            script, marker = tests[name]
            command = result.get("command", [])
            require(isinstance(command, list) and "--script" in command, name + " 缺少实际执行命令")
            require(command[command.index("--script") + 1] == "res://" + script, name + " 执行脚本不是当前 target")
            require("--path" in command and absolute(command[command.index("--path") + 1], "command --path") == snapshot,
                    name + " 未运行该隔离 snapshot")
            log = absolute(result.get("log", ""), name + " log")
            require(log.parent == path.parent, name + " 日志不在本次 runner 目录")
            text = normalized(inputs.raw(log))
            require(not re.search(ERROR, text) and re.search(marker, text), name + " 原日志失败或缺少成功标记")
            if name.startswith("visual-"):
                require(result.get("renderer") == "real" and "--headless" not in command, name + " 必须真实渲染")
            covered.add(name)
        if imported is not None:
            require(type(imported.get("exit_code")) is int and imported["exit_code"] == 0
                    and imported.get("unexpected_errors") == [], "asset_import 必须 exit0 且无错误")
            log = absolute(imported.get("log", ""), "asset_import log")
            require(log.parent == path.parent and not re.search(ERROR, normalized(inputs.raw(log))), "asset_import 原日志失败")
            imports += 1
        if "visual-scenic-fish-distribution" in relevant:
            render_path = snapshot / "outputs/scenic-fish-distribution/render-report.json"
            render = inputs.json(render_path)
            require(render.get("render_checks_passed") is True and render.get("failures") == [], "渲染报告未通过")
            rows = render.get("frames", [])
            require(len(rows) == 23, "渲染报告必须有20幅近景和3幅环境图")
            local_frames = set()
            for row in rows:
                require(row.get("formal_fish_on") is True, "不能以 fish-off 诊断图代替正式图")
                frame = (snapshot / row["path"][6:]).resolve() if row["path"].startswith("res://") else absolute(row["path"], "frame")
                require(frame.is_relative_to((snapshot / "outputs/scenic-fish-distribution").resolve()) and frame not in local_frames,
                        "渲染帧路径越界或重复")
                image = inputs.raw(frame)
                require(image.startswith(b"\x89PNG\r\n\x1a\n") and len(image) > 32, "渲染帧不是有效PNG")
                local_frames.add(frame)
                frames[frame.as_posix()] = sha(image)
        evidence.append({"path": path.as_posix(), "sha256": inputs.digest(path)})
    require(REQUIRED <= covered and covered & STRUCTURES, "缺少必要通过项：" + str(sorted(REQUIRED - covered)) + "；另须结构项二选一")
    require(imports > 0, "至少一份同 SHA snapshot 的 runner asset_import 必须 exit0")
    return evidence, hashes, frames, sorted(covered)


def validate_pending_reports(inputs, paths, tests):
    """限定鱼群输入必须同 SHA；其它漂移和运行错误保留为阻断，不豁免失败。"""
    critical = {SCENE, SURFACE, TEST, CAPTURE, FISH, *SCRIPTS, "godot/src/ambient/scene_component.gd"}
    current = {}
    for folder in ("scenes", "src", "scripts", "tests", "tools", "shaders"):
        for path in sorted((ROOT / "godot" / folder).rglob("*")):
            if path.is_file() and path.suffix in {".gd", ".tscn", ".gdshader"}:
                current[path.relative_to(ROOT).as_posix()] = inputs.digest(path)
    require(critical <= current.keys() and MAIN in current, "限定鱼群输入或 main 缺失")
    evidence, frames, subchecks, blockers, mismatches = [], {}, [], [], []
    covered, imports, main_hashes = set(), 0, []
    for supplied in paths:
        path = absolute(supplied, "--verification")
        require(path.name == "report.json" and path.as_posix() not in {x["path"] for x in evidence},
                "必须是唯一的 runner report.json")
        report = inputs.json(path)
        require(absolute(report.get("run_dir", ""), "runner run_dir") == path.parent,
                "runner run_dir 与报告父目录不符")
        results = report.get("results")
        require(isinstance(results, dict), "runner 报告缺少 results 字典")
        snapshot = path.parent / "project"
        snapshot_hashes = {}
        for folder in ("scenes", "src", "scripts", "tests", "tools", "shaders"):
            for file in sorted((snapshot / folder).rglob("*")):
                if file.is_file() and file.suffix in {".gd", ".tscn", ".gdshader"}:
                    snapshot_hashes["godot/" + file.relative_to(snapshot).as_posix()] = inputs.digest(file)
        for name in sorted(critical):
            require(snapshot_hashes.get(name) == current[name], "pending 限定输入 SHA 与当前不符：" + name)
        require(MAIN in snapshot_hashes, "snapshot 缺少 main")
        main_hashes.append({"report": path.as_posix(), "sha256": snapshot_hashes[MAIN]})
        for name in sorted(current.keys() | snapshot_hashes.keys()):
            if current.get(name) != snapshot_hashes.get(name):
                mismatch = {"report": path.as_posix(), "path": name,
                            "current_sha256": current.get(name), "evidence_sha256": snapshot_hashes.get(name)}
                mismatches.append(mismatch)
                blockers.append({"kind": "snapshot_current_mismatch", **mismatch})
        for name, result in sorted(results.items()):
            require(isinstance(result, dict), "无效 runner result：" + name)
            log = absolute(result.get("log", ""), name + " log")
            require(log.parent == path.parent, name + " 日志不在本次 runner 目录")
            text = normalized(inputs.raw(log))
            raw_errors = [{"line": number, "text": line} for number, line in enumerate(text.splitlines(), 1)
                          if re.search(ERROR, line, re.I)]
            actual_errors = {key: deepcopy(result[key]) for key in
                             ("expected_errors", "unexpected_errors", "failure_labels", "failures", "errors")
                             if key in result}
            actual_errors["log_errors"] = raw_errors
            relevant = name in REQUIRED | STRUCTURES
            marker = None
            command_valid = False
            if relevant:
                require(name in tests, "当前 runner 未定义 target：" + name)
                script, pattern = tests[name]
                marker = re.search(pattern, text)
                command = result.get("command", [])
                require(isinstance(command, list) and "--script" in command and "--path" in command,
                        name + " 缺少实际执行命令")
                require(command[command.index("--script") + 1] == "res://" + script,
                        name + " 执行脚本不是当前 target")
                require(absolute(command[command.index("--path") + 1], "command --path") == snapshot,
                        name + " 未运行该隔离 snapshot")
                if name.startswith("visual-"):
                    require(result.get("renderer") == "real" and "--headless" not in command,
                            name + " 必须真实渲染")
                command_valid = True
            assertions = (relevant and command_valid and type(result.get("exit_code")) is int
                          and result["exit_code"] == 0 and result.get("completion_marker") is True
                          and marker is not None and not result.get("failure_labels")
                          and not result.get("failures")
                          and not re.search(r"\bFAIL\b|\b[1-9]\d* (?:failures|failed)\b", text))
            error_free = not raw_errors and not any(result.get(key) for key in
                         ("expected_errors", "unexpected_errors", "failure_labels", "failures", "errors"))
            passed = (result.get("passed") is True and type(result.get("exit_code")) is int
                      and result["exit_code"] == 0 and result.get("completion_marker") is True
                      and result.get("unexpected_errors") == [] and error_free
                      and (assertions if relevant else True))
            check = {"report": path.as_posix(), "target": name, "exit_code": result.get("exit_code"),
                     "runner_passed": result.get("passed"), "completion_marker": result.get("completion_marker"),
                     "targeted_assertions_passed": bool(assertions), "passed": passed,
                     "completion_evidence": marker[0] if marker else None, "actual_errors": actual_errors,
                     "log": log.as_posix(), "log_sha256": inputs.digest(log)}
            subchecks.append(check)
            if assertions:
                covered.add(name)
            if not passed:
                blockers.append({"kind": "runtime_check_failed_or_incomplete", **deepcopy(check)})
        imported = report.get("asset_import")
        if imported is not None:
            require(isinstance(imported, dict), "无效 asset_import")
            imports += 1
            log = absolute(imported.get("log", ""), "asset_import log")
            require(log.parent == path.parent, "asset_import 日志不在本次 runner 目录")
            text = normalized(inputs.raw(log))
            actual_errors = {key: deepcopy(imported[key]) for key in
                             ("unexpected_errors", "expected_errors", "errors", "failures") if key in imported}
            actual_errors["log_errors"] = [
                {"line": number, "text": line} for number, line in enumerate(text.splitlines(), 1)
                if re.search(ERROR, line, re.I)]
            passed = (type(imported.get("exit_code")) is int and imported["exit_code"] == 0
                      and imported.get("unexpected_errors") == [] and not any(actual_errors.values()))
            check = {"report": path.as_posix(), "target": "asset_import", "exit_code": imported.get("exit_code"),
                     "passed": passed, "actual_errors": actual_errors, "log": log.as_posix(),
                     "log_sha256": inputs.digest(log)}
            subchecks.append(check)
            if not passed:
                blockers.append({"kind": "import_failed_or_incomplete", **deepcopy(check)})
        if "visual-scenic-fish-distribution" in results:
            render_path = snapshot / "outputs/scenic-fish-distribution/render-report.json"
            render = inputs.json(render_path)
            require(render.get("render_checks_passed") is True and render.get("failures") == [], "渲染断言未通过")
            rows = render.get("frames", [])
            require(len(rows) == 23, "渲染报告必须有20幅近景和3幅环境图")
            local_frames = set()
            for row in rows:
                require(row.get("formal_fish_on") is True, "不能以 fish-off 诊断图代替正式图")
                frame = ((snapshot / row["path"][6:]).resolve() if row["path"].startswith("res://")
                         else absolute(row["path"], "frame"))
                require(frame.is_relative_to((snapshot / "outputs/scenic-fish-distribution").resolve())
                        and frame not in local_frames, "渲染帧路径越界或重复")
                image = inputs.raw(frame)
                require(image.startswith(b"\x89PNG\r\n\x1a\n") and len(image) > 32, "渲染帧不是有效PNG")
                local_frames.add(frame)
                frames[frame.as_posix()] = sha(image)
            subchecks.append({"report": path.as_posix(), "target": "render_assertions", "passed": True,
                              "scope": "仅历史snapshot像素断言，不含完整运行或人工目视签署",
                              "frame_count": len(rows), "path": render_path.as_posix(),
                              "sha256": inputs.digest(render_path)})
        evidence.append({"path": path.as_posix(), "sha256": inputs.digest(path)})
    missing = sorted(REQUIRED - covered)
    if not covered & STRUCTURES:
        missing.append("结构项二选一")
    if missing:
        blockers.append({"kind": "incomplete_targeted_assertions", "missing": missing})
    if not imports:
        blockers.append({"kind": "incomplete_asset_import", "actual_errors": "未提供 import 证据"})
    blockers.append({"kind": "full_integration_pending", "note": "未对当前完整实景签署 verified；需严格模式重新验证。"})
    current[RUNNER] = inputs.digest(ROOT / RUNNER)
    current[Path(__file__).relative_to(ROOT).as_posix()] = inputs.digest(Path(__file__))
    return evidence, current, frames, sorted(covered), {
        "current_mainsha": current[MAIN], "evidence_mainsha": main_hashes[0]["sha256"],
        "evidence_mainsha_by_report": main_hashes,
        "snapshot_mismatches": mismatches, "structured_subchecks": subchecks,
        "blockers_actual": blockers, "targeted_assertions_passed": not missing,
        "full_integration_pending": True, "full_integration_verified": False,
        "incomplete": True, "passed": False}


def visual_review(inputs, supplied, frames):
    if supplied is None:
        return {"status": "pending", "note": "运行/像素验证不代表人工目视通过，等待父任务看图。"}
    path = absolute(supplied, "--visual-review")
    review = inputs.json(path)
    require(review.get("passed") is True, "人工签署必须 passed:true")
    rows = review.get("framefiles")
    require(isinstance(rows, list) and rows, "人工签署须含非空 framefiles [{path, sha256}]")
    approved = {}
    for row in rows:
        require(isinstance(row, dict), "framefiles 每项须含 path/sha256")
        frame = absolute(row.get("path", ""), "人工审核帧").as_posix()
        require(frame not in approved and frames.get(frame) == row.get("sha256") == inputs.digest(Path(frame)),
                "人工审核帧不属于本次真实渲染或 SHA 不符：" + frame)
        approved[frame] = row["sha256"]
    require(set(approved) == set(frames), "人工签署必须覆盖提供的全部正式渲染帧")
    return {"status": "passed", "report": path.as_posix(), "sha256": inputs.digest(path), "framefiles": rows,
            "note": "仅记录外部显式人工签署；登记脚本不代签。"}


def append_unique(rows, value):
    if value not in rows:
        rows.append(deepcopy(value))


def register(args):
    inputs = Inputs()
    inputs.raw(Path(__file__))
    index = inputs.json(ROOT / "assets/registry/ledger_index.json")
    route = index["domains"]["scenes"]
    ledger_path, inventory_path = project_path(route["ledger"]), project_path(index["runtime_inventory"])
    ledger, inventory = inputs.json(ledger_path), inputs.json(inventory_path)
    require(route.get("asset_key") == "assets" and isinstance(ledger.get("assets"), list), "scenes domain 必须路由 assets 列表")
    original_assets, original_resources = deepcopy(ledger["assets"]), deepcopy(inventory["resources"])
    assets, domain_rows = {}, []
    for domain, routing in index["domains"].items():
        book = ledger if domain == "scenes" else inputs.json(project_path(routing["ledger"]))
        domain_rows.append(book[routing["asset_key"]])
        for asset in book[routing["asset_key"]]:
            require(asset["asset_id"] not in assets, "跨域重复 AssetID：" + asset["asset_id"])
            assets[asset["asset_id"]] = asset
    by_path = {x["path"]: x for x in inventory["resources"]}
    require(len(by_path) == len(inventory["resources"]), "runtime inventory 路径重复")
    groups = parse_scene(normalized(inputs.raw(ROOT / SCENE)))
    rollback = surface_rollback(inputs, pending=args.record_pending)
    runner_text = normalized(inputs.raw(ROOT / RUNNER))
    tests = runner_tests(runner_text)
    require(tests.get("scenic-fish-distribution", (None,))[0] == TEST.removeprefix("godot/")
            or "visual-scenic-fish-structure" in tests, "缺少结构 target")
    require(tests.get("visual-scenic-fish-distribution", (None,))[0] == CAPTURE.removeprefix("godot/"), "渲染 target 路径不符")
    touched = {SURFACE, SCENE, TEST, CAPTURE}
    if RUNNER in by_path and not args.record_pending:
        # 只允许在已登记的版本上恰好增加两条鱼群 entry；其它任务改动绝不顺带洗白。
        before_runner = git("show", "HEAD:" + RUNNER)
        require(sha(before_runner) == by_path[RUNNER]["sha256"], "runner 登记 SHA 与 HEAD 不符，不能证明 exact 本轮 diff")
        stripped = runner_text
        for name in ("scenic-fish-distribution", "visual-scenic-fish-distribution"):
            pattern = r"^    " + re.escape(repr(name)) + r": .*\n"
            stripped, count = re.subn(pattern, "", stripped, flags=re.M)
            require(count == 1 and name not in runner_tests(normalized(before_runner)), "runner 本轮必须恰为两 entry 新增")
        require(stripped == normalized(before_runner), "runner 含非本轮两 entry 增量，拒绝更新 inventory")
        touched.add(RUNNER)
    pending_details = {}
    if args.record_pending:
        evidence, snapshots, frames, checks, pending_details = validate_pending_reports(inputs, args.verification, tests)
    else:
        evidence, snapshots, frames, checks = validate_reports(inputs, args.verification, tests)
    art = visual_review(inputs, args.visual_review, frames)
    if args.record_pending and art["status"] == "passed":
        art.update(scope="仅签署所列历史snapshot帧，不签署当前完整实景或运行集成", full_integration_verified=False)
    dependencies = {p: inputs.digest(ROOT / p) for p in (FISH, *SCRIPTS)}
    scene_hash = inputs.digest(ROOT / SCENE)
    warnings = []
    if args.record_pending:
        require(SCENE not in by_path or by_path[SCENE].get("asset_id") in (None, ASSET_ID),
                "新场景关联了其它资产")
        touched = {p for p in (SCENE, TEST, CAPTURE) if p not in by_path}
        surface_row = by_path.get(SURFACE)
        if (surface_row is not None and surface_row.get("sha256") == rollback["historical_sha256"]
                and rollback["only_scenic_mount_diff"]):
            touched.add(SURFACE)
        else:
            warnings.append({"kind": "surface_inventory_not_refreshed", "path": SURFACE,
                             "registered_sha256": surface_row.get("sha256") if surface_row else None,
                             "head_sha256": rollback["historical_sha256"],
                             "current_sha256": snapshots[SURFACE],
                             "only_scenic_mount_diff": rollback["only_scenic_mount_diff"],
                             "action": "保持旧记录；仅旧hash等于HEAD且只有本轮resource/node差异才允许更新"})
        for path in (SCENE, TEST, CAPTURE):
            if path in by_path:
                warnings.append({"kind": "existing_pending_inventory_preserved", "path": path,
                                 "registered_sha256": by_path[path].get("sha256"),
                                 "current_sha256": snapshots[path], "action": "既有记录不刷新"})
    for old in original_assets:
        source = old.get("source")
        if source not in dependencies:
            continue
        for key in ("source_sha256", "originalSHA"):
            if old.get(key) and old[key] != dependencies[source]:
                warnings.append({"kind": "existing_source_drift", "asset_id": old["asset_id"], "path": source,
                                 "field": key, "registered_sha256": old[key], "current_sha256": dependencies[source],
                                 "action": ("仅记录限定历史证据，不更新旧资产hash，不签署完整集成。" if args.record_pending
                                            else "仅警告；允许经当前 snapshot 视觉验证的复用，不更新旧资产hash。")})
    for path in dependencies:
        row = by_path.get(path)
        if row and row.get("sha256") != dependencies[path]:
            warnings.append({"kind": "existing_shared_inventory_drift", "path": path,
                             "registered_sha256": row.get("sha256"), "current_sha256": dependencies[path], "action": "保持旧记录不变"})
    evidence_main = (pending_details["evidence_mainsha"] if args.record_pending
                     else snapshots[MAIN.removeprefix("godot/")])
    event = {"verification": evidence, "checks": checks, "snapshot_main_sha256": evidence_main,
             "dependency_sha256": dependencies, "art_review": art}
    if args.record_pending:
        event.update(mode="pending", **pending_details)
    core = {"asset_id": ASSET_ID, "name": "独立海面观赏鱼群摆位", "domain": "scenes", "version": "v001",
            "source": SCENE, "source_sha256": scene_hash, "prefab": SCENE, "prefab_sha256": scene_hash,
            "runtime_path": SCENE, "runtime_sha256": scene_hash, "manifest": MANIFEST,
            "source_provenance": PROVENANCE, "license": LICENSE,
            "classification": {"category": "decoration", "subcategory": "animals"},
            "group_count": 10, "fish_count": 98, "groups": groups, "dependency_sha256": dependencies,
            "building_class": None,
            "water_layer": "none", "water_layer_role": "none", "placement_water_layer": "surface",
            "visual_only": True, "responsibility": "visual_only", "collision": False,
            "interactive": False, "resource_output": False, "gameplay_state": False,
            "commercial_rights_status": "pending", "reference_rights_verified": False}
    old = assets.get(ASSET_ID)
    if old is not None:
        require(old in ledger["assets"] and "suite" not in old, "新ID不属于独立scenes资产或误入suite")
        require(all((k in old or k == "building_class") and old.get(k) == v for k, v in core.items()),
                "新ID已存在但内容/SHA不匹配；只能补空building_class或追加新证据")
        old.setdefault("building_class", None)
        asset = old
    else:
        asset = deepcopy(core)
        asset.update(stage="runtime_verified_art_pending", runtime_integrated=not args.record_pending,
                     runtime_verified=not args.record_pending,
                     verification=[], evidence_history=[], art_review={"status": "pending"})
        ledger["assets"].append(asset)
    if args.record_pending:
        require(asset.get("runtime_verified") is not True and asset.get("runtime_integrated") is not True,
                "不能用 pending 降级已有 verified 资产")
        asset.update(stage="source_scene_registered_runtime_final_pending", runtime_integrated=False,
                     runtime_verified=False, default_visible_scene_mounted=True, full_integration_pending=True)
    elif asset.get("stage") == "source_scene_registered_runtime_final_pending":
        # 只有严格 validate_reports 及其余原门禁全部通过，才允许升级；不删 pending 历史。
        asset.update(stage="runtime_verified_art_pending", runtime_integrated=True, runtime_verified=True,
                     full_integration_pending=False)
    for item in evidence:
        append_unique(asset.setdefault("verification", []), item["path"])
    append_unique(asset.setdefault("evidence_history", []), event)
    if art["status"] == "passed":
        asset["art_review"] = art
    manifest_path = ROOT / MANIFEST
    before_manifest = inputs.raw(manifest_path, optional=True)
    manifest_core = dict(core, asset_ledger=route["ledger"] + "#" + ASSET_ID)
    manifest = json.loads(before_manifest.decode("utf-8-sig")) if before_manifest else deepcopy(manifest_core)
    require(before_manifest is None or all((k in manifest or k == "building_class") and manifest.get(k) == v
                                          for k, v in manifest_core.items()), "既有manifest与新ID内容不符")
    manifest.setdefault("building_class", None)
    for item in evidence:
        append_unique(manifest.setdefault("verification", []), item["path"])
    append_unique(manifest.setdefault("evidence_history", []), event)
    if art["status"] == "passed" or "art_review" not in manifest:
        manifest["art_review"] = art
    if args.record_pending:
        manifest.update(stage=asset["stage"], runtime_integrated=False, runtime_verified=False,
                        default_visible_scene_mounted=True, current_file_sha256=snapshots,
                        **pending_details)
    elif manifest.get("full_integration_pending") is True:
        for key in ("current_file_sha256", "current_mainsha", "evidence_mainsha", "evidence_mainsha_by_report", "snapshot_mismatches",
                    "structured_subchecks", "blockers_actual", "targeted_assertions_passed"):
            manifest.pop(key, None)
        manifest.update(stage=asset["stage"], runtime_integrated=True, runtime_verified=True,
                        full_integration_pending=False, full_integration_verified=True, passed=True,
                        incomplete=False)
    for path in sorted(touched):
        row = by_path.get(path)
        if row is None:
            row = {"path": path, "asset_id": ASSET_ID if path == SCENE else None}
            inventory["resources"].append(row)
        require(path != SCENE or row.get("asset_id") in (None, ASSET_ID), "新场景关联了其它资产")
        data = inputs.raw(ROOT / path)
        new_sha = sha(data)
        if path == SCENE:
            row["asset_id"] = ASSET_ID
        if row.get("sha256") and row["sha256"] != new_sha:
            append_unique(row.setdefault("hash_history", []), {"sha256": row["sha256"], "bytes": row.get("bytes")})
        row.update(sha256=new_sha, bytes=len(data), status=("runtime_validation_pending" if args.record_pending
                   else "runtime_component_verified_art_pending" if path == SCENE else "runtime_resource_verified"))
        for item in evidence:
            append_unique(row.setdefault("verification_history", []), item)
    require([x for x in original_assets if x["asset_id"] != ASSET_ID] ==
            [x for x in ledger["assets"] if x["asset_id"] != ASSET_ID], "修改了其它asset row")
    require([x for x in original_resources if x["path"] not in touched] ==
            [x for x in inventory["resources"] if x["path"] not in touched], "修改了白名单外inventory")
    source_index_path = ROOT / "assets/registry/current_source_index.json"
    source_index = inputs.json(source_index_path)
    projected_sources = [{key: row[key] for key in ("asset_id", "source", "source_sha256", "manifest")}
                         for rows in domain_rows for row in rows]
    require([row for row in source_index["sources"] if row["asset_id"] != ASSET_ID] ==
            [row for row in projected_sources if row["asset_id"] != ASSET_ID],
            "current_source_index 存在非本轮行差异；拒绝同步其它域或旧行")
    source_index["sources"] = projected_sources
    planned = {}
    for path, value in ((ledger_path, ledger), (inventory_path, inventory), (manifest_path, manifest),
                        (source_index_path, source_index)):
        before = inputs.raw(path, optional=path == manifest_path)
        if before is None or json.loads(before.decode("utf-8-sig")) != value:
            planned[path] = payload(value, before)
    report_path = WORK / "runtime_registration.json"
    previous_raw = inputs.raw(report_path, optional=True)
    report = json.loads(previous_raw.decode("utf-8-sig")) if previous_raw else {}
    history = report.setdefault("history", [])
    mode = "pending" if args.record_pending else "apply" if args.apply else "dryrun"
    append_unique(history, {"mode": mode, "applied": args.apply, **event, "warnings": warnings})
    report.update(asset_id=ASSET_ID, mode=mode, passed=not args.record_pending,
                  group_count=10, fish_count=98, art_review=asset["art_review"], warnings=warnings,
                  checks=checks, verification=evidence, resource_sha256={p: inputs.digest(ROOT / p) for p in sorted(touched)},
                  snapshot_main_sha256=evidence_main, dependency_sha256=dependencies,
                  planned_changes=[{"path": p.relative_to(ROOT).as_posix(), "before_sha256": sha(inputs.before[p]) if inputs.before[p] else None,
                                    "after_sha256": sha(data)} for p, data in planned.items()],
                  surface_rollback=rollback, unchanged_other_assets=True, unchanged_main_inventory=True,
                  note="只登记独立摆位；不修改共享鱼脚本旧hash，不入sunken_city，无新Blender导出或优化。")
    report.update(applied=args.apply, dry_run=not args.apply)
    if args.record_pending:
        report.update(current_file_sha256=snapshots, **pending_details)
        report["note"] = "仅登记历史snapshot限定断言与实际错误；当前完整实景未verified，不刷新共享脚本旧hash。"
    elif report.get("full_integration_pending") is True:
        for key in ("current_file_sha256", "current_mainsha", "evidence_mainsha", "evidence_mainsha_by_report", "snapshot_mismatches",
                    "structured_subchecks", "blockers_actual", "targeted_assertions_passed"):
            report.pop(key, None)
        report.update(full_integration_pending=False, full_integration_verified=True, incomplete=False)
    # 保存真实写前字节用于登记元数据回滚；不宣称已有备份ZIP，不覆盖首次留存历史。
    if args.apply:
        originals = report.setdefault("registration_originals_base64", {})
        for path in planned:
            originals.setdefault(path.relative_to(ROOT).as_posix(),
                                 base64.b64encode(inputs.before[path]).decode() if inputs.before[path] is not None else None)
    writes = dict(planned) if args.apply else {}
    writes[report_path] = payload(report, previous_raw)
    inputs.unchanged()
    # dry-run 只落工作目录报告；登记文件逐文件原子替换，失败则还原本事务已写项。
    require(WORK.parent.is_dir(), "工作目录父路径不存在：" + str(WORK.parent))
    WORK.mkdir(exist_ok=True)
    atomic_write(inputs, writes)
    print(json.dumps({"mode": report["mode"], "passed": report["passed"], "applied": args.apply,
                      **({"targeted_assertions_passed": pending_details["targeted_assertions_passed"],
                          "full_integration_verified": False, "incomplete": True,
                          "blockers_actual": pending_details["blockers_actual"]} if args.record_pending else {}),
                      "report": report_path.as_posix(), "planned_changes": report["planned_changes"],
                      "art_review": asset["art_review"]["status"], "warnings": warnings}, ensure_ascii=False, indent=2))


def atomic_write(inputs, writes):
    staged, committed = {}, {}
    try:
        for path, data in writes.items():
            require(path.parent.is_dir(), "写入父目录不存在：" + str(path.parent))
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix="." + path.name + ".", delete=False) as stream:
                staged[path] = Path(stream.name)
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
        for path in writes:
            inputs.unchanged(committed)
            os.replace(staged[path], path)
            committed[path] = writes[path]
    except Exception:
        for path in reversed(list(committed)):
            require(path.read_bytes() == committed[path], "回滚遇到并行改动，请使用报告原始字节人工恢复：" + str(path))
            original = inputs.before[path]
            if original is None:
                path.unlink()
            else:
                with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
                    restore = Path(stream.name)
                    stream.write(original)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(restore, path)
        raise
    finally:
        for temp in staged.values():
            temp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verification", action="append", required=True, metavar="ABS_REPORT_JSON", help="绝对 runner report.json；可重复追加")
    parser.add_argument("--visual-review", metavar="ABS_JSON", help="父任务目视后的绝对人工签署JSON")
    parser.add_argument("--record-pending", action="store_true",
                        help="限定SHA历史证据登记模式；不签署verified，默认dry-run，追加--apply才写pending")
    parser.add_argument("--apply", action="store_true", help="写入登记；无--record-pending时必须通过原有全部verified门禁")
    args = parser.parse_args()
    try:
        register(args)
    except (ValueError, KeyError, TypeError, IndexError, OSError, subprocess.CalledProcessError) as error:
        print("登记阻断：" + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
