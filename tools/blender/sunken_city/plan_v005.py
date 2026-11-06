"""Freeze v005: visual fauna remains runtime decoration; road extension uses existing terrain/ramp definitions."""
import copy,hashlib,json,zipfile
from pathlib import Path
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/sunken_city/v004';D=OLD.parent/'v005';W=R.parent/'sea-work/sunken_city/v005'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
cat=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'];p=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'));assert len(cat)==50
source=[OLD/'sunken_city_v004.blend',OLD/'component_plan.json',OLD/'component_catalog.json',OLD/'component_instances.json',R/'godot/scenes/main.tscn',R/'godot/scenes/world/sunken_city.tscn',R/'godot/assets/models/scenery/sunken_city/runtime_manifest.json',R/'godot/scenes/decorations/animals/fish_school.tscn',R/'godot/src/ambient/decorative_fish_school.gd',R/'godot/src/ambient/birds.gd',R/'godot/src/ambient/bird.gd']
archive=OLD/'export/v004/runtime_preserved_before_v005_fauna.zip';assert not archive.exists()
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=3) as z:
 for x in source:z.write(x,x.relative_to(R).as_posix())
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
p=copy.deepcopy(p);p.update(version='v005',status='frozen_before_geometry',revision='v005_fauna_and_road_edge_slope',previous_source='art_source/scenes/sunken_city/v004/sunken_city_v004.blend',previous_source_sha256=sha(OLD/'sunken_city_v004.blend'))
p['fauna_contract']={'visual_only':True,'fish_school_prefab':'res://scenes/decorations/animals/fish_school.tscn','variants':[{'key':'near','count':6,'spread_radius_m':2.2,'orbit_radius_m':[1.8,.9]},{'key':'mid','count':10,'spread_radius_m':3.2,'orbit_radius_m':[2.6,1.3]},{'key':'wide','count':14,'spread_radius_m':4.8,'orbit_radius_m':[3.8,1.9]}],'gull_buildings':['solar_cabin','rooftop_ranch'],'excluded_submerged_buildings':['neon_garden_quarter','floating_shop'],'no_gameplay_state':True}
p['road_edge_contract']={'base_boundary_xy_m':[-120,120,-120,120],'edge_extension_m':12.0,'outer_slope_run_m':24.0,'relief_m':4.8,'slope_angle_deg':11.309932474020213,'reuse_components':['street_intact','street_split','terrain_ramp','junction'],'highest_world_y_limit_m':.87,'main_manual_root_y_m':43.487442,'no_change_to_existing_sunken_city_instances':True}
p['previous_runtime_archive']=archive.relative_to(R).as_posix();p['scope_lock']={'previous_version':'v004','source_sha256':sha(OLD/'sunken_city_v004.blend'),'protected_files':{x.relative_to(R).as_posix():sha(x) for x in source},'geometry_changes':'new edge-slope support definitions only; existing 50 component geometry and 388 instances locked','runtime_changes':'fauna scenes + approved road extension mount only; main manual SunkenCity Y is authoritative and unchanged'}
dump(D/'component_plan.json',p);dump(W/'scope_lock.json',{'passed':True,'archive':archive.relative_to(R).as_posix(),'archive_sha256':sha(archive),'protected_sources':p['scope_lock']['protected_files'],'fauna_contract':p['fauna_contract'],'road_edge_contract':p['road_edge_contract']})
(W/'import/main_before_v005.tscn').write_bytes((R/'godot/scenes/main.tscn').read_bytes());(W/'import/assembly_before_v005.tscn').write_bytes((R/'godot/scenes/world/sunken_city.tscn').read_bytes())
print('V005_FROZEN',sha(archive),p['fauna_contract']['variants'],p['road_edge_contract'])
