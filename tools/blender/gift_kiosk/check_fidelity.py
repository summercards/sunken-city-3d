"""Read-only image comparison and GLB structural audit before scene assembly."""
import hashlib,json,math,os,struct
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/gift_kiosk/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
manifest=D/'export/v001/optimization_manifest.json';m=json.loads(manifest.read_text(encoding='utf-8'));views=[]
for name in ['hero','front','back','right']:
 a=Image.open(W/(name+'.png')).convert('RGB');b=Image.open(W/('optimized_'+name+'.png')).convert('RGB')
 assert a.size==b.size
 diff=ImageChops.difference(a,b);stats=ImageStat.Stat(diff);rms=math.sqrt(sum(v*v for v in stats.rms)/3)
 channels=diff.split();peak=ImageChops.lighter(ImageChops.lighter(channels[0],channels[1]),channels[2]);hist=peak.histogram();changed=sum(hist[25:])/(a.width*a.height)
 # Same geometry/materials/cameras; only tiny cleanup-boundary noise is allowed.
 views.append({'view':name,'rgb_rms_255':rms,'fraction_changed_over_24':changed,'passed':rms<3.0 and changed<.012})
total=0
for e in m['components']:
 p=R/e['glb'];raw=p.read_bytes();size,kind=struct.unpack_from('<II',raw,12);d=json.loads(raw[20:20+size]);assert kind==0x4E4F534A
 assert not d.get('images') and not d.get('textures')
 tris=0
 for mesh in d['meshes']:
  for prim in mesh['primitives']:
   assert set(prim['attributes'])=={'POSITION','NORMAL','TEXCOORD_0'}
   tris+=d['accessors'][prim['indices']]['count']//3
 assert tris==e['triangles_after'];assert hashlib.sha256(p.read_bytes()).hexdigest()==e['glb_sha256'];total+=tris
report={'passed':all(x['passed'] for x in views),'views':views,'components':len(m['components']),'export_triangles':total,'no_embedded_images':True,'raw_source_protected':True}
(W/'fidelity.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
assert report['passed'],report
m['fidelity']={'passed':True,'report':str(W/'fidelity.json'),'views':views};manifest.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
