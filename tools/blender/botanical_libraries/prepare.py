"""Freeze a source-preserving, two-file botanical archive plan before importing geometry."""
import collections, hashlib, json, os
from pathlib import Path
R = Path(__file__).resolve().parents[3]
W = Path(os.environ.get('SEA_WORK_ROOT', str(R.parent/'sea-work')))/'botanical_libraries/v001'
OUT = R/'art_source/vegetation/libraries/v001'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p): return json.loads((R/p).read_text(encoding='utf-8'))
idx = read('assets/registry/ledger_index.json')
rows = {d:read(v['ledger'])[v.get('asset_key','assets')] for d,v in idx['domains'].items()}
allrows = {a['asset_id']:a for aa in rows.values() for a in aa}
selected = {}
def add(a, group, source=None, note=''):
 p=source or a['source']; assert (R/p).is_file(),p
 selected[a['asset_id']]={'asset_id':a['asset_id'],'name':a.get('name',a['asset_id']), 'source':p,'source_sha256':sha(R/p),'ledger_source':a['source'],'ledger_source_sha256':a.get('source_sha256'), 'original_stage':a.get('stage','pending'),'domain':a.get('domain','scenes'),'group':group,'note':note,'mode':'blend_component'}
for a in rows['scenes']:
 cls=a.get('classification',{}); p=a.get('source',''); aid=a['asset_id']
 if cls.get('subcategory')=='plants' and p.endswith('.blend') and a.get('stage')!='historical_source_retained':
  group='01_阳光房与基座' if aid.startswith(('SEA-SCENE-SBR-','SEA-SCENE-BLB-')) else '06_已制作待接入'
  add(a,group)
 if p.startswith('godot/assets/plants/'):
  add(a,'05_原版升级植物'); selected[aid]['mode']='native_binary'
for aid in ['SEA-VEG-GRASS-SOFT','SEA-VEG-MOUND-SOFT','SEA-VEG-MOSS-SOFT']:
 add(allrows[aid],'02_共享草地与苔藓')
for aid in ['SEA-FISHERY-TURF','SEA-FISHERY-REEDS','SEA-SCENE-GKS-FOLIAGE']:
 add(allrows[aid],'03_设施植物')
for key in ['grass','tuft','vine','plant','moss_cluster','turf_core']:
 aid='SEA-SCENE-ORF2-'+key.upper()
 p=f'art_source/scenes/ocean_rooftop_farm/v004/component_packages/{key}/{key}.blend'
 add(allrows[aid],'03_设施植物',p,'运行包装使用v004，原主账本仍登记v003；本库明确取v004，不改原主源或验收阶段。')
for i in range(37,45): add(allrows[f'SEA-SCENE-NGQ-{i:03}'],'03_设施植物')
for a in rows['scenes']:
 p=a.get('source','')
 if '/sunken_city/' in p and Path(p).stem in ['moss_patch','kelp_clump']:
  add(a,'04_水生与水下植物')
for aid in ['SEA-SCENE-FSH-FOLIAGE','SEA-SCENE-FSH-FLOWERS']: add(allrows[aid],'06_已制作待接入')
a=allrows['SEA-DECO-WATER-LILY'];add(a,'04_水生与水下植物');selected[a['asset_id']]['mode']='native_lily'
planting=[]
for a in rows['crops']:
 addrow={'asset_id':a['asset_id'],'name':a['name'],'source':a['source'],'source_sha256':sha(R/a['source']), 'ledger_source':a['source'],'ledger_source_sha256':a.get('source_sha256'),'domain':'crops','original_stage':a.get('stage'),'group':'01_六品种四阶段','mode':'blend_crop' if a['source'].endswith('.blend') else 'native_flower'}
 planting.append(addrow)
for aid in ['SEA-FARM-SOIL-CELL','SEA-FARM-CULTIVATION-DECK']:
 a=allrows[aid]; planting.append({'asset_id':aid,'name':a['name'],'source':a['source'],'source_sha256':sha(R/a['source']),'ledger_source':a['source'],'ledger_source_sha256':a.get('source_sha256'),'domain':'scenes','original_stage':a.get('stage'),'group':'02_种植设施','mode':'native_facility'})
plan={'schema_version':1,'kind':'derived_collection_libraries_not_primary_source_migration','version':'v001','created':'2026-11-10', 'coordinate_system':'Blender Z-up metres; Godot(x,y,z)->Blender(x,-z,y)', 'libraries':[{'library_id':'SEA-LIB-VEGETATION-V001','name':'植被组件库','path':'art_source/vegetation/libraries/v001/vegetation_library.blend','components':list(selected.values())},{'library_id':'SEA-LIB-PLANTING-V001','name':'种植系统组件库','path':'art_source/crops/libraries/v001/planting_library.blend','components':planting}], 'native_extraction':'D:/projects/sea-work/botanical_libraries/v001/native_meshes.json', 'policy':{'original_sources':'read_only_hash_protected','runtime':'not_modified','primary_asset_ids':'reused_no_duplicate_main_records','materials':'preserve_existing_palette_botanical_uv_vertex_color_and_wind_channels','scene_positions':'gallery_instances_only_not_runtime_positions','scope_limit':'each semantic subgroup <=50; historical/rejected/trial-only assets excluded','native_sources':'Godot-derived editable snapshot; original procedural source remains authoritative','archive_normalization':'bottom-center offset recorded; transforms baked; no topology/UV/color editing'},'exclusions':['vegetation/v001 rejected candidates','historical_source_retained SBR vine/palm','retired sea barrier','ProtonScatter third-party trial','corals/animals/rocks/building shells','old crop and ORF source superseded by current version'], 'preserved_drift':[]}
for lib in plan['libraries']:
 counts=collections.Counter(x['group'] for x in lib['components']);assert max(counts.values())<=50,counts
 for e in lib['components']:
  if e['ledger_source']==e['source'] and e['ledger_source_sha256'] and e['ledger_source_sha256']!=e['source_sha256']:
   plan['preserved_drift'].append({'asset_id':e['asset_id'],'source':e['source'],'registered':e['ledger_source_sha256'],'actual':e['source_sha256']})
 plan.setdefault('counts',{})[lib['library_id']]={'asset_records':len(lib['components']),'groups':dict(counts)}
# Protect only authored inputs and original runtime visuals; never accept their drift by updating old hashes.
protect={}
for lib in plan['libraries']:
 for e in lib['components']:
  protect[e['source']]=e['source_sha256']
  a=allrows[e['asset_id']]
  for k in ['runtime_path','glb','prefab']:
   p=a.get(k)
   if p and (R/p).is_file():protect[p]=sha(R/p)
  for p in a.get('stage_models',[]):
   if (R/p).is_file(): protect[p]=sha(R/p)
for p in (R/'art_source/shared/palettes').glob('*'):
 if p.is_file():protect[p.relative_to(R).as_posix()]=sha(p)
plan['protected_inputs']=protect
for folder in [OUT,R/'art_source/crops/libraries/v001',W]:
 assert folder.is_dir(),folder
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(R/'art_source/crops/libraries/v001/component_plan.json').write_text(json.dumps({'schema_version':1,'shared_plan':'art_source/vegetation/libraries/v001/component_plan.json','library':plan['libraries'][1]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(W/'protected_inputs.json').write_text(json.dumps(protect,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'counts':plan['counts'],'source_hash_drift':plan['preserved_drift'],'protected_inputs':len(protect)},ensure_ascii=False,indent=2))
