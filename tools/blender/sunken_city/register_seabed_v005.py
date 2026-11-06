"""登记 sunken_city v005 海床与 fauna 运行资产。

默认只读 dry-run；只有显式 --apply 才写入登记元数据与本轮生成的 manifest。
本脚本不运行 Blender、Godot、runner、import 或 apply_water_layer，不修改 Blend、GLB、prefab、Terrain3D 数据、色盘及其它代码。

严格门禁：
- v005 主源、50 个组件包、v005 catalog/package/skill 报告和真实 SHA256；
- v004 主源、组件源、优化源、GLB 与公共色盘逐项未变；
- v005 优化源只允许与 v004 优化源字节相同的路径复用，不虚构重新优化；
- 388 个旧城实例、50 个纯 visual 组件、无 edge_ramp 额外节点；
- Terrain3D 独立 SunkenSeabed、4 个持久 region、author tool 与海床 manifest；
- 七个指定 runner 标签全部 passed:true、exit_code:0，且至少一份 asset_import 成功；
- runtime_inventory 只刷新本轮白名单，其它记录逐字节保留；
- --apply 前重新核对所有输入 SHA256，并使用同目录临时文件原子替换。
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[3]
V005 = ROOT / "art_source/scenes/sunken_city/v005"
V004 = ROOT / "art_source/scenes/sunken_city/v004"
GODOT = ROOT / "godot"
WORK = ROOT.parent / "sea-work/sunken_city/v005"
LEDGER = ROOT / "assets/registry/ledgers/scenes.json"
INDEX = ROOT / "assets/registry/ledger_index.json"
SOURCE_INDEX = ROOT / "assets/registry/current_source_index.json"
INVENTORY = ROOT / "assets/registry/runtime_resource_inventory.json"
MASTER = V005 / "sunken_city_v005.blend"
OLD_MASTER = V004 / "sunken_city_v004.blend"
PALETTE = ROOT / "art_source/shared/palettes/sea_cabin_timber_8x8_512.png"
V005_EXPORT = V005 / "export/v005/export_manifest.json"
V004_EXPORT = V004 / "export/v004/export_manifest.json"
RUNTIME_MANIFEST = GODOT / "assets/models/scenery/sunken_city/runtime_manifest.json"
ASSEMBLY = GODOT / "scenes/world/sunken_city.tscn"
MAIN = GODOT / "scenes/main.tscn"
MAIN_SCRIPT = GODOT / "src/bootstrap/main.gd"
FUTILITY = {
    "SEA-SCENE-SCITY-T-JUNCTION",
    "SEA-SCENE-SCITY-CANAL-END",
}
ASSEMBLY_ID = "SEA-SCENE-SCITY-ASSEMBLY"
SEABED_ID = "SEA-SCENE-SCITY-SEABED"
FAUNA_IDS = {
    "SEA-DECO-SOLAR-FISH-VARIANTS",
    "SEA-DECO-SOLAR-GULLS",
    "SEA-DECO-RANCH-GULLS",
}
TARGETS = {
    "seabed-scene",
    "sunken-city",
    "sea-fauna",
    "water-layer",
    "minimum-loop",
    "visual-sunken-seabed",
    "visual-sea-fauna",
}
FALSE_FIELDS = (
    "collision", "navigation", "walk", "interaction", "shoreline", "emission",
    "interactive", "blocks_actor", "blocks_water", "walkable", "has_landing",
    "navigation_obstacle", "resource_output", "gameplay_state", "shoreline_source",
    "walk_areas", "landing_points", "water_shapes", "navigation_obstacles",
    "interactions", "production", "save_fields", "walk_surface", "walkable_area",
    "actor_collision", "boat_blocking", "landing_point",
)


def fail(message: str) -> None:
    raise ValueError(message)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT.resolve()).as_posix()


def project_path(value: str) -> Path:
    require(isinstance(value, str) and value and "\\" not in value,
            "工程路径必须为非空正斜杠路径：" + str(value))
    if value.startswith("res://"):
        value = "godot/" + value[6:]
    path = (ROOT / value).resolve()
    require(path.is_relative_to(ROOT.resolve()), "路径越出工程：" + value)
    return path


class Inputs:
    def __init__(self) -> None:
        self.raw: dict[Path, bytes] = {}
        self.hashes: dict[Path, str] = {}

    def read_bytes(self, path: Path) -> bytes:
        path = path.resolve()
        require(path.is_file(), "缺少输入文件：" + str(path))
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if path in self.hashes:
            require(self.hashes[path] == digest, "输入读取期间发生变化：" + str(path))
        self.raw[path] = raw
        self.hashes[path] = digest
        return raw

    def text(self, path: Path) -> str:
        return self.read_bytes(path).decode("utf-8-sig").replace("\r\n", "\n")

    def json(self, path: Path) -> dict:
        return json.loads(self.read_bytes(path).decode("utf-8-sig"))

    def digest(self, path: Path) -> str:
        path = path.resolve()
        require(path.is_file(), "缺少输入文件：" + str(path))
        value = sha(path)
        if path in self.hashes:
            require(self.hashes[path] == value, "输入读取期间发生变化：" + str(path))
        self.hashes[path] = value
        return value

    def unchanged(self) -> None:
        for path, digest in self.hashes.items():
            require(path.is_file() and sha(path) == digest, "输入被并发修改：" + str(path))


def passed(data: dict, label: str) -> None:
    require(isinstance(data, dict), label + " 必须为对象")
    for key in ("errors", "failures", "unexpected_errors", "failed_labels"):
        require(not data.get(key), label + " 存在失败：" + key)
    if "passed" in data:
        require(data["passed"] is True, label + " 缺少 passed:true")
    if "status" in data:
        require(data["status"] == "passed", label + " status 不是 passed")
    if "exit_code" in data:
        require(type(data["exit_code"]) is int and data["exit_code"] == 0,
                label + " exit_code 不是 0")


def visual_only(data: dict, label: str) -> None:
    require(data.get("building_class", "underwater") in {"underwater", None},
            label + " 必须是 underwater 或非建筑观赏资产")
    for field in FALSE_FIELDS:
        require(not data.get(field), label + " 声明了禁止职责：" + field)


def normalize_text(text: str) -> str:
    return text.replace("\r\n", "\n").rstrip("\n") + "\n"


def json_payload(value: dict, raw: bytes | None = None) -> bytes:
    newline = "\r\n" if raw is not None and b"\r\n" in raw else "\n"
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").replace("\n", newline).encode("utf-8")


def verify_hash_field(data: dict, field: str, expected: str, label: str) -> None:
    value = data.get(field)
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-fA-F]{64}", value)
            and value.lower() == expected.lower(), label + " SHA256 不匹配：" + field)


def minimum_failure_snapshot(result: dict, log_text: str) -> tuple[int, int, list[str]]:
    marker = re.search(r"\[minimum-loop\] (\d+) checks, (\d+) failures", log_text)
    require(marker is not None, "minimum-loop 缺少失败汇总标记")
    labels = [line[5:] for line in log_text.splitlines() if line.startswith("FAIL ")]
    require(int(marker.group(2)) == len(labels), "minimum-loop 原日志失败数与标签数不一致")
    if "failure_labels" in result:
        require(result["failure_labels"] == labels, "minimum-loop 报告失败标签与原日志不一致")
    return int(marker.group(1)), int(marker.group(2)), labels


def validate_minimum_baseline(inputs: Inputs, current_result: dict, current_log: str,
                              baseline_path: Path) -> dict:
    require(baseline_path.is_absolute() and baseline_path.name == "report.json",
            "--baseline-verification 必须是绝对 report.json 路径")
    baseline_path = baseline_path.resolve()
    baseline = inputs.json(baseline_path)
    run_dir = Path(baseline.get("run_dir", "")).resolve()
    require(run_dir.is_absolute() and run_dir == baseline_path.parent.resolve(),
            "baseline runner run_dir 必须对应 report.json 父目录")
    current_checks, current_failures, current_labels = minimum_failure_snapshot(current_result, current_log)
    expected = baseline.get("minimum_loop_baseline")
    require(isinstance(expected, dict) and expected.get("passed") is True,
            "baseline 缺少通过的 minimum_loop_baseline 对照证据")
    baseline_result = baseline.get("results", {}).get("minimum-loop")
    require(isinstance(baseline_result, dict) and baseline_result.get("passed") is False and
            type(baseline_result.get("exit_code")) is int and baseline_result["exit_code"] == 1,
            "baseline 必须明确记录 minimum-loop 断言失败，而不是超时或冒充通过")
    require(current_result.get("passed") is False and type(current_result.get("exit_code")) is int and
            current_result["exit_code"] == 1, "当前 minimum-loop 必须是断言失败，不能豁免超时/崩溃")
    baseline_log_path = Path(baseline_result.get("log", "")).resolve()
    require(baseline_log_path.is_file() and baseline_log_path.parent == run_dir,
            "baseline minimum-loop 日志路径无效")
    baseline_log = inputs.text(baseline_log_path)
    require(not re.search(r"SCRIPT ERROR|SHADER ERROR|ERROR:", current_log + baseline_log),
            "minimum-loop 对照不能豁免脚本、着色器或引擎错误")
    baseline_checks, baseline_failures, baseline_labels = minimum_failure_snapshot(baseline_result, baseline_log)
    require(current_checks == baseline_checks and current_failures == baseline_failures and current_failures > 0,
            "当前 minimum-loop 与 baseline checks/failures 不一致或没有失败")
    require(json.dumps(current_labels, ensure_ascii=False, separators=(",", ":")).encode("utf-8") ==
            json.dumps(baseline_labels, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
            "当前 minimum-loop 失败列表与 baseline 不同")
    expected_removed = [
        "World/SunkenSeabed",
        "World/Environment/Animals/SolarCabinFishSchools",
        "World/Zones/Zone1HomeHarbor/Models/太阳能木屋/SolarCabinGulls",
        "World/SeaStructures/rooftop_ranch/RooftopRanchGulls",
    ]
    removed_nodes = expected.get("removednodes", expected.get("removed_nodes"))
    require(removed_nodes == expected_removed,
            "baseline 未声明精确移除四个新增视觉节点")
    fixture_script = run_dir / "project/tests/test_minimum_loop_without_seabed_fauna.gd"
    fixture_test = run_dir / "project/tests/test_minimum_loop.gd"
    require(fixture_script.is_file() and fixture_test.is_file(),
            "baseline fixture 缺少隔离 minimum-loop 输入")
    fixture_text = inputs.text(fixture_script)
    require(all(path in fixture_text for path in expected_removed),
            "baseline fixture 未验证四个视觉节点的移除路径")
    require("extends \"res://tests/test_minimum_loop.gd\"" in fixture_text,
            "baseline fixture 未从当前 minimum-loop 派生")
    require(inputs.digest(fixture_test) == inputs.digest(GODOT / "tests/test_minimum_loop.gd"),
            "baseline fixture 的 minimum-loop 输入不是当前版本")
    fail("minimum-loop 登记 blocked：baseline fixture 格式尚未冻结，未能验证实际执行命令、四节点移除和全部 fixture inputs；失败列表相同不能代替输入验真，禁止登记为集成通过；"
         + json.dumps({"status": "blocked", "full_integration_verified": False,
                       "minimum_loop_passed": False, "checks": current_checks,
                       "failures": current_failures, "failure_labels": current_labels,
                       "baseline_report": baseline_path.as_posix()}, ensure_ascii=False))


def read_reports(inputs: Inputs, report_paths: list[Path], master_hash: str,
                 verification_files: list[Path], baseline_verification: Path | None = None) -> tuple[list[str], dict | None]:
    covered: set[str] = set()
    evidence: list[str] = []
    imports = 0
    integration_evidence: dict | None = None
    markers = {
        "seabed-scene": ("godot/tools/test_seabed_scene.gd", r"\[seabed-scene\] [1-9]\d* checks, 0 failures"),
        "sunken-city": ("godot/tests/test_sunken_city.gd", r"\[sunken-city\] [1-9]\d* checks, 0 failures"),
        "sea-fauna": ("godot/tests/test_sea_fauna.gd", r"\[sea-fauna\] [1-9]\d* checks, 0 failures"),
        "water-layer": ("godot/tests/test_water_layer.gd", r"\[water-layer\] [1-9]\d* checks, 0 failures"),
        "minimum-loop": ("godot/tests/test_minimum_loop.gd", r"\[minimum-loop\] [1-9]\d* checks, 0 failures"),
        "visual-sunken-seabed": ("godot/tools/capture_sunken_seabed.gd", r"\[sunken-seabed-render\] [1-9]\d* checks, 0 failures"),
        "visual-sea-fauna": ("godot/tools/capture_sea_fauna.gd", r"\[sea-fauna-render\] [1-9]\d* checks, 0 failures"),
    }
    for supplied in report_paths:
        require(supplied.is_absolute() and supplied.name == "report.json",
                "--verification 必须是绝对 report.json 路径")
        path = supplied.resolve()
        require(path.as_posix() not in evidence, "重复 verification：" + str(path))
        report = inputs.json(path)
        run_dir = Path(report.get("run_dir", "")).resolve()
        require(run_dir.is_absolute() and run_dir == path.parent.resolve(),
                "runner run_dir 必须对应 report.json 父目录")
        results = report.get("results")
        require(isinstance(results, dict), "runner 报告缺少 results：" + str(path))
        for name, result in results.items():
            if name not in TARGETS:
                continue
            if name == "minimum-loop" and baseline_verification is not None:
                require(result.get("passed") is False, "minimum-loop 对照登记不得标记为通过")
                require(result.get("completion_marker") is True, name + " 缺少完成标记")
            else:
                passed(result, name)
                require(result.get("passed") is True and type(result.get("exit_code")) is int and
                        result["exit_code"] == 0, name + " 必须 passed:true 且 exit_code:0")
                require(result.get("completion_marker") is True, name + " 缺少完成标记")
            log = Path(result.get("log", "")).resolve()
            require(log.is_file() and log.parent == run_dir, name + " 日志路径越界或不存在")
            text = inputs.text(log)
            if name != "minimum-loop" or baseline_verification is None:
                require(not re.search(r"SCRIPT ERROR|SHADER ERROR|ERROR:|\bFAIL\b", text),
                        name + " 原日志存在错误")
            test_path, marker = markers[name]
            if name == "minimum-loop" and baseline_verification is not None:
                marker = r"\[minimum-loop\] [1-9]\d* checks, [1-9]\d* failures"
            require(re.search(marker, text), name + " 原日志没有结束标记")
            if name == "minimum-loop" and baseline_verification is not None:
                integration_evidence = validate_minimum_baseline(inputs, result, text, baseline_verification)
            if name.startswith("visual-"):
                require(result.get("renderer") == "real", name + " 必须使用真实渲染器")
                require("--headless" not in result.get("command", []), name + " 禁止 headless")
            isolated = run_dir / "project"
            files_to_check = [ROOT / test_path, *verification_files]
            for current in files_to_check:
                if current.is_relative_to(GODOT):
                    counterpart = isolated / current.relative_to(GODOT)
                elif current.is_relative_to(ROOT):
                    counterpart = isolated / current.relative_to(ROOT)
                else:
                    fail("verification 文件必须位于工程内：" + str(current))
                require(counterpart.is_file(), name + " 隔离工程缺少：" + rel(current))
                require(inputs.digest(counterpart) == inputs.digest(current),
                        name + " 隔离工程 SHA 不对应当前文件：" + rel(current))
            if name == "sunken-city":
                structure = isolated / "outputs/sunken-city-structure.json"
                require(structure.is_file(), "sunken-city 缺少结构证据")
                structure_data = inputs.json(structure)
                passed(structure_data, "sunken-city 结构证据")
                require(structure_data.get("source_master_sha256") == master_hash,
                        "结构证据不匹配当前 v005 主源")
                counts = structure_data.get("counts")
                require(isinstance(counts, dict), "sunken-city 结构证据缺少 counts")
                require(counts.get("components") == 50 and counts.get("instances") == 388,
                        "sunken-city 结构证据组件/实例数量错误")
            covered.add(name)
        imported = report.get("asset_import")
        if imported is not None:
            passed(imported, "asset_import")
            require(type(imported.get("exit_code")) is int and imported["exit_code"] == 0,
                    "asset_import exit_code 不是 0")
            log = Path(imported.get("log", "")).resolve()
            require(log.is_file() and log.parent == run_dir, "asset_import 日志路径越界")
            require(not re.search(r"SCRIPT ERROR|SHADER ERROR|ERROR:|\bFAIL\b", inputs.text(log)),
                    "asset_import 原日志存在错误")
            imports += 1
        evidence.append(path.as_posix())
    require(covered == TARGETS, "报告必须覆盖七个目标 runner：" + "、".join(sorted(TARGETS)))
    require(imports > 0, "至少一份 runner 报告必须有成功的 asset_import")
    return evidence, integration_evidence


def validate_source_reports(inputs: Inputs, master_hash: str, catalog_hash: str,
                            catalog: dict) -> tuple[dict, dict, dict]:
    paths = [WORK / "source_verification.json", WORK / "package_verification.json", WORK / "skill_verification.json"]
    reports = [inputs.json(path) for path in paths]
    for label, data in zip(("source_verification", "package_verification", "skill_verification"), reports):
        passed(data, label)
        require(data.get("suite", "sunken_city") == "sunken_city", label + " 套件错误")
        for field in ("source_sha256", "source_master_sha256", "master_sha256",
                      "source_sha256_before", "source_sha256_after"):
            if field in data:
                verify_hash_field(data, field, master_hash, label)
    source_report, package_report, skill_report = reports
    require(source_report.get("components") == 50 and source_report.get("instances") == 388,
            "source_verification 不是 50/388")
    require(source_report.get("reopened_from_disk") is True and
            source_report.get("source_unchanged_on_reopen") is True,
            "source_verification 未证明当前主源已重开且字节未变")
    require(type(package_report.get("packages_reopened")) is int and
            package_report["packages_reopened"] == 50,
            "package_verification 未证明 50 个包已重开")
    require(package_report.get("expected_package_count") == 50 and package_report.get("catalog_updated") is True,
            "package_verification 未完成 50 包 catalog 提交")
    verify_hash_field(package_report, "catalog_sha256_after", catalog_hash, "package_verification/catalog")
    require(package_report.get("run_id") and package_report.get("run_id") == skill_report.get("run_id"),
            "package/skill 不是同一 run_id")
    package_rows = {x.get("key"): x for x in package_report.get("components", [])}
    skill_rows = {x.get("key"): x for x in skill_report.get("components", [])}
    require(set(package_rows) == {x["key"] for x in catalog["components"]},
            "package 报告组件集合不等于 v005 catalog")
    require(set(skill_rows) == set(package_rows), "skill 报告组件集合不完整")
    for entry in catalog["components"]:
        key = entry["key"]
        package_row, skill_row = package_rows[key], skill_rows[key]
        passed(package_row, "package/" + key)
        passed(skill_row, "skill/" + key)
        component_source = ROOT / entry["component_blend"]
        actual = inputs.digest(component_source)
        verify_hash_field(package_row, "package_sha256", actual, key + "/package")
        verify_hash_field(skill_row, "package_sha256_before", actual, key + "/skill")
        verify_hash_field(skill_row, "package_sha256_after", actual, key + "/skill")
        verify_hash_field(entry, "source_sha256", actual, key + "/catalog")
    return source_report, package_report, skill_report


def old_export_protection(inputs: Inputs) -> dict:
    old_export = inputs.json(V004_EXPORT)
    passed(old_export, "v004 export_manifest")
    require(old_export.get("version") == "v004", "v004 export 版本错误")
    protected = old_export.get("protected_sources")
    require(isinstance(protected, dict) and protected, "v004 protected_sources 缺失")
    old_rows = old_export.get("components", [])
    require(len(old_rows) == 50 and len({row["key"] for row in old_rows}) == 50,
            "v004 export 组件集合不完整或重复")
    required_sources = {rel(OLD_MASTER), rel(PALETTE)}
    for row in old_rows:
        source_path = project_path(row["source"])
        require(source_path.is_relative_to((V004 / "component_packages").resolve()),
                "v004 组件 source 不在 v004/component_packages：" + row["source"])
        required_sources.add(rel(source_path))
        digest = inputs.digest(source_path)
        verify_hash_field(row, "source_sha256_before", digest, row["key"] + "/v004 source before")
        verify_hash_field(row, "source_sha256_after", digest, row["key"] + "/v004 source after")
    require(required_sources <= set(protected), "v004 protected_sources 未覆盖全部旧包、主源和色盘")
    for name, expected in protected.items():
        path = project_path(name)
        verify_hash_field({"sha256": inputs.digest(path)}, "sha256", expected, "v004 protected/" + name)
    require(inputs.digest(OLD_MASTER) == old_export.get("protected_sources", {}).get(rel(OLD_MASTER)),
            "v004 主源保护摘要不一致")
    require(inputs.digest(PALETTE) == old_export.get("protected_sources", {}).get(rel(PALETTE)),
            "公共色盘被修改")
    return old_export


def compare_assembly_scope(inputs: Inputs) -> None:
    archive = V004 / "export/v004/runtime_preserved_before_v005_fauna.zip"
    inputs.digest(archive)
    with zipfile.ZipFile(archive) as zf:
        old = zf.read("godot/scenes/world/sunken_city.tscn").decode("utf-8")
    current = inputs.text(ASSEMBLY)
    expected = normalize_text(old).replace('metadata/asset_version = "v004"', 'metadata/asset_version = "v005"', 1)
    require(normalize_text(current) == expected, "388-node 总装块除 metadata 版本外发生未授权修改")
    require(not re.search(r'edge_ramp_(?:west|east|north|south)_\d{2}', current),
            "总装仍含已撤下的 edge_ramp 节点")
    require(len(re.findall(r'^\[node name="', current, re.M)) == 389,
            "总装节点数量不是根节点加 388 个实例")


def compare_main_scope(inputs: Inputs, build: dict) -> None:
    before_path = WORK / "import/main_before_v005.tscn"
    inputs.digest(before_path)
    require(inputs.digest(MAIN) == build.get("main_sha256_after"), "main_sha256_after 不匹配当前 main.tscn")
    require(inputs.digest(before_path) == build.get("main_sha256_before"), "main_before SHA 不匹配 runtime_build")
    before = normalize_text(inputs.text(before_path))
    current = normalize_text(inputs.text(MAIN))
    ext = '[ext_resource type="PackedScene" path="res://scenes/world/sunken_seabed.tscn" id="39_sunken_seabed"]\n'
    node = '[node name="SunkenSeabed" parent="World" instance=ExtResource("39_sunken_seabed")]\n'
    node_block = node + "\n"
    require(current.count(ext) == 1 and current.count(node_block) == 1, "main.tscn 海床引用必须恰好一份")
    reduced = current.replace(ext, "", 1).replace(node_block, "", 1)
    require(reduced == before, "main.tscn 除独立 SunkenSeabed 接入外存在额外修改")


def validate_runtime(inputs: Inputs, catalog: dict) -> list[Path]:
    runtime = inputs.json(RUNTIME_MANIFEST)
    passed(runtime, "runtime_manifest")
    require(runtime.get("version") == "v005" and runtime.get("pure_visual") is True,
            "runtime_manifest 不是 v005 pure_visual")
    require(runtime.get("source_master_sha256") == inputs.digest(MASTER),
            "runtime_manifest 主源 SHA 不匹配")
    require(len(runtime.get("components", [])) == 50 and len(runtime.get("instances", [])) == 388,
            "runtime_manifest 不是 50/388")
    require(not any(str(x.get("instance_id", "")).startswith("edge_ramp_") for x in runtime["instances"]),
            "runtime_manifest 仍含 edge_ramp")
    require(project_path(runtime.get("assembly")) == ASSEMBLY.resolve(), "runtime assembly 路径错误")
    for path in sorted((GODOT / "scenes/components/scenery/sunken_city").glob("*.tscn")):
        text = inputs.text(path)
        require('metadata/asset_version = "v005"' in text, "prefab 缺少 v005 metadata：" + rel(path))
    return [ASSEMBLY, RUNTIME_MANIFEST]


def build_v005_export(inputs: Inputs, catalog: dict, old_export: dict, evidence: list[str]) -> tuple[dict, dict]:
    old_by_key = {x["key"]: x for x in old_export.get("components", [])}
    require(len(old_by_key) == 50, "v004 export 不是 50 个组件")
    current = inputs.json(V005_EXPORT)
    require(current.get("suite") == "sunken_city" and current.get("version") == "v005",
            "v005 export 套件/版本错误")
    entries = []
    for catalog_entry in catalog["components"]:
        key = catalog_entry["key"]
        old = old_by_key.get(key)
        require(old is not None, "v004 export 缺组件：" + key)
        v004_opt = project_path(old["optimized_source"])
        v005_opt = project_path("art_source/scenes/sunken_city/v005/export/v005/" + key + "_optimized.blend")
        glb = project_path(old["glb"])
        package = project_path(catalog_entry["component_blend"])
        old_opt_hash = inputs.digest(v004_opt)
        new_opt_hash = inputs.digest(v005_opt)
        require(old_opt_hash == new_opt_hash == old["optimized_sha256"],
                key + " v005 optimized 不是 v004 已验收同字节复用")
        require(inputs.digest(glb) == old["glb_sha256"], key + " GLB 与 v004 验收摘要不一致")
        source_hash = inputs.digest(package)
        item = copy.deepcopy(old)
        item.update(
            version="v005",
            source=rel(package),
            source_sha256=source_hash,
            source_sha256_before=source_hash,
            source_sha256_after=source_hash,
            optimized_source=rel(v005_opt),
            optimized_sha256=new_opt_hash,
            glb=rel(glb),
            glb_sha256=inputs.digest(glb),
            source_preserved=True,
            reuse_provenance={
                "kind": "existing_bytes_reused",
                "previous_version": "v004",
                "previous_source": old["source"],
                "previous_source_sha256": old.get("source_sha256_after", old.get("source_sha256_before")),
                "previous_optimized_source": old["optimized_source"],
                "previous_optimized_sha256": old["optimized_sha256"],
                "previous_glb": old["glb"],
                "previous_glb_sha256": old["glb_sha256"],
                "fidelity_verification": "D:/projects/sea-work/sunken_city/v004/import/fidelity_verification.json",
                "fidelity_source": "v004_existing_fidelity_review",
            },
        )
        entries.append(item)
    current.update(
        suite="sunken_city",
        version="v005",
        passed=True,
        stage="exports_reused_from_v004_geometry_with_v005_source_paths",
        source_master=rel(MASTER),
        source_master_sha256=inputs.digest(MASTER),
        palette=rel(PALETTE),
        palette_sha256=inputs.digest(PALETTE),
        source_unchanged=True,
        components=entries,
        protected_sources={
            rel(MASTER): inputs.digest(MASTER),
            rel(PALETTE): inputs.digest(PALETTE),
            **{rel(ROOT / e["source"]): e["source_sha256"] for e in entries},
        },
        previous_protected_sources=copy.deepcopy(old_export.get("protected_sources", {})),
        verification=evidence,
        fidelity_verification="D:/projects/sea-work/sunken_city/v004/import/fidelity_verification.json",
        reuse_policy="No re-optimization; v005 optimized files are byte-identical copies of v004 accepted files.",
    )
    return current, {x["key"]: x for x in entries}


def seabed_manifest(inputs: Inputs, ledger_route: str) -> tuple[dict, list[Path]]:
    data_dir = GODOT / "terrain/sunken_seabed"
    require(data_dir.is_dir(), "缺少 Terrain3D 海床数据目录：" + str(data_dir))
    region_files = sorted(data_dir.glob("terrain3d*.res"))
    require(len(region_files) == 4, "Terrain3D 海床必须恰好 4 个 terrain3d*.res region 资源")
    author = GODOT / "tools/author_seabed_terrain.gd"
    scene = GODOT / "scenes/world/sunken_seabed.tscn"
    material = GODOT / "assets/materials/sunken_city/seabed_material.tres"
    source_files = [*region_files, author, data_dir / "assets.tres", data_dir / "albedo.res", data_dir / "normal.res", material,
                    GODOT / "assets/materials/sunken_city/seabed.gdshader"]
    for path in [*source_files, scene, material]:
        inputs.digest(path)
    scene_text = inputs.text(scene)
    require('data_directory = "res://terrain/sunken_seabed"' in scene_text,
            "海床场景未绑定独立 Terrain3D data_directory")
    require('collision_mode = 0' in scene_text and 'metadata/visual_only = true' in scene_text,
            "海床场景不是纯 visual 无碰撞")
    manifest = {
        "schema": "sea.sunken_city.seabed_manifest.v1",
        "asset_id": SEABED_ID,
        "suite": "sunken_city",
        "version": "v005",
        "stage": "runtime_component_verified",
        "source": rel(region_files[0]),
        "source_sha256": inputs.digest(region_files[0]),
        "source_files": [rel(p) for p in source_files],
        "source_files_sha256": {rel(p): inputs.digest(p) for p in source_files},
        "authoring_tool": rel(author),
        "authoring_tool_sha256": inputs.digest(author),
        "scene": rel(scene),
        "scene_sha256": inputs.digest(scene),
        "runtime_path": rel(scene),
        "runtime_sha256": inputs.digest(scene),
        "data_directory": "godot/terrain/sunken_seabed",
        "region_count": 4,
        "region_size": 256,
        "vertex_spacing": 2.0,
        "collision_mode": 0,
        "visual_only": True,
        "water_layer": "submerged",
        "water_layer_role": "part",
        "asset_ledger": ledger_route + "#" + SEABED_ID,
        "license": "pending_legacy_provenance_review",
        "commercial_rights_status": "pending",
        "reference_rights_verified": False,
        "note": "Terrain3D source is persisted Godot 4-region data plus authoring tool; no Blender source claimed.",
    }
    return manifest, [*source_files, scene, material]


def fauna_specs(inputs: Inputs, ledger_route: str) -> tuple[list[dict], list[Path]]:
    specs = [
        ("SEA-DECO-SOLAR-FISH-VARIANTS", "太阳屋周边鱼群变体", "godot/src/ambient/decorative_fish_school.gd", "godot/scenes/decorations/animals/solar_cabin_fish_schools.tscn", "surface", "solar_cabin_fish_schools"),
        ("SEA-DECO-SOLAR-GULLS", "太阳屋屋顶海鸥", "godot/src/ambient/building_gull_flock.gd", "godot/scenes/decorations/animals/solar_cabin_gulls.tscn", "surface", "solar_cabin_gulls"),
        ("SEA-DECO-RANCH-GULLS", "屋顶牧场海鸥", "godot/src/ambient/building_gull_flock.gd", "godot/scenes/decorations/animals/rooftop_ranch_gulls.tscn", "surface", "rooftop_ranch_gulls"),
    ]
    rows, paths = [], []
    for aid, name, source_value, prefab_value, layer, key in specs:
        source, prefab = ROOT / source_value, ROOT / prefab_value
        inputs.digest(source); inputs.digest(prefab)
        source_scene = inputs.text(prefab)
        require('metadata/visual_only = true' in source_scene and 'metadata/water_layer = "surface"' in source_scene,
                aid + " 不是纯 visual surface fauna")
        manifest_path = V005 / (key + "_manifest.json")
        manifest = {
            "schema": "sea.sunken_city.runtime_asset_manifest.v1",
            "asset_id": aid,
            "suite": "sunken_city",
            "version": "v005",
            "stage": "runtime_component_verified",
            "source": source_value,
            "source_sha256": inputs.digest(source),
            "prefab": prefab_value,
            "prefab_sha256": inputs.digest(prefab),
            "runtime_path": prefab_value,
            "runtime_sha256": inputs.digest(prefab),
            "asset_ledger": ledger_route + "#" + aid,
            "classification": {"category": "decoration", "subcategory": "animals"},
            "visual_only": True,
            "water_layer": "none",
            "water_layer_role": "none",
            "placement_water_layer": layer,
            "collision": False,
            "interactive": False,
            "emission": False,
            "license": "pending_legacy_provenance_review",
            "commercial_rights_status": "pending",
            "reference_rights_verified": False,
            "dependencies": ["godot/scenes/decorations/animals/fish_school.tscn", "godot/scenes/decorations/animals/bird.tscn"] if "gull" in key else ["godot/scenes/decorations/animals/fish_school.tscn"],
            "note": "程序化运行装饰复用现有 fish/bird source；不创建 Blender 源，不引入玩法状态。",
        }
        rows.append({
            "asset_id": aid,
            "name": name,
            "domain": "scenes",
            "suite": "sunken_city",
            "version": "v005",
            "scope": "scene_local",
            "building_class": None,
            "responsibility": "visual_only",
            "category": "surface_animal_decoration",
            "classification": {"category": "decoration", "subcategory": "animals"},
            "water_layer": "none",
            "water_layer_role": "none",
            "placement_water_layer": layer,
            "source": source_value,
            "source_sha256": inputs.digest(source),
            "manifest": rel(manifest_path),
            "stage": "runtime_component_verified",
            "maintenance_status": "runtime_component_verified",
            "runtime_path": prefab_value,
            "runtime_sha256": inputs.digest(prefab),
            "prefab": prefab_value,
            "prefab_sha256": inputs.digest(prefab),
            "runtime_integrated": True,
            "runtime_status": "verified",
            "prefab_status": "verified",
            "runtime_verified": True,
            "runtime_validation": "sea-fauna_and_visual-sea-fauna_passed",
            "license": "pending_legacy_provenance_review",
            "commercial_rights_status": "pending",
            "reference_rights_verified": False,
            "consumer_features": ["SEA-ASSET", "SEA-AMBIENT"],
            "verification": [],
            "visual_only": True,
            "collision": False,
            "interactive": False,
            "emission": False,
            "dependencies": manifest["dependencies"],
            "source_provenance": "procedural source reused; no blend fabricated",
        })
        rows[-1].update({field: False for field in FALSE_FIELDS if field not in rows[-1]})
        paths.extend([source, prefab])
    return rows, paths


def inventory_allowlist(inputs: Inputs, catalog: dict, seabed_paths: list[Path], fauna_paths: list[Path]) -> list[Path]:
    paths = [MAIN, MAIN_SCRIPT, ASSEMBLY, RUNTIME_MANIFEST,
             GODOT / "tools/capture_sunken_city.gd", GODOT / "tests/test_sunken_city.gd",
             GODOT / "tools/test_seabed_scene.gd", GODOT / "tools/capture_sunken_seabed.gd",
             GODOT / "tests/test_sea_fauna.gd", GODOT / "tools/capture_sea_fauna.gd",
             GODOT / "assets/materials/sunken_city/gloss.tres", GODOT / "assets/materials/sunken_city/matte.tres",
             GODOT / "assets/materials/sunken_city/metal.tres", GODOT / "assets/materials/sunken_city/seabed_material.tres",
             GODOT / "assets/materials/sunken_city/seabed.gdshader", GODOT / "assets/materials/sunken_city/seabed.gdshader.uid",
             GODOT / "scenes/decorations/animals/fish_school.tscn", GODOT / "scenes/decorations/animals/bird.tscn",
             GODOT / "src/ambient/decorative_fish_school.gd", GODOT / "src/ambient/building_gull_flock.gd",
             GODOT / "src/ambient/fish_flock_group.gd", GODOT / "src/ambient/bird.gd", GODOT / "src/ambient/birds.gd",
             GODOT / "assets/baked/birds.json"]
    paths.extend(GODOT / "scenes/components/scenery/sunken_city" / (x["key"] + ".tscn") for x in catalog["components"])
    paths.extend(GODOT / "assets/models/scenery/sunken_city" / x["key"] / (x["key"] + suffix)
                 for x in catalog["components"] for suffix in (".glb", ".glb.import"))
    paths.extend([GODOT / "assets/models/scenery/sunken_city/runtime_manifest.json"])
    paths.extend(seabed_paths)
    paths.extend(fauna_paths)
    result = []
    seen = set()
    for path in paths:
        path = path.resolve()
        if path in seen:
            continue
        require(path.is_file(), "runtime_inventory 白名单资源缺失：" + str(path))
        seen.add(path)
        inputs.digest(path)
        result.append(path)
    return result


def update_ledger(inputs: Inputs, catalog: dict, export: dict, export_entries: dict,
                  seabed_row: dict, fauna_rows: list[dict], evidence: list[str],
                  fidelity_path: str) -> tuple[dict, dict, dict]:
    index = inputs.json(INDEX)
    route = index["domains"]["scenes"]
    ledger_path = project_path(route["ledger"])
    require(ledger_path.resolve() == LEDGER.resolve(), "scenes ledger 路由变化，拒绝越权")
    book = inputs.json(ledger_path)
    rows = book[route["asset_key"]]
    all_ids = {row["asset_id"] for row in rows}
    require(len(all_ids) == len(rows), "全局 scenes 账本存在重复 AssetID")
    export_ids = {x["asset_id"] for x in export["components"]} | {ASSEMBLY_ID}
    new_ids = {SEABED_ID} | FAUNA_IDS
    suite_rows = [row for row in rows if row["asset_id"] in export_ids | FUTILITY | new_ids]
    current_old = [row for row in suite_rows if row["asset_id"] in export_ids]
    require(len(current_old) == 51 and {x["asset_id"] for x in current_old} == export_ids,
            "当前旧城组件与总装不是 51 行，拒绝升级")
    require(all(row.get("version") in {"v004", "v005"} for row in current_old),
            "旧城已出现非 v004/v005 版本，拒绝降级覆盖")
    require({x["asset_id"] for x in suite_rows if x["asset_id"] in FUTILITY} == FUTILITY,
            "两条 retired v002 记录不完整")
    for row in suite_rows:
        if row["asset_id"] in FUTILITY:
            require(row.get("version") == "v002", row["asset_id"] + " retired 记录不是 v002")
    for row in suite_rows:
        if row["asset_id"] in new_ids:
            require(row.get("suite") == "sunken_city" and row.get("version") == "v005",
                    "新增 AssetID 已被其它版本/套件占用：" + row["asset_id"])

    updated = copy.deepcopy(book)
    by_id = {row["asset_id"]: row for row in updated[route["asset_key"]]}
    export_by_id = {x["asset_id"]: x for x in export["components"]}
    runtime = inputs.json(RUNTIME_MANIFEST)
    runtime_by_key = {x["key"]: x for x in runtime.get("components", [])}
    catalog_by_id = {x["component_id"]: x for x in catalog["components"]}
    for old in current_old:
        aid = old["asset_id"]
        new = by_id[aid]
        old_snapshot = copy.deepcopy(new)
        if aid == ASSEMBLY_ID:
            new.update(
                version="v005",
                source=rel(MASTER), source_sha256=inputs.digest(MASTER),
                manifest=rel(V005 / "asset_manifest.json"),
                runtime_path=rel(ASSEMBLY), runtime_sha256=inputs.digest(ASSEMBLY),
                prefab=rel(ASSEMBLY), prefab_sha256=inputs.digest(ASSEMBLY),
                runtime_integrated=True, runtime_status="verified", prefab_status="verified",
                runtime_verified=True, source_verified=True,
                runtime_validation="seabed-scene_and_sunken-city_and_visual-sunken-seabed_passed",
                verification=evidence, fidelity_verification=fidelity_path,
                export_manifest=rel(V005_EXPORT), component_count=50, instance_count=388,
                total_assembly={"components": 50, "instances": 388, "city_instances": 388,
                                "seabed_scene": rel(GODOT / "scenes/world/sunken_seabed.tscn"),
                                "fauna_assemblies": sorted(FAUNA_IDS)},
                source_master_sha256=inputs.digest(MASTER),
                palette_sha256=inputs.digest(PALETTE),
                optimized_sources=[{"asset_id": x["asset_id"], "optimized_source": x["optimized_source"], "optimized_sha256": x["optimized_sha256"], "reuse_provenance": x["reuse_provenance"]} for x in export["components"]],
            )
            visual_only(new, aid)
        else:
            entry = export_by_id[aid]
            cat = catalog_by_id[aid]
            runtime_entry = runtime_by_key[cat["key"]]
            source = project_path(entry["source"])
            prefab = GODOT / "scenes/components/scenery/sunken_city" / (cat["key"] + ".tscn")
            new.update(
                version="v005", source=rel(source), source_sha256=inputs.digest(source),
                manifest=rel(V005 / "component_packages" / cat["key"] / "asset_manifest.json"),
                runtime_path=entry["glb"], runtime_sha256=inputs.digest(project_path(entry["glb"])),
                prefab=rel(prefab), prefab_sha256=inputs.digest(prefab),
                runtime_integrated=True, runtime_status="verified", prefab_status="verified",
                runtime_verified=True, source_verified=True,
                runtime_validation="sunken-city_and_visual-sunken-city_passed",
                verification=evidence, fidelity_verification=fidelity_path,
                export_manifest=rel(V005_EXPORT), optimized_source=entry["optimized_source"],
                optimized_sha256=entry["optimized_sha256"], glb=entry["glb"], glb_sha256=entry["glb_sha256"],
                triangles=entry["triangles_after"], exported_triangles=entry["triangles_after"],
                triangles_before=entry["triangles_before"], triangles_after=entry["triangles_after"],
                reduction_ratio=entry["reduction_ratio"], operations=entry["operations"],
                material_roles=cat["material_roles"], source_preserved=True,
                reuse_provenance=entry["reuse_provenance"], runtime_component=runtime_entry,
            )
            visual_only(new, aid)
        previous = list(new.get("previous_sources", []))
        if old_snapshot.get("version") != "v005":
            if not any(item.get("version") == old_snapshot.get("version") and item.get("source") == old_snapshot.get("source") for item in previous if isinstance(item, dict)):
                previous.append(old_snapshot)
        new["previous_sources"] = previous
        by_id[aid] = new

    seabed_row["verification"] = evidence
    fauna_rows = copy.deepcopy(fauna_rows)
    for row in fauna_rows:
        row["verification"] = evidence
        row["fidelity_verification"] = fidelity_path
    for row in [seabed_row, *fauna_rows]:
        if row["asset_id"] in by_id:
            require(by_id[row["asset_id"]].get("source") == row["source"] and
                    by_id[row["asset_id"]].get("manifest") == row["manifest"],
                    "已有新增 AssetID 路由不符，拒绝覆盖：" + row["asset_id"])
            by_id[row["asset_id"]].update(row)
        else:
            updated[route["asset_key"]].append(row)
            by_id[row["asset_id"]] = row
    require([row for row in updated[route["asset_key"]] if row["asset_id"] not in export_ids | new_ids] ==
            [row for row in rows if row["asset_id"] not in export_ids | new_ids],
            "修改了本批范围外的账本记录")
    updated_ids = {row["asset_id"] for row in updated[route["asset_key"]]}
    require(len(updated_ids) == len(updated[route["asset_key"]]), "更新后账本 AssetID 重复")
    require(all(next(row for row in updated[route["asset_key"]] if row["asset_id"] == aid) == old
                for aid, old in ((row["asset_id"], row) for row in rows if row["asset_id"] in FUTILITY)),
            "retired v002 记录发生修改")

    source_index = inputs.json(SOURCE_INDEX)
    updated_index = copy.deepcopy(source_index)
    updated_index["sources"] = []
    for domain, domain_route in index["domains"].items():
        if domain == "scenes":
            domain_book = updated
        else:
            domain_book = inputs.json(project_path(domain_route["ledger"]))
        updated_index["sources"].extend({field: row[field] for field in ("asset_id", "source", "source_sha256", "manifest")}
                                        for row in domain_book[domain_route["asset_key"]])
    return updated, updated_index, {"ledger_path": ledger_path, "route": route}


def update_inventory(inputs: Inputs, allowlist: list[Path], updated_inventory: dict,
                     new_ids: dict[str, str]) -> dict:
    by_path = {item["path"]: item for item in updated_inventory.get("resources", [])}
    require(len(by_path) == len(updated_inventory.get("resources", [])), "runtime_inventory 路径重复")
    allowed_names = {rel(path) for path in allowlist}
    for path in allowlist:
        name = rel(path)
        previous = by_path.get(name)
        item = copy.deepcopy(previous) if previous else {"path": name, "asset_id": new_ids.get(name)}
        item["sha256"] = inputs.digest(path)
        item["bytes"] = path.stat().st_size
        item.setdefault("status", "runtime_resource_verified")
        if name in new_ids:
            item["asset_id"] = new_ids[name]
        if previous is None:
            updated_inventory["resources"].append(item)
            by_path[name] = item
        else:
            previous.update(item)
    for old, new in zip(inputs.json(INVENTORY)["resources"], updated_inventory["resources"]):
        if old["path"] not in allowed_names:
            require(old == new, "修改了 runtime_inventory 白名单外记录：" + old["path"])
    return updated_inventory


def atomic_apply(inputs: Inputs, changes: dict[Path, bytes]) -> None:
    staged: dict[Path, Path] = {}
    committed: list[tuple[Path, bytes, bytes | None]] = []
    try:
        for path, payload in changes.items():
            require(path.parent.is_dir(), "写入父目录不存在：" + str(path.parent))
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + ".", suffix=".tmp", delete=False) as stream:
                staged[path] = Path(stream.name)
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
        inputs.unchanged()
        for path, payload in changes.items():
            before = inputs.raw.get(path)
            if before is None and path.exists():
                before = inputs.read_bytes(path)
            require((before is None and not path.exists()) or (before is not None and path.read_bytes() == before),
                    "写入目标被并发修改：" + str(path))
            os.replace(staged[path], path)
            committed.append((path, payload, before))
    except BaseException:
        for path, payload, before in reversed(committed):
            if path.is_file() and sha(path) == hashlib.sha256(payload).hexdigest():
                if before is None:
                    path.unlink()
                else:
                    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + ".rollback.", suffix=".tmp", delete=False) as stream:
                        rollback = Path(stream.name)
                        stream.write(before)
                        stream.flush()
                        os.fsync(stream.fileno())
                    os.replace(rollback, path)
        raise
    finally:
        for temp in staged.values():
            if temp.exists():
                temp.unlink()


def register(args: argparse.Namespace) -> int:
    inputs = Inputs()
    report_dir = args.report_dir.resolve()
    require(report_dir.is_dir() and not report_dir.is_relative_to(ROOT.resolve()),
            "报告目录必须已存在且位于工程外")
    master_hash = inputs.digest(MASTER)
    old_export = old_export_protection(inputs)
    catalog_path = V005 / "component_catalog.json"
    catalog = inputs.json(catalog_path)
    require(len(catalog.get("components", [])) == 50, "v005 catalog 不是 50 个组件")
    catalog_hash = inputs.digest(catalog_path)
    validate_source_reports(inputs, master_hash, catalog_hash, catalog)
    export, export_entries = build_v005_export(inputs, catalog, old_export, [])
    runtime_files = validate_runtime(inputs, catalog)
    build = inputs.json(WORK / "import/runtime_build.json")
    passed(build, "runtime_build")
    require(build.get("components") == 50 and build.get("instances") == 388,
            "runtime_build 不是 50/388")
    compare_assembly_scope(inputs)
    compare_main_scope(inputs, build)

    v004_fidelity = (WORK.parent / "v004/import/fidelity_verification.json").resolve()
    require(v004_fidelity.is_file(), "缺少 v004 保真来源证据：" + str(v004_fidelity))
    fidelity = inputs.json(v004_fidelity)
    passed(fidelity, "v004 fidelity_verification")
    require(fidelity.get("source_protected") is True and fidelity.get("visual_review") == "passed",
            "v004 保真来源必须 source_protected:true 且 visual_review:passed")
    require(set(fidelity.get("views", [])) >= {"game_angle", "front", "back", "side"},
            "v004 保真来源缺少四视角")

    seabed_manifest_data, seabed_paths = seabed_manifest(inputs, "assets/registry/ledgers/scenes.json")
    fauna_rows, fauna_paths = fauna_specs(inputs, "assets/registry/ledgers/scenes.json")
    allowlist = inventory_allowlist(inputs, catalog, seabed_paths, fauna_paths)
    verification_files = [MAIN, MAIN_SCRIPT, ASSEMBLY, RUNTIME_MANIFEST,
                          GODOT / "scenes/world/sunken_seabed.tscn", *seabed_paths, *fauna_paths]
    evidence, integration_evidence = read_reports(
        inputs, args.verification, master_hash, list(dict.fromkeys(verification_files)),
        args.baseline_verification,
    )
    export, export_entries = build_v005_export(inputs, catalog, old_export, evidence)
    seabed_manifest_data["verification"] = evidence
    for row in fauna_rows:
        row["verification"] = evidence

    updated_book, updated_source_index, ledger_info = update_ledger(
        inputs, catalog, export, export_entries, {
            "asset_id": SEABED_ID,
            "name": "SunkenSeabed Terrain3D 海床",
            "domain": "scenes", "suite": "sunken_city", "version": "v005",
            "scope": "scene_local", "building_class": "underwater", "responsibility": "visual_only",
            "category": "underwater_terrain_visual", "classification": {"category": "decoration", "subcategory": "underwater_terrain"},
            "water_layer": "submerged", "water_layer_role": "part", "source": seabed_manifest_data["source"],
            "source_sha256": seabed_manifest_data["source_sha256"], "manifest": rel(V005 / "seabed_manifest.json"),
            "stage": "runtime_component_verified", "maintenance_status": "runtime_component_verified",
            "runtime_path": seabed_manifest_data["runtime_path"], "runtime_sha256": seabed_manifest_data["runtime_sha256"],
            "prefab": seabed_manifest_data["runtime_path"], "prefab_sha256": seabed_manifest_data["runtime_sha256"],
            "runtime_integrated": True, "runtime_status": "verified", "prefab_status": "verified",
            "runtime_verified": True, "source_verified": True,
            "runtime_validation": "seabed-scene_and_visual-sunken-seabed_passed",
            "source_files": seabed_manifest_data["source_files"], "source_files_sha256": seabed_manifest_data["source_files_sha256"],
            "authoring_tool": seabed_manifest_data["authoring_tool"], "authoring_tool_sha256": seabed_manifest_data["authoring_tool_sha256"],
            "region_count": 4, "visual_only": True, "collision": False,
            "license": "pending_legacy_provenance_review", "commercial_rights_status": "pending",
            "reference_rights_verified": False, "consumer_features": ["SEA-ASSET", "SEA-TERRAIN"],
        }, fauna_rows, evidence, v004_fidelity.as_posix(),
    )
    updated_inventory = update_inventory(inputs, allowlist, inputs.json(INVENTORY), {
        rel(MAIN): None, rel(MAIN_SCRIPT): None,
        rel(GODOT / "scenes/world/sunken_seabed.tscn"): SEABED_ID,
        **{rel(path): aid for aid, path in [
            ("SEA-DECO-SOLAR-FISH-VARIANTS", GODOT / "scenes/decorations/animals/solar_cabin_fish_schools.tscn"),
            ("SEA-DECO-SOLAR-GULLS", GODOT / "scenes/decorations/animals/solar_cabin_gulls.tscn"),
            ("SEA-DECO-RANCH-GULLS", GODOT / "scenes/decorations/animals/rooftop_ranch_gulls.tscn"),
        ]},
    })

    # 只构造变化，不在 dry-run 写任何目标或新 manifest。
    changes: dict[Path, bytes] = {}
    output_json = {
        V005_EXPORT: export,
        V005 / "seabed_manifest.json": seabed_manifest_data,
    }
    # 新 manifest 只进入写入计划，不作为已存在的验证输入。
    for row in fauna_rows:
        key = Path(row["manifest"]).stem.replace("_manifest", "")
        source = row["source"]
        output_json[V005 / (key + "_manifest.json")] = {
            "schema": "sea.sunken_city.runtime_asset_manifest.v1",
            "asset_id": row["asset_id"], "suite": "sunken_city", "version": "v005",
            "stage": row["stage"], "source": source, "source_sha256": row["source_sha256"],
            "prefab": row["prefab"], "prefab_sha256": row["prefab_sha256"],
            "runtime_path": row["runtime_path"], "runtime_sha256": row["runtime_sha256"],
            "asset_ledger": "assets/registry/ledgers/scenes.json#" + row["asset_id"],
            "classification": row["classification"], "visual_only": True,
            "water_layer": row["water_layer"], "water_layer_role": "none",
            "building_class": None, "placement_water_layer": row["placement_water_layer"],
            "collision": False, "interactive": False, "emission": False,
            "dependencies": row["dependencies"], "verification": evidence,
            "license": row["license"], "commercial_rights_status": row["commercial_rights_status"],
            "reference_rights_verified": False,
            "note": "程序化运行装饰复用现有 fish/bird source；不创建 Blender 源，不引入玩法状态。",
        }
    output_json[V005 / "asset_manifest.json"] = copy.deepcopy(inputs.json(V005 / "asset_manifest.json"))
    output_json[V005 / "asset_manifest.json"].update(
        version="v005", source_sha256=master_hash, source_verified=True, runtime_integrated=True,
        runtime_validation="seabed-scene_and_sunken-city_and_visual-sunken-seabed_passed",
        runtime_export={"export_manifest": rel(V005_EXPORT), "runtime_path": rel(ASSEMBLY),
                        "runtime_sha256": inputs.digest(ASSEMBLY), "prefab": rel(ASSEMBLY),
                        "prefab_sha256": inputs.digest(ASSEMBLY), "verification": evidence,
                        "fidelity_verification": v004_fidelity.as_posix(), "components": 50, "instances": 388,
                        "total_assembly": {"city_instances": 388, "seabed": SEABED_ID, "fauna": sorted(FAUNA_IDS)}},
    )
    for path, value in output_json.items():
        path = path.resolve()
        raw = inputs.raw.get(path)
        if raw is None and path.exists():
            raw = inputs.read_bytes(path)
        payload = json_payload(value, raw)
        if raw != payload:
            changes[path] = payload
    source_index_raw = inputs.raw[SOURCE_INDEX.resolve()]
    if json.loads(source_index_raw.decode("utf-8-sig")) != updated_source_index:
        changes[SOURCE_INDEX.resolve()] = json_payload(updated_source_index, source_index_raw)
    ledger_raw = inputs.raw[LEDGER.resolve()]
    if json.loads(ledger_raw.decode("utf-8-sig")) != updated_book:
        changes[LEDGER.resolve()] = json_payload(updated_book, ledger_raw)
    inventory_raw = inputs.raw[INVENTORY.resolve()]
    if json.loads(inventory_raw.decode("utf-8-sig")) != updated_inventory:
        changes[INVENTORY.resolve()] = json_payload(updated_inventory, inventory_raw)

    inputs.unchanged()
    summary = {
        "passed": True, "suite": "sunken_city", "version": "v005", "applied": bool(args.apply),
        "current_records_before": 51, "retained_v002_records": 2, "components": 50, "instances": 388,
        "added_records": [SEABED_ID, *sorted(FAUNA_IDS)],
        "updated_ledger_rows": 51, "source_master_sha256": master_hash,
        "catalog_sha256_after": catalog_hash, "palette_sha256": inputs.digest(PALETTE),
        "source_protected": True, "v004_source_untouched": True, "palette_untouched": True,
        "verification": evidence, "fidelity_source": v004_fidelity.as_posix(),
        "integration_evidence": integration_evidence,
        "runtime_inventory_allowlist": sorted(rel(path) for path in allowlist),
        "changed_files": sorted(rel(path) for path in changes),
        "atomicity": "same_directory_temp_replace_with_preflight_sha256_and_best_effort_rollback",
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if not args.apply:
        print("DRY-RUN：门禁全部通过；未写入任何账本、manifest 或 runtime_inventory。添加 --apply 才会原子写入。")
        return 0
    report_path = (report_dir / "seabed_runtime_registration.json").resolve()
    if report_path.exists():
        inputs.read_bytes(report_path)
    changes[report_path] = json_payload(summary)
    atomic_apply(inputs, changes)
    print("APPLIED：已原子替换登记/manifest/index/inventory；未修改 Blend、GLB、prefab、Terrain3D 数据、色盘或其它代码。")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--verification", action="append", required=True, type=Path,
                        help="原始 runner 的绝对 report.json 路径；可重复传入")
    parser.add_argument("--baseline-verification", type=Path,
                        help="可选的绝对 minimum-loop baseline report.json；fixture 输入规范冻结前保持 blocked，不放行登记")
    parser.add_argument("--report-dir", type=Path, default=WORK,
                        help="工程外 v005 source/package/skill 报告目录；默认 sea-work/sunken_city/v005")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="门禁通过后原子写入登记与本轮 manifest")
    mode.add_argument("--dry-run", action="store_true", help="只读校验和打印写入计划；默认模式")
    args = parser.parse_args()
    try:
        return register(args)
    except (OSError, ValueError, KeyError, TypeError, IndexError, zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print("拒绝登记：" + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
