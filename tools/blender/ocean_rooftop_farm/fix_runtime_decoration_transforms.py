"""仅修复牧场150个装饰实例的变换；标准库运行，不调用Blender/Godot。"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import shutil


ROOT = Path(__file__).resolve().parents[3]
SCENE = Path("godot/scenes/facilities/rooftop_ranch.tscn")
SOURCE = Path("art_source/scenes/ocean_rooftop_farm/v004/component_instances.json")
GLB_DIR = Path("godot/assets/models/facilities/rooftop_ranch")
OUTPUT = Path("D:/projects/sea-work/ocean_rooftop_farm/v006_attachment_fix")
COUNTS = {
    "SEA-SCENE-ORF2-VINE": 24,
    "SEA-SCENE-ORF2-MOSS_CLUSTER": 11,
    "SEA-SCENE-ORF2-GRASS": 90,
    "SEA-SCENE-ORF2-WEATHER": 25,
}
C = ((1, 0, 0), (0, 0, 1), (0, -1, 0))
CT = tuple(zip(*C))
SECTION = re.compile(rb"^\[[^\r\n]*\](?:\r?\n|$)", re.M)
TRANSFORM = re.compile(rb"^(transform = Transform3D\()([^\r\n]*)(\))(?=\r?$)", re.M)
TOLERANCE = 1e-10
MARKER = "ocean_rooftop_farm_decoration_transform_fix_v1"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def file_sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def glb_hashes(root):
    directory = root / GLB_DIR
    require(directory.is_dir(), "牧场GLB目录不存在")
    paths = sorted(directory.rglob("*.glb"))
    require(paths, "未找到牧场GLB")
    return {p.relative_to(root).as_posix(): file_sha(p) for p in paths}


def protected_inputs(root):
    paths = [root / SOURCE]
    source_dir = root / "art_source/scenes/ocean_rooftop_farm"
    paths.extend(sorted(source_dir.rglob("*.blend")))
    return {p.relative_to(root).as_posix(): file_sha(p) for p in paths}


def load_targets(root):
    instances = json.loads((root / SOURCE).read_bytes())["instances"]
    rows = [row for row in instances if row["component_id"] in COUNTS]
    require(dict(Counter(row["component_id"] for row in rows)) == COUNTS,
            "源装饰分类计数不符合24/11/90/25")
    require(len({row["name"] for row in rows}) == 150, "源实例名重复")
    for row in rows:
        for key in ("position_m", "rotation_euler_xyz", "scale"):
            require(len(row[key]) == 3 and all(math.isfinite(v) for v in row[key]),
                    f"源变换无效：{row['name']} {key}")
    return {row["name"]: row for row in rows}


def multiply(left, right):
    return [[sum(left[i][k] * right[k][j] for k in range(3))
             for j in range(3)] for i in range(3)]


def converted(row):
    x, y, z = row["rotation_euler_xyz"]
    cx, cy, cz = math.cos(x), math.cos(y), math.cos(z)
    sx, sy, sz = math.sin(x), math.sin(y), math.sin(z)
    rx = ((1, 0, 0), (0, cx, -sx), (0, sx, cx))
    ry = ((cy, 0, sy), (0, 1, 0), (-sy, 0, cy))
    rz = ((cz, -sz, 0), (sz, cz, 0), (0, 0, 1))
    scale = [[row["scale"][i] if i == j else 0 for j in range(3)] for i in range(3)]
    basis = multiply(multiply(C, multiply(multiply(multiply(rz, ry), rx), scale)), CT)
    px, py, pz = row["position_m"]
    return [basis[i][j] for j in range(3) for i in range(3)] + [px, pz, -py]


def attribute(block, key):
    matches = re.findall(rb'^' + re.escape(key.encode()) + rb' = "([^"\r\n]+)"\r?$', block, re.M)
    require(len(matches) == 1, f"属性不唯一：{key}")
    return matches[0].decode("utf-8")


def sections(data):
    headers = list(SECTION.finditer(data))
    require(headers and headers[0].start() == 0, "场景段落头不符合预期")
    return [(m.start(), headers[i + 1].start() if i + 1 < len(headers) else len(data))
            for i, m in enumerate(headers)]


def plan(data, targets):
    patches, found, counts = [], set(), Counter()
    for start, end in sections(data):
        block = data[start:end]
        if not block.startswith(b"[node "):
            continue
        asset = re.search(rb'^metadata/asset_id = "([^"\r\n]+)"\r?$', block, re.M)
        if not asset or asset[1].decode("utf-8") not in COUNTS:
            continue
        name = attribute(block, "metadata/source_instance")
        component = asset[1].decode("utf-8")
        require(name in targets and targets[name]["component_id"] == component,
                f"目标源实例不匹配：{name}")
        require(name not in found, f"场景目标重复：{name}")
        header = block.splitlines()[0]
        require(re.search(rb' parent="Models" ', header) is not None,
                f"目标不属于Models：{name}")
        node_name = re.search(rb'^\[node name="([^"]+)"', header)
        require(node_name and node_name[1].decode("utf-8") == name, f"节点名不匹配：{name}")
        transforms = list(TRANSFORM.finditer(block))
        require(len(transforms) == 1, f"目标Transform不唯一：{name}")
        require(not re.search(rb'^(position|rotation|rotation_degrees|quaternion|scale) = ', block, re.M),
                f"目标存在额外变换属性：{name}")
        transform = transforms[0]
        expected = converted(targets[name])
        numbers = ", ".join(format(0.0 if v == 0 else v, ".15g") for v in expected).encode("ascii")
        replacement = transform[1] + numbers + transform[3]
        patches.append({"name": name, "component_id": component,
                        "start": start + transform.start(), "end": start + transform.end(),
                        "replacement": replacement})
        found.add(name)
        counts[component] += 1
    require(found == set(targets) and dict(counts) == COUNTS, "场景目标数或实例集合不匹配")
    result, cursor = [], 0
    for patch in patches:
        result.extend((data[cursor:patch["start"]], patch["replacement"]))
        cursor = patch["end"]
    result.append(data[cursor:])
    return b"".join(result), patches


def independent_parse(data):
    # 独立逐行解析，不复用修复器的段落/Transform正则。
    blocks, current = [], []
    for line in data.splitlines(keepends=True):
        if line.startswith(b"[") and current:
            blocks.append(b"".join(current))
            current = []
        current.append(line)
    if current:
        blocks.append(b"".join(current))
    parsed = []
    for block in blocks:
        lines = block.splitlines(keepends=True)
        fields = {}
        for line in lines[1:]:
            key, sep, value = line.rstrip(b"\r\n").partition(b" = ")
            if sep:
                require(key not in fields, f"重复属性：{key!r}")
                fields[key] = value
        parsed.append((block, lines, fields))
    return parsed


def independent_expected(row):
    # 对Godot三个单位轴先逆映射，再逐轴缩放/Rx/Ry/Rz，最后映射回来。
    ax, ay, az = row["rotation_euler_xyz"]
    result = []
    for gx, gy, gz in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
        x, y, z = gx * row["scale"][0], -gz * row["scale"][1], gy * row["scale"][2]
        y, z = math.cos(ax) * y - math.sin(ax) * z, math.sin(ax) * y + math.cos(ax) * z
        x, z = math.cos(ay) * x + math.sin(ay) * z, -math.sin(ay) * x + math.cos(ay) * z
        x, y = math.cos(az) * x - math.sin(az) * y, math.sin(az) * x + math.cos(az) * y
        result.extend((x, z, -y))
    px, py, pz = row["position_m"]
    return result + [px, pz, -py]


def state(fields):
    text = fields[b"transform"].decode("ascii")
    require(text.startswith("Transform3D(") and text.endswith(")"), "Transform3D语法不符")
    values = [float(v.strip()) for v in text[len("Transform3D("):-1].split(",")]
    require(len(values) == 12 and all(math.isfinite(v) for v in values), "Transform3D数值无效")
    return {"position": values[9:], "basis_columns": [values[i:i + 3] for i in (0, 3, 6)],
            "transform3d_values": values, "transform_line": "transform = " + text}


def verify(before, after, root):
    targets = load_targets(root)
    old_blocks, new_blocks = independent_parse(before), independent_parse(after)
    require(len(old_blocks) == len(new_blocks), "段落总数变化")
    records, protected, counts, seen = [], [], Counter(), set()
    before_masked, after_masked = [], []
    changed_lines = 0
    for index, ((old, old_lines, old_fields), (new, new_lines, fields)) in enumerate(zip(old_blocks, new_blocks)):
        require(old_lines[0] == new_lines[0], f"段落头变化：{index}")
        asset = fields.get(b"metadata/asset_id", b"").strip(b'"').decode("utf-8")
        is_target = new.startswith(b"[node ") and asset in COUNTS
        if not is_target:
            entry = {"index": index, "header": new_lines[0].decode("utf-8").strip(),
                     "sha256_before": sha(old), "sha256_after": sha(new), "unchanged": old == new}
            protected.append(entry)
            require(old == new, f"非目标块发生变化：{entry['header']}")
            before_masked.append(old)
            after_masked.append(new)
            continue
        name = fields[b"metadata/source_instance"].strip(b'"').decode("utf-8")
        require(name in targets and name not in seen and targets[name]["component_id"] == asset,
                f"独立解析实例不匹配：{name}")
        seen.add(name)
        counts[asset] += 1
        old_rest = b"".join(line for line in old_lines if not line.startswith(b"transform = "))
        new_rest = b"".join(line for line in new_lines if not line.startswith(b"transform = "))
        require(old_rest == new_rest, f"目标块非Transform字节变化：{name}")
        require(len(old_lines) == len(new_lines), f"目标块行数变化：{name}")
        for left, right in zip(old_lines, new_lines):
            if left != right:
                require(left.startswith(b"transform = ") and right.startswith(b"transform = "),
                        f"非Transform行变化：{name}")
                require(left[len(left.rstrip(b'\r\n')):] == right[len(right.rstrip(b'\r\n')):],
                        f"Transform换行变化：{name}")
                changed_lines += 1
        before_masked.append(old_rest)
        after_masked.append(new_rest)
        previous, current = state(old_fields), state(fields)
        expected = independent_expected(targets[name])
        errors = [abs(a - b) for a, b in zip(current["transform3d_values"], expected)]
        require(max(errors) <= TOLERANCE, f"独立数学转换不匹配：{name} {max(errors)}")
        delta = [a - b for a, b in zip(current["transform3d_values"], previous["transform3d_values"])]
        records.append({"name": name, "component_id": asset, "source": targets[name],
                        "before": previous, "after": current,
                        "expected_independent": expected,
                        "delta": {"position": delta[9:],
                                  "basis_columns": [delta[i:i + 3] for i in (0, 3, 6)],
                                  "transform3d_values": delta,
                                  "position_distance_m": math.sqrt(sum(v * v for v in delta[9:]))},
                        "max_abs_error": max(errors),
                        "target_non_transform_sha256_before": sha(old_rest),
                        "target_non_transform_sha256_after": sha(new_rest)})
    require(seen == set(targets) and dict(counts) == COUNTS, "独立解析目标计数失败")
    require(b"".join(before_masked) == b"".join(after_masked), "非目标字节整体变化")
    return {"target_counts": dict(counts), "target_count": len(records),
            "changed_transform_lines": changed_lines,
            "max_abs_error": max(row["max_abs_error"] for row in records),
            "protected_non_target_block_count": len(protected),
            "protected_non_target_blocks": protected,
            "all_non_transform_bytes_sha256_before": sha(b"".join(before_masked)),
            "all_non_transform_bytes_sha256_after": sha(b"".join(after_masked)),
            "instances": records}


def checks_for(details, glb_before, glb_after, inputs_before, inputs_after, idempotent):
    return {
        "exact_150_targets_and_per_category_counts": details["target_counts"] == COUNTS and details["target_count"] == 150,
        "independent_source_math_all_150_pass": details["max_abs_error"] <= TOLERANCE,
        "all_non_target_blocks_sha256_unchanged": all(row["unchanged"] for row in details["protected_non_target_blocks"]),
        "target_blocks_except_transform_unchanged": all(row["target_non_transform_sha256_before"] == row["target_non_transform_sha256_after"] for row in details["instances"]),
        "all_non_transform_bytes_sha256_unchanged": details["all_non_transform_bytes_sha256_before"] == details["all_non_transform_bytes_sha256_after"],
        "only_target_transform_lines_changed": details["changed_transform_lines"] <= 150,
        "glb_hashes_and_file_set_unchanged": glb_before == glb_after,
        "source_json_and_all_source_blends_unchanged": inputs_before == inputs_after,
        "rerun_produces_identical_scene_bytes": idempotent,
    }


def write_audit(path, report):
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apply", action="store_true", help="备份后执行定点修复，已修复时保持场景字节不变")
    mode.add_argument("--verify-only", action="store_true", help="相对首次备份独立复核，并将结果附加至原审计")
    args = parser.parse_args()
    root, output = args.project_root.resolve(), args.output_dir.resolve()
    require(not output.is_relative_to(root), "备份与审计目录必须位于工程外")
    require(output.parent.is_dir(), "输出父目录不存在")
    scene, audit_path = root / SCENE, output / "transform_audit.json"
    prior = json.loads(audit_path.read_bytes()) if audit_path.exists() else None
    if prior:
        require(prior.get("tool") == MARKER and prior.get("project_root") == root.as_posix(),
                "已有审计不属于当前修复工具/工程，拒绝覆盖")
    now = datetime.now(timezone.utc).isoformat()
    if args.verify_only:
        require(prior is not None, "独立验证需要首次修复审计")
        backup = Path(prior["backup_path"])
        require(file_sha(backup) == prior["scene_sha256_before"], "首次备份哈希变化")
        current = scene.read_bytes()
        details = verify(backup.read_bytes(), current, root)
        glb_after, inputs_after = glb_hashes(root), protected_inputs(root)
        check = checks_for(details, prior["glb_sha256_before"], glb_after,
                           prior["protected_input_sha256_before"], inputs_after,
                           plan(current, load_targets(root))[0] == current)
        check["scene_matches_first_repair_sha256"] = sha(current) == prior["scene_sha256_after"]
        check["original_backup_sha256_unchanged"] = True
        result = {"time_utc": now, "checks": check, "passed": all(check.values()),
                  "target_count": details["target_count"], "max_abs_error": details["max_abs_error"],
                  "scene_sha256": sha(current)}
        prior.setdefault("independent_verifications", []).append(result)
        write_audit(audit_path, prior)
        print(json.dumps(result, ensure_ascii=False))
        require(result["passed"], "独立验证失败，参见transform_audit.json")
        return

    before = scene.read_bytes()
    glb_before, inputs_before = glb_hashes(root), protected_inputs(root)
    proposed, patches = plan(before, load_targets(root))
    verify(before, proposed, root)
    if prior:
        require(sha(before) == prior["scene_sha256_after"], "场景自首次修复后发生额外变化，拒绝覆盖")
        require(glb_before == prior["glb_sha256_before"], "GLB自首次修复后变化，拒绝继续")
        require(inputs_before == prior["protected_input_sha256_before"], "源数据自首次修复后变化，拒绝继续")
    output.mkdir(exist_ok=True)
    backup = output / ("rooftop_ranch.before.tscn" if not prior else
                       "rooftop_ranch.rerun_" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ") + ".tscn")
    with backup.open("xb") as stream:
        stream.write(before)
    shutil.copystat(scene, backup)
    require(backup.read_bytes() == before, "场景备份未通过字节核对")
    require(scene.read_bytes() == before, "写入前场景被其他进程修改，停止修复")
    if proposed != before:
        scene.write_bytes(proposed)
    after = scene.read_bytes()
    require(after == proposed, "场景写回字节不匹配")
    # 写回后重新读取源与场景，执行不同解析器及不同数学算法。
    details = verify(backup.read_bytes(), after, root)
    glb_after, inputs_after = glb_hashes(root), protected_inputs(root)
    check = checks_for(details, glb_before, glb_after, inputs_before, inputs_after,
                       plan(after, load_targets(root))[0] == after)
    check["backup_matches_pre_repair_scene"] = file_sha(backup) == sha(before)
    check["replacement_count_exactly_150"] = len(patches) == 150
    report = {
        "tool": MARKER, "time_utc": now, "project_root": root.as_posix(),
        "scene_path": scene.as_posix(), "source_path": (root / SOURCE).as_posix(),
        "backup_path": backup.as_posix(), "audit_path": audit_path.as_posix(),
        "math": {"position": "(x,z,-y)", "basis": "C*(Rz*Ry*Rx*diag(sx,sy,sz))*C^-1",
                 "C": C, "serialization": "Godot Transform3D: basis columns X,Y,Z then origin",
                 "independent_verifier": "逐向量C^-1、缩放、Rx、Ry、Rz、C；独立逐行场景解析",
                 "absolute_tolerance": TOLERANCE, "numeric_format": ".15g"},
        "scene_sha256_before": sha(before), "scene_sha256_after": sha(after),
        "scene_bytes_before": len(before), "scene_bytes_after": len(after),
        "glb_count": len(glb_before), "glb_sha256_before": glb_before, "glb_sha256_after": glb_after,
        "protected_input_sha256_before": inputs_before, "protected_input_sha256_after": inputs_after,
        **details, "checks": check, "passed": all(check.values()),
        "not_executed": ["Blender编辑/导出", "Godot重导入/运行/渲染", "测试/runner/文档修改"],
    }
    evidence_path = output.parent / "v006_delivery/source_audit.json"
    if evidence_path.is_file():
        evidence = json.loads(evidence_path.read_bytes())
        report["source_layout_evidence"] = {
            "path": evidence_path.as_posix(), "sha256": file_sha(evidence_path),
            "passed": evidence.get("passed"), "source": evidence.get("source"),
            "source_parent": evidence.get("source_parent"),
            "visibility_reference": evidence.get("visibility_reference"),
            "checks": evidence.get("checks"),
            "scope_note": "历史源审计仅作布局链佐证，不替代本次150实例数学核验。",
        }
    if prior:
        prior.setdefault("reruns", []).append({key: value for key, value in report.items()
                                               if key not in ("instances", "protected_non_target_blocks", "source_layout_evidence")})
        write_audit(audit_path, prior)
    else:
        write_audit(audit_path, report)
    print(json.dumps({"passed": report["passed"], "target_counts": details["target_counts"],
                      "changed_transform_lines": details["changed_transform_lines"],
                      "max_abs_error": details["max_abs_error"], "glb_count": len(glb_before),
                      "protected_non_target_block_count": details["protected_non_target_block_count"],
                      "backup": backup.as_posix(), "audit": audit_path.as_posix()}, ensure_ascii=False))
    require(report["passed"], "修复验证失败，参见transform_audit.json")


if __name__ == "__main__":
    main()
