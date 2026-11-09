"""Freeze B1109A v003 under longest-axis taper and legal contact rules."""
from pathlib import Path
import json, shutil, hashlib
R=Path('D:/projects/sea');V2=R/'art_source/scenes/bld_20261109_a/v002';D=R/'art_source/scenes/bld_20261109_a/v003';D.mkdir(parents=True,exist_ok=True)
for name in ('reference.jpg','reference_measurements.json'):
 src=V2/name
 if src.exists():shutil.copy2(src,D/name)
plan=json.loads((V2/'component_plan.json').read_text(encoding='utf-8'));catalog=json.loads((V2/'catalog.json').read_text(encoding='utf-8'));cat=catalog['components'];cat=cat['components'] if isinstance(cat,dict) and 'components' in cat else cat;old_instances=json.loads((V2/'component_instances.json').read_text(encoding='utf-8'))
# v003 keeps the stable v001 AssetID family; version is the source revision, not a duplicate logical asset.
for c in plan['components']:
 e=next(x for x in cat if x['key']==c['key']);extent=e.get('bounds_size',[1,1,1]);
 c['id']='SEA-SCENE-B1109A-'+c['key'].upper().replace('_','-');c['asset_id']=c['id'];c['version']='v003';c['component_source']=f'art_source/scenes/bld_20261109_a/v003/component_packages/{c["key"]}/{c["key"]}.blend';c['extent']=[round(float(v),6) for v in extent]
 if c['kind'] in {'plant','soft'}:continue
 c['taper_along']=max(('x','y','z'),key=lambda a:{'x':extent[0],'y':extent[1],'z':extent[2]}[a])
 # flat plates use longest-axis taper and define rho on its section height/depth.
 if c['kind']=='linear':
  c['d_bottom']=c.get('d_bottom',.12);c['d_top']=c.get('d_top',c['d_bottom']*.9)
 # keep plan dimensions; actual geometry audit is authoritative after Blender iteration.
# Explicit contact contract: all attached components get at least one legal relation.
attached={
 'main_sign':('shell','inset',.006,'招牌背板嵌入前墙浅槽'),
 'awning':('shell','clearance',.006,'篷面与店面留6mm安装缝'),
 'blade_sign':('shell','inset',.006,'侧挑牌托架嵌入转角柱槽'),
 'poster_panel':('shell','clearance',.004,'广告板与侧墙留4mm'),
 'ac_unit':('shell','inset',.006,'外机脚座嵌入墙面托槽'),
 'pipe_set':('shell','inset',.004,'排水管在墙面开竖槽'),
 'vent_duct':('shell','inset',.006,'风管接口进入墙面开洞'),
 'antenna':('roof_hut','inset',.004,'天线底座嵌入屋顶支座'),
 'clothesline':('roof_hut','clearance',.004,'晾衣架端头留安装缝'),
 'barred_window':('shell','inset',.006,'窗框嵌入窗洞槽'),
 'transom':('shell','inset',.006,'亮窗框嵌入窗洞槽'),
 'backdoor':('shell','inset',.006,'背门框嵌入门洞槽'),
 'stair_ladder':('shell','inset',.006,'梯子竖杆嵌入转角柱竖槽'),
 'shop_lintel':('shell','clearance',.004,'门楣与墙壳留4mm'),
 'fascia':('shell','clearance',.004,'檐牌与墙壳留4mm'),
 'side_eave':('shell','clearance',.004,'侧檐与墙壳留4mm'),
 'coping':('shell','miter',.004,'女儿墙檐口四角斜接'),
}
contacts=[]
for key,(host,relation,gap,note) in attached.items():
 c=next(x for x in plan['components'] if x['key']==key);host_row=next(x for x in plan['components'] if x['key']==host);c['attached_to']=host_row['id'];contacts.append({'a':c['id'],'b':host_row['id'],'relation':relation,'gap_m':gap,'cut_verified':True if relation=='boolean_cut' else None,'note':note})
# remove null cut flags and define real geometry obligations.
for ct in contacts:
 if ct['cut_verified'] is None:ct.pop('cut_verified')
plan['clause']='SEA-ASSET-R64';plan['version']='v003';plan['asset_id']='SEA-SCENE-B1109A-V003-ASSEMBLY';plan['component_budget']={'limit':50,'planned':49,'remaining':1};plan['contacts']=contacts
plan['zero_square_contract']['version']='2026-11-09f';plan['taper_along_rule']={'principle':'argmax extent; modify perpendicular cross-section; longest edge length unchanged','flat_plate_min_ratio':2.0};plan['seam_contract']={'allowed_relations':['inset','clearance','boolean_cut','miter'],'gap_m_range':[.002,.020],'forbidden_relations':['coplanar','face_to_face','interpenetrate','overlap','flush'],'attached_requires_contacts':True,'geometry_audit_required':True}
plan['stylized_form']['components']=plan['components'];plan['stylized_form']['contacts']=contacts;plan['stylized_form']['seam_contract']=plan['seam_contract']
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'component_instances.json').write_text(json.dumps(old_instances,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(D/'reference_measurements.json').write_text(json.dumps(plan['measurement'],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'version':'v003','components':len(plan['components']),'contacts':len(contacts),'taper_declared':sum('taper_along' in c for c in plan['components'] if c['kind'] not in {'plant','soft'}),'attached':len(attached),'legal_gap_range':[min(x['gap_m'] for x in contacts),max(x['gap_m'] for x in contacts)]},ensure_ascii=False))
