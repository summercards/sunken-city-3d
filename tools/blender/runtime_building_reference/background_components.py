"""Recover repeated outer-city building templates from current runtime matrices.

Authoring placement formulas only identify candidates; matches must agree with
actual baked geometry/color/transforms. Unmatched data is retained as context.
"""
import bpy,json,math,hashlib,os,re,shutil,ast
import numpy as np
from pathlib import Path
from collections import defaultdict,Counter
from mathutils import Euler,Matrix,Vector
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/runtime_building_reference/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'runtime_building_reference_v0.1'
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def smooth(a,b,v):t=max(0,min(1,(v-a)/(b-a)));return t*t*(3-2*t)
def move(x,z):return x-16*smooth(15,65,-x)*smooth(-55,-10,z)+14*smooth(20,70,x)*smooth(-65,-20,z),z+14*smooth(0,65,z)+4*smooth(15,65,-x)*smooth(10,50,z)
def matrix(x,y,z,rx,ry,rz,scale):
    # Three.js XYZ Euler order: Rx @ Ry @ Rz.
    cx,sx,cy,sy,cz,sz=math.cos(rx),math.sin(rx),math.cos(ry),math.sin(ry),math.cos(rz),math.sin(rz)
    a=np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]])@np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])@np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])
    m=np.eye(4);m[:3,:3]=a*scale;m[:3,3]=[x,y,z];return m
placements=[]
for row in range(-16,17):
 for col in range(-16,17):
    h=abs(math.sin(col*127.1+row*311.7)*43758.5453)%1
    x=col*13+math.fmod(row,2)*5.8+math.sin(row*1.7+col)*1.3;z=row*13.5-5+math.cos(col*1.4+row)*1.2
    if (x/(83*1.30))**2+((z+5)/(86*1.30))**2<1:continue
    if z< -66*1.30 and abs(x-49.56*1.30)<30:continue
    if abs(x)>204 or abs(z+5)>216:continue
    ring=math.hypot(x/(83*1.30),(z+5)/(86*1.30));front=z>20 or x<-35
    source=1+math.floor(h*5) if (col+row)%4==0 else 0
    lift=(1 if front else 8)+h*9+math.sin(col*.61+row*.83)*3
    if ring<1.4 and front:lift-=5
    yaw=math.sin(row*.7+col*.4)*.12;lean=(.12+h*.12)*(1 if col%2 else -1) if abs(col*3+row)%13==0 else 0
    x,z=move(x,z);m=matrix(x,lift,z,0,yaw,lean,1.2)
    placements.append(dict(id=f'outer_{row:+03d}_{col:+03d}',source=source,matrix=m.tolist(),kind='outer'))
# Boundary instances: parse the static numeric layout; never execute old builders.
src=(R/'web/first-region.js').read_text();layout=src.split('const layout=[')[1].split('];')[0];layout=re.sub(r'//[^\n]*','',layout)
layout=ast.literal_eval('['+layout+']')
for i,(x,z,s,l,yaw,lz,lx) in enumerate(layout):
 x,z=move(x*1.18*1.30,-5+(z+5)*1.18*1.30)
 placements.append(dict(id=f'boundary_{i:02d}',source=s,matrix=matrix(x,l,z,lx,yaw,lz,1.2).tolist(),kind='boundary'))
for i,(x,z) in enumerate([(-19,-51),(31,-22),(39,12),(-40,21),(20,43)]):
 placements.append(dict(id=f'original_ruin_{i}',source=i+1,matrix=matrix(x,0,z,0,(1 if i%2 else -1)*.12,0,1).tolist(),kind='original'))
placements.append(dict(id='original_residence',source=0,matrix=matrix(-30,0,40,0,0,0,1).tolist(),kind='original'))
catalog=json.loads((D/'catalog.json').read_text());plan=json.loads((D/'export_plan.json').read_text())
shared=json.loads((R/'godot/assets/baked/scene.json').read_text());bake=json.loads((R/'godot/assets/world/environment/bake.json').read_text());inst=np.fromfile(R/'godot/assets/world/environment/instances.bin',dtype='<f4').reshape(-1,16)
ids=[];batches=[];mats=[];world=[]
for b in catalog['items']:
 if b['category']=='playable_surface':continue
 for bi,ii in b['batch_instances']:
    raw=inst[ii];m=np.eye(4);m[:3,:3]=raw[:12].reshape(3,4)[:,:3];m[:3,3]=raw[[3,7,11]]
    ids.append(ii);batches.append(bi);world.append(m)
world=np.array(world);ids=np.array(ids);batches=np.array(batches)
origins=np.array([np.array(p['matrix'])[:3,3] for p in placements]);actual=world[:,:3,3]
nearest=[]
for chunk in np.array_split(actual,100):
 dist=((chunk[:,None,[0,2]]-origins[None,:,[0,2]])**2).sum(-1);nearest.extend(dist.argmin(1).tolist())
