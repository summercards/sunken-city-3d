"""Save and reopen v002 component packages from the live Blender session."""
import bpy,json,hashlib,os
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v002';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'bld_20261109_a/v002';S=D/'bld_20261109_a_v002.blend';W.mkdir(parents=True,exist_ok=True)
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'));plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));pal=R/plan['palette'];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();source_sha=sha(S);pal_sha=sha(pal)
# Active GUI source is already v002. Build package files in a separate headless copy after this callback.
(D/'v002_source_snapshot.json').write_text(json.dumps({'source_sha256':source_sha,'palette_sha256':pal_sha,'components':len(cat['components']),'instances':len(json.loads((D/'component_instances.json').read_text())['instances'])},indent=2)+'\n',encoding='utf-8')
print('V002_PACKAGE_SNAPSHOT',json.dumps({'source_sha256':source_sha,'palette_sha256':pal_sha,'components':len(cat['components'])}),flush=True)
