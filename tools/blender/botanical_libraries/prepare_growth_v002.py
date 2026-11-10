"""Freeze named three-form plant production plan. No seasonal or runtime changes."""
import hashlib,json,os,collections
from pathlib import Path
R=Path(__file__).resolve().parents[3];OUT=R/'art_source/vegetation/libraries/v002';W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_growth/v002/vegetation'
def load(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
names=load(R/'tools/blender/botanical_libraries/plant_names_v002.json')['plants'];old=load(R/'art_source/vegetation/libraries/v001/library_manifest.json');source={x['asset_id']:x for x in old['members']}
plants=[]
for n in names:
 aid=n['asset_id']
 if aid not in source:continue
 e=source[aid];f=n['family'];dims=[e['bounds'][1][i]-e['bounds'][0][i] for i in range(3)];seed=int(hashlib.sha256(aid.encode()).hexdigest()[:8],16);q=(seed%997)/996
 shape=['round','oval','heart','lance'][seed%4]
 if 'SUCCULENT' in aid:shape='succulent'
 if 'CITRUS' in aid:shape='citrus';f='broadleaf'
 if aid=='SEA-SCENE-NGQ-037':shape='cabbage'
 if 'EDGE' in aid or '40_4L' in aid or '41_5L' in aid:shape='spreading'
 if f=='broadleaf':h=max(.3,min(1.7,dims[2]));w=max(.45,min(2.,max(dims[:2])));counts=[3,7,12+(seed%4)]
 elif f=='flower':h=max(.3,min(1.1,dims[2]));w=max(.36,min(1.15,max(dims[:2])));counts=[3,6,10]
 elif f=='palm':h=max(1.1,min(4.3,dims[2]));w=max(.85,min(2.65,max(dims[:2])));counts=[3,5,8]
 elif f=='vine':h=max(.55,min(3.2,dims[2]));w=max(.35,min(1.0,dims[0]));counts=[4,9,16]
 elif f=='grass':h=max(.25,min(1.35,dims[2]));w=max(.28,min(1.8,max(dims[:2])));counts=[4,8,15]
 elif f=='reed':h=max(.65,min(2.2,dims[2]));w=max(.35,min(1.1,max(dims[:2])));counts=[3,5,8]
 elif f=='moss':h=.10+.05*q;w=max(.4,min(1.4,max(dims[:2])));counts=[5,11,21]
 elif f=='kelp':h=2.4;w=1.1;counts=[3,6,10]
 elif f=='water_leaf':h=.12;w=.74;counts=[1,2,3]
 elif f=='tomato':h=1.3;w=1.;counts=[3,7,12]
 else:raise ValueError(f)
 is_cover=any(x in aid for x in ['MOSS','TURF','ORF2-GRASS','MOUND'])
 if is_cover and f=='grass':h=.35 if 'TURF_CORE' in aid else min(.65,h);w=min(1.8,w)
 petal_color='white' if any(t in aid for t in ['DAISY','WHITE']) else ('yellow' if any(t in aid for t in ['GOLD','YELLOW','FSH-FLOWERS']) else 'pink')
 petals=6 if 'DAISY' in aid else (8 if 'COSMOS' in aid else 5)
 traits={'leaf_shape':shape,'spread':round(.18+.14*q,3),'azimuth':round(q*6.283185,5),'green_cycle':['leaf','leaf_light','sage','fern'] if f!='kelp' else ['jade','fern','leaf_mid'],'petal_color':petal_color,'petals':petals,'coverage_patch':is_cover,'branch_count_large':1+seed%3,'roundness':round(.55+.25*q,3)}
 subfamily=f+'_'+str(sum(1 for x in plants if x['family']==f)//12+1).zfill(2)
 variants=[]
 for i,(key,cn) in enumerate([('small','小'),('medium','中'),('large','大')]):
  variants.append({'growth_key':key,'label':cn,'height_target':round(h*[.38,.68,1][i],4),'spread_target':round(w*[.38,.69,1][i],4),'organ_budget':counts[i],'triangle_budget':6000 if f=='palm' else 3600,'collection':f'{n["display_name"]}_{cn}__{aid}'})
 plants.append({**n,'family':f,'seed':seed,'traits':traits,'subsuite':subfamily,'source':e['source'],'source_library':'art_source/vegetation/libraries/v001/vegetation_library.blend','source_collection':e['collection'],'source_dimensions':dims,'archive_original_stage':e.get('original_stage','pending'),'build_mode':'new_procedural_growth_geometry_from_named_reference','anchor':'top_center_attachment' if f=='vine' else 'bottom_center','variants':variants,'note':'Three botanical forms, no seasonal state. Coverage assets use reusable small patch, never runtime surface replacement.' if is_cover else 'Static source-only variants; root layout and runtime bindings unchanged.'})
assert len(plants)==98 and len({p['display_name'] for p in plants})==98
subcounts=collections.Counter(p['subsuite'] for p in plants);assert all(v*3<=50 for v in subcounts.values())
protect={'art_source/vegetation/libraries/v001/vegetation_library.blend':sha(R/'art_source/vegetation/libraries/v001/vegetation_library.blend'),'art_source/crops/libraries/v001/planting_library.blend':sha(R/'art_source/crops/libraries/v001/planting_library.blend')}
for p in ['godot/scenes/main.tscn','godot/assets/data/crops.json','godot/src/crops/flower_view.gd','godot/src/farming/farm_plot.gd','assets/registry/current_source_index.json']:
 protect[p]=sha(R/p)
for path in (R/'art_source/shared/palettes').glob('*'):
 if path.is_file():protect[path.relative_to(R).as_posix()]=sha(path)
plan={'schema_version':2,'library_id':'SEA-LIB-VEGETATION-GROWTH-V002','path':'art_source/vegetation/libraries/v002/vegetation_library.blend','season_variants':False,'growth_axis':['small','medium','large'],'growth_labels':['小','中','大'],'plant_count':98,'component_count':294,'plants':plants,'subsuite_component_counts':{k:v*3 for k,v in subcounts.items()},'coordinate_system':'Blender Z-up metres','geometry_rule':'Independent organ counts, branches, leaf unfolding and crown dimensions; not whole-model scale copies.','primary_source_migration':False,'runtime_integration':False,'palette':'art_source/shared/palettes/sea_cozy_8x8_512.png','protected_inputs':protect}
assert OUT.is_dir() and W.is_dir()
(OUT/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(W/'protected_inputs.json').write_text(json.dumps(protect,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'plants':len(plants),'variants':294,'subsuite_component_counts':plan['subsuite_component_counts'],'season_variants':False,'protected':len(protect)},ensure_ascii=False))
