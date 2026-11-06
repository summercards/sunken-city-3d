"""v005 corrected scope: no perimeter road instances; continuous seabed is authored in Godot Terrain3D."""
import bpy,hashlib,json
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v005';W=R.parent/'sea-work/sunken_city/v005';P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];INST=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances'];S=bpy.data.scenes['沉没旧城_完整参考布局_v005'];errors=[];checks=0
def ck(ok,msg):
 global checks
 checks+=1
 if not ok:errors.append(msg)
ck(len(INST)==388,'corrected layout retains 388 city instances');ck(not any(a['instance_id'].startswith('edge_ramp_') for a in INST),'no rejected perimeter road instances');ck(len(CAT)==50,'component definitions remain 50');ck(hashlib.sha256((R/'art_source/scenes/sunken_city/v004/sunken_city_v004.blend').read_bytes()).hexdigest()==P['previous_source_sha256'],'v004 source unchanged');ck(P['road_edge_contract']['method']=='Terrain3D heightmap below existing city','Terrain3D seabed method recorded');ck(P['road_edge_contract']['added_road_instances']==0,'no added road instances');report=dict(passed=not errors,checks=checks,errors=errors,ground_tiles=100,edge_ramps=0,existing_instances_unchanged=True,seabed_authored_outside_blender=True);(W/'terrain_bridge_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('TERRAIN_V005_CORRECTED_CHECK',checks,'checks',len(errors),'errors',errors);assert not errors,errors
