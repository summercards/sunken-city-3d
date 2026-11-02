"""Register this kit only; never mass-accept hashes from unrelated work."""
import argparse,hashlib,json,struct
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/wild_fishery/v001';E=D/'export/v001'
if (D/'asset_manifest.json').exists() and json.loads((D/'asset_manifest.json').read_text(encoding='utf-8')).get('runtime_revision_report'):
 raise SystemExit('The runtime layout has been manually revised. Update reviewed ledger rows individually; do not re-register the historical source plan.')
parser=argparse.ArgumentParser();parser.add_argument('--verified-report',type=Path,required=True);args=parser.parse_args()
verification=json.loads(args.verified_report.read_text(encoding='utf-8'))
for name in ['fishery-environment','visual-fishery-environment','fishery','visual-fishery']:
 assert verification['results'][name]['passed'],name+' must pass with current imports'
assert verification.get('asset_import',{}).get('exit_code')==0 and not verification['asset_import']['unexpected_errors']
cat=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));opt=json.loads((E/'optimization_manifest.json').read_text(encoding='utf-8'));ex=json.loads((E/'export_manifest.json').read_text(encoding='utf-8'))
assert opt['fidelity_status'].startswith('passed')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(R/opt['source'])==opt['source_sha256_before']==opt['source_sha256_after']
assert sha(R/opt['optimized'])==opt['optimized_sha256']
for path,digest in plan['protected_files'].items():assert sha(R/path)==digest
def save(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def geometry_hash(path):
 raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);blob=raw[28+size:];h=hashlib.sha256()
 for mesh in doc['meshes']:
  for primitive in mesh['primitives']:
   for accessor_id in [primitive['attributes']['POSITION'],primitive['indices']]:
    a=doc['accessors'][accessor_id];view=doc['bufferViews'][a['bufferView']];start=view.get('byteOffset',0);h.update(blob[start:start+view['byteLength']])
 return h.hexdigest()
index=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'));route=index['domains']['scenes'];book_path=R/route['ledger'];book=json.loads(book_path.read_text(encoding='utf-8'))
records=[];runtime_rows=[]
for item in cat:
 key=item['key'];export=next(e for e in ex['exports'] if e['key']==key);operations=next(e for e in opt['components'] if e['key']==key)
 source=R/item['component_blend'];assert sha(source)==item['source_sha256'];assert sha(R/export['runtime_path'])==export['runtime_sha256']
 prefab='godot/scenes/components/fishery/'+key+'.tscn';manifest_path=source.parent/'asset_manifest.json';aid=item['asset_id']
 manifest={'asset_id':aid,'name':item['name'],'domain':'scenes','asset_ledger':route['ledger']+'#'+aid,'version':'v001','source':item['component_blend'],'source_sha256':sha(source),'collection':item['collection'],'origin':'bottom_center','front_axis':item['front_axis'],'bounds_blender_m':item['bounds'],'material_roles':['SEA_Matte'],'palette':plan['palette'],'palette_uv':'sole UV0 / PaletteUV / eight-pixel safe inset','geometry_fingerprint':geometry_hash(R/export['runtime_path']),'collision':item['collision'],'runtime_path':export['runtime_path'],'runtime_sha256':export['runtime_sha256'],'prefab':prefab,'optimized':opt['optimized'],'optimization_manifest':str((E/'optimization_manifest.json').relative_to(R)).replace('\\','/'),'optimization':operations,'source_hash_unchanged':True,'runtime_integrated':True,'runtime_validation_report':str(args.verified_report),'license':'pending_user_reference_rights_review','category':item['category'],'reuse':'scene_local'}
 save(manifest_path,manifest)
 records.append({'asset_id':aid,'name':item['name'],'domain':'scenes','stage':'runtime_verified_provenance_pending','source':item['component_blend'],'source_sha256':sha(source),'manifest':manifest_path.relative_to(R).as_posix(),'version':'v001','runtime_path':export['runtime_path'],'runtime_sha256':export['runtime_sha256'],'prefab':prefab,'license':manifest['license'],'geometry_fingerprint':manifest['geometry_fingerprint'],'consumer_features':['SEA-AQUA','SEA-WORLD','SEA-ASSET'],'category':'fishery/'+item['category'],'optimization_manifest':manifest['optimization_manifest'],'note':'独立组件源/优化派生/真实运行验收通过；原始参考来源权属另记pending。'})
 runtime_rows.append({'path':export['runtime_path'],'bytes':(R/export['runtime_path']).stat().st_size,'sha256':export['runtime_sha256'],'asset_id':aid,'status':'runtime_component_verified_provenance_pending'})
