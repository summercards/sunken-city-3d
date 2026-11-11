#!/usr/bin/env python3
"""核对 shell_v3 交付文件并写交付报告：只读实际文件、算 hash，不运行引擎、不写 registry。"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

OUT = Path("D:/projects/sea-work/building_workshop/shell_v3/outputs")
REPO = Path("D:/projects/sea/godot/scenes/workshop_buildings")
VERIFY = Path("D:/projects/sea-work/verification/20261111-170241-shell-v3-doors2-55f69d")
BUNDLE = ("building.recipe.json", "catalog_snapshot.json", "building.tscn", "candidate_manifest.json", "ledger.json")
IDS = ("shell_rect_1794387870_107701812", "shell_l_1794387870_107701812")


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def image_size(path: Path) -> list[int]:
    data = path.read_bytes()[:33]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return []
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    return [width, height]


def main() -> int:
    checks: list[dict] = []
    failures: list[str] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        checks.append({"name": name, "passed": bool(ok), "detail": detail})
        if not ok:
            failures.append(name)

    images = sorted(OUT.glob("*.png"))
    check("交付图像数量", len(images) >= 12, str(len(images)))
    for path in images:
        size = image_size(path)
        check("图像可解析且非空：" + path.name, bool(size) and path.stat().st_size > 10_000, str(size))

    bundles: dict[str, dict] = {}
    for building_id in IDS:
        installed = REPO / building_id / "revision_0001"
        shipped = OUT / building_id / "revision_0001"
        entry = {"installed_dir": str(installed), "shipped_dir": str(shipped), "files": {}}
        for name in BUNDLE:
            source = installed / name
            copy = shipped / name
            check("bundle五件存在：" + building_id + "/" + name, source.is_file() and copy.is_file())
            if not (source.is_file() and copy.is_file()):
                continue
            digest = sha(source)
            check("bundle hash与交付副本一致：" + building_id + "/" + name, digest == sha(copy))
            entry["files"][name] = {"sha256": digest, "bytes": source.stat().st_size}
        manifest_path = installed / "candidate_manifest.json"
        if manifest_path.is_file():
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            # 实际清单字段：candidate_ledger_status + formal_registry_written，不虚构 pending 字段。
            entry["candidate_ledger_status"] = manifest.get("candidate_ledger_status", "unknown")
            entry["formal_registry_written"] = manifest.get("formal_registry_written")
            entry["no_main"] = manifest.get("noMain")
            entry["stats"] = manifest.get("stats", {})
            check("候选未正式登记：" + building_id, manifest.get("formal_registry_written") is False and manifest.get("candidate_ledger_status") == "exported_pending_project_registration", str(entry.get("candidate_ledger_status")))
        recipe_path = installed / "building.recipe.json"
        if recipe_path.is_file():
            recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
            entry["recipe_summary"] = {
                key: recipe.get(key)
                for key in ("construction_mode", "shape", "width", "depth", "floors", "floor_height", "slab_thickness", "window_width", "window_height", "window_sill", "door_width", "door_height", "taper")
            }
            architecture = recipe.get("architecture", {})
            entry["recipe_summary"]["roof_mode"] = architecture.get("roof", {}).get("mode")
            entry["recipe_summary"]["sill_enabled"] = architecture.get("window", {}).get("sill_enabled")
            check("候选为连续实体模式：" + building_id, recipe.get("construction_mode") == "shell_v2")
            check("候选含勒脚/窗台/女儿墙默认：" + building_id, bool(entry["recipe_summary"].get("sill_enabled")) and entry["recipe_summary"].get("roof_mode") == "parapet")
        bundles[building_id] = entry

    report_path = VERIFY / "project/outputs/workshop_editor_report.json"
    editor = {}
    if report_path.is_file():
        inner = json.loads(report_path.read_text(encoding="utf-8"))
        editor = {
            "checks": len(inner.get("checks", [])),
            "failures": inner.get("failures", []),
            "passed": inner.get("passed"),
            "enginehint": inner.get("enginehint"),
            "is_playing": inner.get("is_playing"),
            "scene_unchanged": inner.get("scene_unchanged"),
        }
        check("真实editor报告通过", bool(inner.get("passed")), str(len(inner.get("checks", []))))
    else:
        check("真实editor报告存在", False, str(report_path))

    summary = {
        "kind": "workshop_shell_v3_delivery",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "output_root": str(OUT),
        "verification_run": str(VERIFY),
        "editor": editor,
        "images": [{"name": p.name, "size": image_size(p), "sha256": sha(p)} for p in images],
        "bundles": bundles,
        "notes": [
            "候选仍为 candidate_only / exported_pending_project_registration，不是正式资产登记。",
            "本脚本不运行Godot，engine_executed=false；引擎证据来自引用的runner报告。",
            "视觉结论须由主线程逐图目检；报告只记录文件与hash事实。",
        ],
        "engine_executed": False,
        "checks_count": len(checks),
        "failed_count": len(failures),
        "failures": failures,
        "passed": not failures,
    }
    target = OUT / "shell_v3_delivery_report.json"
    target.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": summary["passed"], "checks": len(checks), "failures": failures[:6], "report": str(target)}, ensure_ascii=False))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
