"""Fix measured Godot 4.7 hierarchy and TSCN row serialization; keep math manifest column convention."""
import hashlib,json,re
from pathlib import Path
R=Path(__file__).resolve().parents[3];G=R/'godot';M=G/'assets/models/scenery/sunken_city/runtime_manifest.json'
m=json.loads(M.read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
for c in m['components']:
    key=c['key'];p=G/f'scenes/components/scenery/sunken_city/{key}.tscn';s=p.read_text(encoding='utf-8')
    s=s.replace(f'[node name="Mesh_{key}" parent="Visual" index="0"]',f'[node name="Mesh_{key}" parent="Visual/Root_{key}" index="0"]')
    p.write_text(s,encoding='utf-8');c['prefab_sha256']=sha(p)
assembly=G/'scenes/world/sunken_city.tscn';s=assembly.read_text(encoding='utf-8')
for a in m['instances']:
    # Manifest is columns [basis.x,basis.y,basis.z,origin], native TSCN Variant text lists rows.
    t=a['godot_transform'];serial=[t[0],t[3],t[6],t[1],t[4],t[7],t[2],t[5],t[8]]+t[9:]
    pattern=r'(\[node name="'+re.escape(a['instance_id'])+r'"[^\n]*\]\n)transform = Transform3D\([^\n]*\)'
    s,n=re.subn(pattern,lambda match:match.group(1)+'transform = Transform3D('+', '.join(f'{v:.10g}' for v in serial)+')',s)
    assert n==1,a['instance_id']
assembly.write_text(s,encoding='utf-8');m['transform_serialization']='godot_transform is column vectors for test/API; TSCN Variant text row-major basis; conversion covered by every instance matrix assertions'
M.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('GODOT_MAPPING_FIXED',len(m['components']),len(m['instances']))
