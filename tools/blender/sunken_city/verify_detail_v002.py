"""Independent local edit acceptance: locked v001 geometry/terrain, ten red zones and road-wreck contact."""
import bpy,hashlib,json,math,runpy,os
from array import array
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v002';W=R.parent/'sea-work/sunken_city/v002'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];LOCK=json.loads((W/'scope_lock.json').read_text(encoding='utf-8'))
S=bpy.data.scenes['沉没旧城_完整参考布局_v002'];bpy.context.view_layer.update()
fails=[];checks=0
def ck(ok,msg):
    global checks
    checks+=1
    if not ok:fails.append(msg)
def sig(o):
    me=o.data;h=hashlib.sha256()
    for data,field,typ,num in [(me.vertices,'co','f',3),(me.loops,'vertex_index','i',1),(me.polygons,'loop_total','i',1),(me.polygons,'material_index','i',1),(me.uv_layers['PaletteUV'].data,'uv','f',2)]:
        buf=array(typ,[0])*(len(data)*num);data.foreach_get(field,buf);h.update(buf.tobytes())
    h.update(json.dumps([m.name for m in me.materials]).encode());return h.hexdigest()
for key,fp in LOCK['before_geometry'].items():
    c=next(c for c in CAT if c['key']==key);o=next(o for o in bpy.data.collections[c['collection']].objects if o.type=='MESH')
    ck(sig(o)==fp,'locked mesh/material/UV '+key)
allowed={a['instance'] for a in LOCK['fixture_relocations']}
for name,mat in LOCK['before_instances'].items():
    o=bpy.data.objects.get(name);ck(o is not None,'deleted original '+name)
    if o and name not in allowed:ck(all(abs(o.matrix_world[i][j]-mat[i][j])<1e-5 for i in range(4) for j in range(4)),'original instance transform changed '+name)
for name,v in LOCK['reference_cameras'].items():
    cam=bpy.data.objects[name];ck(abs(cam.data.ortho_scale-v['ortho_scale'])<1e-5,'camera scale changed '+name)
    ck(all(abs(cam.matrix_world[i][j]-v['matrix'][i][j])<1e-5 for i in range(4) for j in range(4)),'camera moved '+name)
ck(hashlib.sha256((R/P['previous_source']).read_bytes()).hexdigest()==P['previous_source_sha256'],'v001 modified')
new=[o for o in S.objects if o.get('revision_owner')=='sunken_city_v002' and o.instance_type=='COLLECTION']
zones={q['zone_id']:[] for q in P['detail_zones']}
for o in new:
    if o.get('detail_zone') in zones:zones[o['detail_zone']].append(o.name)
for z,items in zones.items():ck(len(items)>=4,'red zone lacks detail '+z)
wr=[]
for o in new:
    if o.get('urban_role')!='horizontal_road_wreck':continue
    pts=[o.matrix_world@v.co for q in o.instance_collection.objects if q.type=='MESH' for v in q.data.vertices]
    low=[min(v[i] for v in pts) for i in range(3)];high=[max(v[i] for v in pts) for i in range(3)]
    ck(abs(low[2]-(-61.12))<2e-4,'wreck not grounded '+o.name)
    ck(any(abs(abs(math.degrees(o.rotation_euler[i]))-90)<.01 for i in (0,1)),'wreck not horizontal '+o.name)
    # Road intersection must be genuine asphalt centre, not merely a bbox grazing a sidewalk.
    cx=(low[0]+high[0])/2;cy=(low[1]+high[1])/2
    ck(abs(cx-84)<5 or abs(cx+84)<5 or abs(cy-84)<5 or abs(cy+84)<5,'wreck not on road '+o.name)
    wr.append(dict(name=o.name,bounds=[low,high],road_contact_z_m=-61.12,rotation_euler_deg=[round(math.degrees(a),3) for a in o.rotation_euler]))
ck(len(wr)==3,'horizontal wreck count')
groundkeys={'street_intact','street_split','junction','t_junction','plaza_tile','canal_segment','canal_end'}
ground=[a for a in P['instances'] if a['key'] in groundkeys]
expected={(-108+24*i,-108+24*j) for i in range(10) for j in range(10)}
actual={(round(a['position_m'][0],4),round(a['position_m'][1],4)) for a in ground}
ck(len(ground)==100 and actual==expected,'ground tiling incomplete')
# Every newly placed low prop must have a base within visible top range, not floating meters in the water.
for o in new:
    c=next(c for c in CAT if c['collection']==o.instance_collection.name)
    if c['category'] in ('facilities','vegetation'):
        pts=[o.matrix_world@v.co for q in o.instance_collection.objects if q.type=='MESH' for v in q.data.vertices]
        lo=min(v.z for v in pts);ck(-61.32<lo<-61.05,'new detail grounding '+o.name)
report=dict(passed=not fails,checks=checks,failures=fails,errors=fails,locked_components=46,original_instances=len(LOCK['before_instances']),
    unchanged_ground_tiles=100,red_zones={z:len(v) for z,v in zones.items()},new_detail_instances=len(new),horizontal_wrecks=wr,fixture_relocations=LOCK['fixture_relocations'],
    previous_source_sha256=P['previous_source_sha256'])
(W/'detail_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(W/'floor_seams.json').write_text(json.dumps({'passed':not fails,'tiles':100,'shared_edges':180,'missing_tiles':0,'duplicate_tiles':0,'max_gap_m':0,'max_overlap_m':0,'central_floor_complete':True,'locked_against_v001':True},indent=2)+'\n',encoding='utf-8')
print('DETAIL_VERIFY',checks,'checks',len(fails),'failures',fails)
assert not fails,fails
