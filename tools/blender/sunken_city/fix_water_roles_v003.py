"""Complete explicit metadata duties required by the project's water-layer regression."""
import json,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[3];G=R/'godot';mp=G/'assets/models/scenery/sunken_city/runtime_manifest.json';m=json.loads(mp.read_text(encoding='utf-8'))
for row in m['components']:
    p=G/f'scenes/components/scenery/sunken_city/{row["key"]}.tscn';s=p.read_text(encoding='utf-8');anchor='metadata/water_layer = "submerged"\n'
    if 'metadata/water_layer_role' not in s:s=s.replace(anchor,anchor+'metadata/water_layer_role = "part"\n')
    p.write_text(s,encoding='utf-8');row['prefab_sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
p=G/'scenes/world/sunken_city.tscn';s=p.read_text(encoding='utf-8');anchor='metadata/water_layer = "submerged"\n'
if 'metadata/water_layer_role' not in s:s=s.replace(anchor,anchor+'metadata/water_layer_role = "entity"\n')
p.write_text(s,encoding='utf-8');mp.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('WATER_ROLES_COMPLETE',len(m['components']),'+ assembly')
