"""Freeze v002 red-box detail scope before creating meshes. Keeps v001 immutable."""
from pathlib import Path
import copy,hashlib,json,math,os
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/sunken_city/v001';D=OLD.parent/'v002';W=R.parent/'sea-work/sunken_city/v002'
assert D.is_dir() and W.is_dir() and not (D/'sunken_city_v002.blend').exists()
P=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components']
ref=Path.home()/'.workbuddy/clipboard-images/clipboard-2026-11-05T06-27-38-484Z-1a49a23a.jpg'
# Solve planar projective transform from four visible 240m ground corners. Screen is a perspective screenshot.
pts=[((229,182),(-120,-120)),((651,32),(-120,120)),((862,444),(120,120)),((392,647),(120,-120))]
A=[]
for (x,y),(u,v) in pts:
    A.extend([[x,y,1,0,0,0,-u*x,-u*y,u],[0,0,0,x,y,1,-v*x,-v*y,v]])
for i in range(8):
    j=max(range(i,8),key=lambda j:abs(A[j][i]));A[i],A[j]=A[j],A[i]
    q=A[i][i];A[i]=[v/q for v in A[i]]
    for j in range(8):
        if i!=j:
            q=A[j][i];A[j]=[a-q*b for a,b in zip(A[j],A[i])]
h=[a[8] for a in A]+[1]
def world(x,y):
    den=h[6]*x+h[7]*y+1
    return [(h[0]*x+h[1]*y+h[2])/den,(h[3]*x+h[4]*y+h[5])/den]
boxes=[(302,197,348,227),(336,383,395,420),(437,322,493,391),(621,260,694,302),(638,307,710,342),(639,339,738,433),(526,399,580,445),(430,448,457,489),(486,435,519,532),(479,504,560,590)]
P=copy.deepcopy(P);P.update(version='v002',revision='red_box_detail_20261105_1427',status='frozen_before_geometry',
    previous_source='art_source/scenes/sunken_city/v001/sunken_city_v001.blend',
    previous_source_sha256=hashlib.sha256((OLD/'sunken_city_v001.blend').read_bytes()).hexdigest(),
    added_reference={'local_path':str(ref),'sha256':hashlib.sha256(ref.read_bytes()).hexdigest(),'role':'ten red-box enrichments and horizontal building wrecks on roads'},
    screenshot_calibration={'method':'four-point projective ground plane, visual corner estimate','anchors':pts,'homography':h,'uncertainty_m':3})
P['detail_zones']=[dict(zone_id=f'redbox_{i+1:02}',screen_box=list(b),world_xy=[round(v,2) for v in world((b[0]+b[2])/2,(b[1]+b[3])/2)],intent=intent) for i,(b,intent) in enumerate(zip(boxes,[
 'collapsed road crossing and snapped pole', 'roadside fallen building and concrete fragments',
 'low utility yard, benches, encrustation; no new upright building', 'service court and ticket kiosk by existing shop',
 'low retaining walls and utility pumping point', 'large eastern court with two unequal detail islands, no new tower',
 'rubble fan beside exposed-room building', 'abandoned delivery vehicle, low debris and kelp',
 'horizontal building on southern boulevard and fallen street fixtures', 'abandoned service forecourt around existing outer house']))]
new=[('retaining_wall_ruin','残破矮挡墙_挂管与缺口','low_wall',[8,2,2.2]),
 ('pump_cabinet','旧排水泵柜_外露管路','utility',[3.4,2.7,2.5]),
 ('kiosk_ruin','旧报刊售票亭_破顶','kiosk',[5.5,4.2,4.0]),
 ('bench','旧街头长凳_断靠背','bench',[3.5,1.1,1.3])]
for key,name,family,size in new:
    c=dict(key=key,slug=key,name=name,component_family=family,category='facilities',component_id='SEA-SCENE-SCITY-'+key.replace('_','-').upper(),building_class='underwater',scope='scene_local',origin='bottom_center',front_axis='-Y',allowed_rotations_y_deg=[0,90,180,270],size_design_m=size,collision=False,interactive=False,emission=False,instance_count=0)
    P['components'].append(c)
P['component_budget']={'limit':50,'planned':len(P['components']),'remaining':50-len(P['components'])}
assert len(P['components'])==50
P['scope_lock']={'locked':'all 46 v001 component geometries/materials, all 100 aligned ground transforms, all existing 260 instances except explicitly recorded fixture relocations if a fallen wreck intersects',
    'editable':'new low detail instances in red-box patches and up to three new horizontal building wreck instances along roads; cameras for added detail views only',
    'central':'no new upright or horizontal whole building in original central building exclusion; low street detail only',
    'ground':'all ground must remain exactly unchanged; no background/animals/Godot'}
for c in P['components']:c['version']='v002'
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('V002_FROZEN',len(P['components']))
for q in P['detail_zones']:print(q['zone_id'],q['world_xy'],q['intent'])
