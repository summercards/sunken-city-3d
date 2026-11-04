"""Fix the two non-decoration source-to-Godot rotation drifts found by full audit."""
from pathlib import Path
import importlib.util
import json
import re
import shutil
import hashlib

ROOT = Path(__file__).resolve().parents[3]
SCENE = ROOT / "godot/scenes/facilities/rooftop_ranch.tscn"
SOURCE = ROOT / "art_source/scenes/ocean_rooftop_farm/v004/component_instances.json"
OUT = Path("D:/projects/sea-work/ocean_rooftop_farm/v006_attachment_fix")
TARGETS = ["ORF2_实例_coop", "ORF3_下挂断裂消防梯"]

spec = importlib.util.spec_from_file_location(
    "decoration_fix", ROOT / "tools/blender/ocean_rooftop_farm/fix_runtime_decoration_transforms.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    before = SCENE.read_bytes()
    backup = OUT / "rooftop_ranch.before_rotation_fix.tscn"
    if not backup.exists():
        backup.write_bytes(before)
    source = {row["name"]: row for row in json.loads(SOURCE.read_text(encoding="utf-8"))["instances"]}
    text = before.decode("utf-8")
    changed = []
    for name in TARGETS:
        row = source[name]
        expected = mod.converted(row)
        nums = ", ".join(format(0.0 if v == 0 else v, ".15g") for v in expected)
        marker = '[node name="' + name + '"'
        start = text.find(marker)
        if start < 0:
            raise RuntimeError(f"missing target node: {name}")
        end = text.find('\n[node ', start + 1)
        if end < 0:
            end = len(text)
        block = text[start:end]
        tm = re.search(r'transform = Transform3D\([^\n]*\)', block)
        if tm is None:
            raise RuntimeError(f"missing transform: {name}")
        old = block
        replacement_block = block[:tm.start()] + 'transform = Transform3D(' + nums + ')' + block[tm.end():]
        text = text[:start] + replacement_block + text[end:]
        replacement = replacement_block
        changed.append({"name": name, "before": old, "after": replacement, "expected": expected})
    after = text.encode("utf-8")
    SCENE.write_bytes(after)
    audit = {
        "tool": "ocean_rooftop_farm_remaining_rotation_drift_v1",
        "scene": str(SCENE),
        "backup": str(backup),
        "targets": changed,
        "sha256_before": sha(before),
        "sha256_after": sha(after),
        "bytes_before": len(before),
        "bytes_after": len(after),
        "changed_target_count": len(changed),
        "scope": "only two Transform3D lines; no GLB, source JSON, waterline, stairs, or navigation changes",
    }
    (OUT / "rotation_drift_audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "targets": TARGETS, "sha256_before": sha(before), "sha256_after": sha(after)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
