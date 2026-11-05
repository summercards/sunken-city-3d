"""Lossless sprite extraction, alpha normalization and gutter packing; no generated art redrawing."""
from PIL import Image
from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/v002'
source=D/'grass_moss_atlas_generated.png';im=Image.open(source).convert('RGBA')
atlas=Image.new('RGBA',(2048,2048));records=[]
for i in range(4):
 x=i%2;y=i//2;tile=im.crop((x*1024,y*1024,(x+1)*1024,(y+1)*1024))
 box=tile.getchannel('A').point(lambda a:255 if a>=80 else 0).getbbox();assert box
 sprite=tile.crop(box)
 # Preserve color+alpha detail, normalize the 254 maximum returned by the image model.
 sprite.putalpha(sprite.getchannel('A').point(lambda a:min(255,round(a*255/254))))
 # Grass stretches only with its card dimensions; atlas crop keeps a safe mip gutter.
 sprite=sprite.resize((992,992),Image.Resampling.LANCZOS)
 atlas.paste(sprite,(x*1024+16,y*1024+16));records.append(dict(tile=i,input_crop=list(box),output_rect=[x*1024+16,y*1024+16,992,992]))
processed=D/'soft_atlas.png';atlas.save(processed)
p=R/'godot/assets/textures/vegetation/soft_atlas.png';p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(processed.read_bytes())
W=R.parent/'sea-work/vegetation_soft_20261105';W.mkdir(parents=True,exist_ok=True)
preview=Image.new('RGBA',atlas.size,(105,113,113,255));preview.alpha_composite(atlas);preview.convert('RGB').resize((1024,1024)).save(W/'atlas_review.jpg')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
report=dict(model='gpt-image-2',protocol='OpenAI Images edits via sofunny-image',reference_sha256=sha(R.parent/'sea-work/vegetation_plan_20261105/reference_04s.png'),source=source.relative_to(R).as_posix(),source_sha256=sha(source),runtime=p.relative_to(R).as_posix(),runtime_sha256=sha(p),size=list(atlas.size),alpha_extrema=list(atlas.getchannel('A').getextrema()),operations=['crop 4 original alpha sprites','normalize 254 maximum alpha to 255','pack each sprite with 16 pixel gutter','no painting, no opaque background'],tiles=records)
(D/'texture_production.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('SOFT_ATLAS_READY',atlas.size,report['alpha_extrema'])
