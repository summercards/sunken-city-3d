"""Reuse independent checks, reopen isolated packages, then restore the MCP addon."""
import bpy,json,hashlib
from pathlib import Path
R=Path('D:/projects/sea')
base=(R/'tools/blender/floating_shop/verify.py').read_text(encoding='utf-8')
prefix=base.split("for e in cat['components']:\n bpy.ops.wm.read_factory_settings")[0]
prefix=prefix.replace('/v001','/v002').replace('悬浮商铺_v001','悬浮商铺_v002').replace("/'floating_shop'","/'floating_shop/v002'").replace("'rail_post_001'","'rail_post_002'")
exec(compile(prefix,'independent_v002_checks','exec'))
# Verify an unobstructed 1.95m central route from the rail opening to the door.
obstructions=[]
for row in layout:
 if row['key'] in ['deck','under_brace','engine','engine_glow','float_pod','aux_nozzle','aux_glow']:continue
 o=sc.objects[row['name']]
 for m in o.instance_collection.objects:
  if m.type!='MESH':continue
  pts=[o.matrix_world@m.matrix_world@v.co for v in m.data.vertices];lo=[min(v[j] for v in pts) for j in range(3)];hi=[max(v[j] for v in pts) for j in range(3)]
  if lo[0]<.975 and hi[0]>-.975 and lo[1]<-6.0 and hi[1]>-9.05 and lo[2]<4.5 and hi[2]>2.56:obstructions.append(row['name']+'/'+m.name)
req(not obstructions,'entry route obstructed '+str(obstructions))
req(len(actual)==248,'revised instance count');req('rail_arc_001' not in actual and 'rail_post_001' not in actual,'front rail removed')
revision=json.loads((D/'component_instances.json').read_text())['revision'];req(revision['walkway_width_m']>=2.4,'walkway double width')
report['revision_metrics']={'previous_walkway_width_m':1.2,'new_walkway_width_m':3.0,'width_multiplier':2.5,'front_railing_opening_m':revision['entry_opening_width_m'],'clear_route_width_m':1.95,'route_obstructions':obstructions}
if errors:raise RuntimeError(str(errors))
# Save and reopen isolated component files using the proven factory-scene path.
# The plugin is restored after the last reopen because factory settings unload it.
for e in cat['components']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 with bpy.data.libraries.load(str(source),link=False) as (a,b):b.collections=[e['collection']]
 c=b.collections[0];bpy.context.scene.collection.children.link(c);bpy.context.scene.name=e['name'];bpy.context.scene.unit_settings.system='METRIC'
 p=R/e['component_source'];p.parent.mkdir(parents=True,exist_ok=True)
 for im in bpy.data.images:
  if im.source=='FILE':im.filepath=bpy.path.relpath(str(pal),start=str(p.parent))
 bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(p),compress=True)
 e['source_sha256']=sha(p);e['stage']='source_verified_runtime_pending';e['version']='v002';e['asset_ledger']='assets/registry/ledgers/scenes.json#'+e['asset_id']
 (p.parent/'asset_manifest.json').write_text(json.dumps(e,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for e in cat['components']:
 bpy.ops.wm.open_mainfile(filepath=str(R/e['component_source']));inspect(e);report['standalone_packages_reopened']+=1
report['passed']=not errors;report['errors']=sorted(set(errors));report['exit_codes']['source_validation']=0 if not errors else 1
(W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if errors:raise RuntimeError(str(errors))
(D/'catalog.json').write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.ops.wm.open_mainfile(filepath=str(source));exec((R/'tools/blender/floating_shop/restore_mcp.py').read_text(encoding='utf-8'));print('V002_VERIFIED',json.dumps(report['metrics']),json.dumps(report['revision_metrics']))
