import hashlib,json
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v005';G=R/'godot';W=R.parent/'sea-work/sunken_city/v005/import'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
m=json.loads((G/'assets/models/scenery/sunken_city/runtime_manifest.json').read_text(encoding='utf-8'));m['version']='v005';m['instances']=[x for x in m['instances'] if not x['instance_id'].startswith('edge_ramp_')];m['edge_extension_instance_count']=0;m['source_master_sha256']=sha(D/'sunken_city_v005.blend');dump(G/'assets/models/scenery/sunken_city/runtime_manifest.json',m)
b=json.loads((W/'runtime_build.json').read_text(encoding='utf-8'));b.update(instances=388,main_sha256_after=sha(G/'scenes/main.tscn'),main_scope='fauna nodes plus continuous Terrain3D seabed; existing SunkenCity root and 388 editor instances preserved',edge_ramp_count=0,seabed_scene='godot/scenes/world/sunken_seabed.tscn',seabed_data='godot/terrain/sunken_seabed');dump(W/'runtime_build.json',b)
print('SEABED_RUNTIME_FINALIZED',len(m['instances']),sha(G/'scenes/main.tscn'))