aid='SEA-FISHERY-ASSEMBLY';source=D/'wild_fishery.blend';manifest_path=D/'asset_manifest.json'
manifest={'asset_id':aid,'name':'野外渔场升级装配','domain':'scenes','asset_ledger':route['ledger']+'#'+aid,'version':'v001','source':source.relative_to(R).as_posix(),'source_sha256':sha(source),'prefab':'godot/scenes/facilities/wild_fishery.tscn','component_count':len(cat),'instance_count':78,'component_catalog':'component_catalog.json','component_instances':'component_instances.json','optimized':opt['optimized'],'optimized_sha256':opt['optimized_sha256'],'runtime_integrated':True,'runtime_validation_report':str(args.verified_report),'license':'pending_user_reference_rights_review','feature_contracts':['SEA-AQUA-R06','SEA-AQUA-R07','SEA-AQUA-R08','SEA-ASSET-R38','SEA-WORLD-R15','SEA-SAVE-R15'],'protected_files':plan['protected_files']}
save(manifest_path,manifest)
records.append({'asset_id':aid,'name':manifest['name'],'domain':'scenes','stage':'runtime_verified_provenance_pending','source':source.relative_to(R).as_posix(),'source_sha256':sha(source),'manifest':manifest_path.relative_to(R).as_posix(),'version':'v001','runtime_path':'godot/scenes/facilities/wild_fishery.tscn','prefab':manifest['prefab'],'license':manifest['license'],'geometry_fingerprint':None,'consumer_features':['SEA-AQUA','SEA-WORLD','SEA-ASSET'],'category':'fishery/scene_assembly','note':'正式装配拥有实例位置；组件保持独立，模型和导航不重建其他场景。'})
ids={r['asset_id'] for r in records};book[route['asset_key']]=[r for r in book[route['asset_key']] if r['asset_id'] not in ids]+records;save(book_path,book)
sources=[]
for domain,rt in index['domains'].items():
 for row in json.loads((R/rt['ledger']).read_text(encoding='utf-8'))[rt['asset_key']]:sources.append({k:row[k] for k in ['asset_id','source','source_sha256','manifest']})
p=R/'assets/registry/current_source_index.json';data=json.loads(p.read_text(encoding='utf-8'));data['sources']=sources;save(p,data)
# Only reviewed task files; shared code baselines are updated explicitly below.
extra=[R/'godot/scenes/facilities/wild_fishery.tscn',R/'godot/scenes/zones/zone1_home_harbor.tscn',R/'godot/src/aqua/fishery_visual.gd',R/'godot/src/ui/fishery_panel.gd',R/'godot/assets/materials/fishery/matte.tres',R/'godot/tools/fishery_palette_import.gd',R/'godot/assets/textures/shared/sea_cabin_timber_8x8_512.png.import']
extra += list((R/'godot/scenes/components/fishery').glob('*.tscn'))
extra += list((R/'godot/assets/models/fishery').glob('*/*.glb.import'))
for path in extra:
 raw=path.read_bytes().replace(b'\r\n',b'\n');runtime_rows.append({'path':path.relative_to(R).as_posix(),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'asset_id':None,'status':'runtime_resource_verified','note':'SEA-ASSET-R38 / SEA-AQUA-R06–R08: task-reviewed fishery import/assembly contract'})
p=R/index['runtime_inventory'];inventory=json.loads(p.read_text(encoding='utf-8'));updated={r['path']:r for r in runtime_rows}
inventory['resources']=[updated.pop(r['path'],r) for r in inventory['resources']]+list(updated.values());save(p,inventory)
print('REGISTERED',len(records),'source rows and',len(runtime_rows),'reviewed runtime resources; unrelated hashes unchanged')
