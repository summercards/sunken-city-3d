import os
from pathlib import Path
import sys

import bpy


ROOT = Path(__file__).resolve().parents[3]
scene = bpy.context.scene
VERSION = Path(bpy.data.filepath).stem.rsplit("_",1)[-1]
OUTPUT = Path(os.environ.get("SEA_WORK_ROOT", ROOT.parent / "sea-work")) / "rooftop_restoration" / VERSION
camera = scene.camera

if "preview" in sys.argv:
    frames = OUTPUT / "frames"
    frames.mkdir(exist_ok=True,parents=True)
    scene.cycles.samples = 4
    scene.render.resolution_percentage = 44
    for index, frame in enumerate([*range(1,300,3),300]):
        scene.frame_set(frame)
        scene.render.filepath = str(frames/f"preview_{index:04d}.png")
        bpy.ops.render.render(write_still=True)
else:
    scene.cycles.samples = 24
    for name, frame, angle in (
        ("01_before",1,None), ("02_repaired",191,None),
        ("03_drop",222,None), ("04_after",300,None),
        ("05_house",300,"House and repaired paving"), ("06_facilities",300,"Glasshouse and tank"),
        ("07_overhead",1,"Terrace overhead"), ("08_whole_building",300,"Whole water-side building"),
        ("09_house_ruined",1,"House and repaired paving"),
    ):
        scene.camera = bpy.data.objects.get(angle) if angle else camera
        if name=="07_overhead":
            scene.render.resolution_y = 875
        elif name=="08_whole_building":
            scene.render.resolution_y = 920
        elif name in ("05_house","06_facilities","09_house_ruined"):
            scene.render.resolution_y = 960
        elif name=="03_drop":
            scene.render.resolution_y = 790
        else:
            scene.render.resolution_y = 535
        scene.frame_set(frame)
        scene.render.filepath = str(OUTPUT/(name+".png"))
        bpy.ops.render.render(write_still=True)