nearest=np.array(nearest);inv=np.linalg.inv(np.array([p['matrix'] for p in placements]));local=inv[nearest]@world
def key_at(i,m):
 b=bake['batches'][int(batches[i])]
 return (b['geom'],b['tex'],b['tint'],b['unlit'],b['alpha'],b['doubleSide'],*np.round(m[:3].ravel(),2).tolist(),*np.round(inst[ids[i],12:16],4).tolist())
counts=[Counter() for _ in range(6)];representatives=[{} for _ in range(6)];sample_counts=Counter()
for j,p in enumerate(placements):
 if p['kind']!='outer':continue
 sample_counts[p['source']]+=1;seen=set()
 for i in np.where(nearest==j)[0]:
    if np.linalg.norm(local[i][:3,3][[0,2]])>9:continue
    k=key_at(i,local[i]);seen.add(k);representatives[p['source']].setdefault(k,(int(i),local[i].copy()))
 counts[p['source']].update(seen)
templates=[]
for s in range(6):
 parts=[]
 for k,n in counts[s].items():
    if n<sample_counts[s]*.55:continue
    i,m=representatives[s][k]
    parts.append(dict(batch=int(batches[i]),instance=int(ids[i]),matrix_local=m.tolist(),votes=n,key=list(k)))
 templates.append(dict(source=s,samples=sample_counts[s],parts=parts))
print('TEMPLATES',[(t['source'],t['samples'],len(t['parts'])) for t in templates],flush=True)
# Only certify a membership when actual matrix agrees with a recovered template.
lookups=[{tuple(p['key']):p for p in t['parts']} for t in templates];matched={};errors=[];placement_matches=defaultdict(list)
for i in range(len(ids)):
 j=int(nearest[i]);s=placements[j]['source'];k=key_at(i,local[i]);p=lookups[s].get(k)
 if not p:continue
 err=float(np.max(np.abs(np.array(placements[j]['matrix'])@np.array(p['matrix_local'])-world[i])))
 if err>0.002:continue
 matched[int(ids[i])]=j;placement_matches[j].append(int(ids[i]));errors.append(err)
matched_parts={}
# Rounding-boundary and leaning-building recovery: test raw matrices against
# nearby candidate placements. This prevents nearest-anchor cuts through roofs.
part_arrays=[]
for t in templates:
    lookup=defaultdict(list)
    for pi,p in enumerate(t['parts']):
        k=p['key'];lookup[tuple(k[:6]+k[18:])].append((pi,np.array(p['matrix_local'])))
    part_arrays.append(lookup)
matched={};placement_matches=defaultdict(list);errors=[]
for i in range(len(ids)):
    if i%50000==0:print('MATCH',i,flush=True)
    b=bake['batches'][int(batches[i])];head=(b['geom'],b['tex'],b['tint'],b['unlit'],b['alpha'],b['doubleSide'],*np.round(inst[ids[i],12:16],4).tolist())
    first=int(nearest[i]);candidates=[first]
    # Most matches succeed on the first candidate; only test neighbors on failure.
    best=None
    for attempt in range(2):
        for j in candidates:
            s=placements[j]['source'];parts=part_arrays[s].get(head,[])
            if not parts:continue
            lm=inv[j]@world[i]
            aa=np.array([p[1] for p in parts]);ee=np.max(np.abs(aa-lm),axis=(1,2));k=int(ee.argmin())
            if ee[k]<.0018:
                pidx=parts[k][0];err=float(np.max(np.abs(np.array(placements[j]['matrix'])@aa[k]-world[i])))
                if err<.0025:best=(j,pidx,err);break
        if best:break
        dist=((origins[:,[0,2]]-actual[i,[0,2]])**2).sum(1);candidates=[int(j) for j in np.argsort(dist)[:4] if int(j)!=first and dist[j]<18**2]
    if best:
        j,pi,err=best;matched[int(ids[i])]=j;matched_parts[int(ids[i])]=pi;placement_matches[j].append(int(ids[i]));errors.append(err)
complete=[];partial=[]
for j,p in enumerate(placements):
 n=len(placement_matches[j]);wanted=len(templates[p['source']]['parts'])
 (complete if n==wanted else partial).append(dict(**p,matched_instances=n,template_instances=wanted))
write(W/'background_recovery.json',dict(templates=templates,placements=placements,complete=complete,partial=partial,matched_instances=len(matched),total_instances=len(ids),max_matrix_error=max(errors,default=0),matched_instance_to_placement=matched,matched_instance_to_part=matched_parts))
print('RECOVERY',len(matched),'instances;',len(complete),'complete;',len(partial),'partial; max error',max(errors,default=0),flush=True)
