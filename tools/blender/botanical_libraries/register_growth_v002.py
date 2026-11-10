"""Register only v002 derived model-library references; retain every original field."""
import argparse,copy,hashlib,json,os
from pathlib import Path
R=Path(__file__).resolve().parents[3]
W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_growth/v002'
LIBS=[R/f'art_source/{domain}/libraries/v002/library_manifest.json' for domain in ['vegetation','crops']]
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def dump(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def without_v002_refs(row,ids):
 out=copy.deepcopy(row)
 if 'library_refs' in out:out['library_refs']=[r for r in out['library_refs'] if r.get('library_id') not in ids]
 return out

def main(write=False):
 assert W.is_dir()
 routes=read(R/'assets/registry/ledger_index.json')['domains']
 paths={name:R/routes[name]['ledger'] for name in ['scenes','crops','vegetation']}
 raw={name:p.read_bytes() for name,p in paths.items()};before={name:json.loads(data) for name,data in raw.items()};after=copy.deepcopy(before)
 lookup={}
 for domain,data in after.items():
  for a in data['assets']:
   assert a['asset_id'] not in lookup,'Duplicate '+a['asset_id']
   lookup[a['asset_id']]=(domain,a)
 names=read(R/'tools/blender/botanical_libraries/plant_names_v002.json')['plants'];name_map={p['asset_id']:p['display_name'] for p in names}
 assert len(names)==104 and len(name_map)==104 and len(set(name_map.values()))==104
 manifest_updates=[];refs={};library_ids=set();libraries=[]
 for domain,mp in zip(['vegetation','crops'],LIBS):
  manifest=read(mp);path=R/manifest['path'];library_ids.add(manifest['library_id'])
  report_path=W/domain/'verification_report.json';report=read(report_path)
  assert report['passed'] and not report['failures'],report
  expected=report.get('sha256',report.get('blend_sha256'))
  assert sha(path)==manifest['sha256']==expected,'Source/report mismatch '+str(path)
  assert manifest['season_variants'] is False and manifest['growth_axis']==['small','medium','large']
  grouped={}
  for member in manifest['members']:grouped.setdefault(member['asset_id'],[]).append(member)
  for aid,members in grouped.items():
   assert aid in lookup and aid in name_map,aid
   members=sorted(members,key=lambda m:['small','medium','large'].index(m['growth_key']))
   assert [m['growth_key'] for m in members]==['small','medium','large'],aid
   assert all(m['display_name']==name_map[aid] for m in members)
   refs[aid]={'library_id':manifest['library_id'],'path':manifest['path'],'sha256':manifest['sha256'],'manifest':mp.relative_to(R).as_posix(),'collections':[m['collection'] for m in members],'growth_forms':{m['growth_key']:m['collection'] for m in members},'display_name':name_map[aid],'season_variants':False,'kind':'derived_growth_models_not_primary_source','source_verification':'reopened_append_verified','original_stage_unchanged':True,'runtime_integration':False}
  manifest['status']='source_models_reopened_append_verified'
  manifest['source_verification']=str(report_path)
  manifest['source_verification_sha256']=sha(report_path)
  manifest['primary_source_migration']=False
  manifest_updates.append((mp,manifest))
  libraries.append({'library_id':manifest['library_id'],'path':manifest['path'],'sha256':manifest['sha256'],'plants':len(grouped),'models':len(manifest['members']),'source_checks':report['checks']})
 assert set(refs)==set(name_map) and len(refs)==104
 changed=[]
 for aid,ref in refs.items():
  domain,row=lookup[aid];existing=row.setdefault('library_refs',[]);old=next((r for r in existing if r.get('library_id')==ref['library_id']),None)
  if old!=ref:changed.append(aid)
  if old is None:existing.append(ref)
  else:existing[existing.index(old)]=ref
 for domain,data in after.items():
  assert len(data['assets'])==len(before[domain]['assets'])
  assert {k:v for k,v in data.items() if k!='assets'}=={k:v for k,v in before[domain].items() if k!='assets'}
  for a,b in zip(data['assets'],before[domain]['assets']):
   assert without_v002_refs(a,library_ids)==without_v002_refs(b,library_ids),'Changed original field '+a['asset_id']
 plan=read(R/'art_source/vegetation/libraries/v002/component_plan.json')
 for p,h in plan['protected_inputs'].items():assert sha(R/p)==h,'Protected '+p
 backup=W/'registration_backup';assert backup.parent.is_dir()
 result={'passed':True,'write':write,'referenced_asset_ids':104,'counts_by_domain':{d:sum(lookup[aid][0]==d for aid in refs) for d in paths},'changed_asset_ids':len(changed),'primary_record_count_unchanged':True,'all_original_fields_and_prior_library_refs_unchanged':True,'current_source_index_unchanged':True,'new_primary_asset_ids':0,'season_variants':False,'runtime_integration':False,'libraries':libraries}
 if write:
  backup.mkdir(exist_ok=True)
  for domain,path in paths.items():
   assert path.read_bytes()==raw[domain],'Concurrent edit '+str(path)
   bp=backup/(domain+'.before.json')
   if not bp.exists():bp.write_bytes(raw[domain])
  for domain,path in paths.items():
   if after[domain]!=before[domain]:dump(path,after[domain])
  for mp,manifest in manifest_updates:dump(mp,manifest)
  previous=W/'registration.json'
  if previous.exists() and not changed:
   result['initial_changed_asset_ids']=read(previous).get('initial_changed_asset_ids',read(previous).get('changed_asset_ids'))
  dump(previous,result)
 print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--write',action='store_true');main(ap.parse_args().write)
