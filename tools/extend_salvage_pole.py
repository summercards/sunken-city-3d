"""Extend the relocated upper pole downward and remove its old submerged half."""
import hashlib
import json
import os
from pathlib import Path
import struct
from split_salvage_pole_group import TARGET, ROOT, indices, compact
from restore_salvage_vertex_colors import read_glb, read_vec3, accessor_bytes

raw=TARGET.read_bytes()
doc,blob,_=read_glb(TARGET)
if doc.get('extras',{}).get('sea_extended_pole_v1'):
    print('Already extended');raise SystemExit(0)
assert doc['extras']['sea_pole_group_split_v1']
lower=doc['meshes'][1]['primitives'][1]
points=read_vec3(doc,blob,lower['attributes']['POSITION'])
removed={i for i,p in enumerate(points) if p[0]<-7.0}
assert len(removed)==43
bottom=[points[i] for i in removed if points[i][1]<-20]
rim=[points[i] for i in removed if points[i][1]>1.11]
center=lambda rows:[(min(p[k] for p in rows)+max(p[k] for p in rows))/2 for k in range(3)]
a,b=center(rim),center(bottom)
delta=[b[k]-a[k] for k in range(3)]
upper=doc['meshes'][2]['primitives'][0]
acc=upper['attributes']['POSITION']
positions=read_vec3(doc,blob,acc)
foot=[i for i,p in enumerate(positions) if p[1]<1.121]
assert foot and all(abs(positions[i][1]-1.12)<0.0001 for i in foot)
backup=Path(os.environ.get('SEA_WORK_ROOT',ROOT.parent/'sea-work'))/'backups'/('salvage-before-extension-'+hashlib.sha256(raw).hexdigest()[:12]+'.glb')
backup.parent.mkdir(parents=True,exist_ok=True);backup.write_bytes(raw)
start,count,comps,stride=accessor_bytes(doc,acc)
for i in foot:
    positions[i]=tuple(positions[i][k]+delta[k] for k in range(3))
    struct.pack_into('<3f',blob,start+i*stride,*positions[i])
doc['accessors'][acc]['min']=[min(p[k] for p in positions) for k in range(3)]
doc['accessors'][acc]['max']=[max(p[k] for p in positions) for k in range(3)]
ix=indices(doc,blob,lower['indices']);keep=[];deleted=0
for t in range(0,len(ix),3):
    triangle=ix[t:t+3]
    assert len({i in removed for i in triangle})==1
    if triangle[0] in removed:deleted+=1
    else:keep.extend(triangle)
doc['meshes'][1]['primitives'][1]=compact(doc,blob,lower,keep)
doc['extras']['sea_extended_pole_v1']={'delta':delta,'foot_vertices':len(foot),'removed_triangles':deleted,'backup_sha256':hashlib.sha256(raw).hexdigest()}
doc['buffers'][0]['byteLength']=len(blob)
js=json.dumps(doc,ensure_ascii=False,separators=(',',':')).encode();js+=b' '*(-len(js)%4);blob+=b'\0'*(-len(blob)%4)
out=struct.pack('<III',0x46546c67,2,28+len(js)+len(blob))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(blob),0x004e4942)+blob
TARGET.write_bytes(out)
print(json.dumps(doc['extras']['sea_extended_pole_v1']));print(backup)
