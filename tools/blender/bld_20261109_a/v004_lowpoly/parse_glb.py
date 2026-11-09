import struct,json
from pathlib import Path
p=Path('D:/projects/sea/godot/assets/models/facilities/water_building_001/water_building_001.glb');b=p.read_bytes();magic,ver,total=struct.unpack_from('<4sII',b,0);off=12;chunks=[]
while off<len(b):
 n,typ=struct.unpack_from('<I4s',b,off);dat=b[off+8:off+8+n];chunks.append((typ,n,dat));off+=8+n
j=json.loads(chunks[0][2].rstrip(b' \\x00')) if chunks else {}
print(json.dumps({'magic':magic.decode(errors='ignore'),'version':ver,'total':total,'chunks':[(t.decode(errors='ignore'),n) for t,n,_ in chunks],'json_keys':list(j.keys()),'scenes':j.get('scenes'),'scene':j.get('scene'),'nodes':len(j.get('nodes',[])),'meshes':len(j.get('meshes',[]))},ensure_ascii=False,indent=2))
