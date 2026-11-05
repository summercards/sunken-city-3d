"""Pack the new broad-leaf Image-2 sprites; preserve the complete generated source."""
from PIL import Image
from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/v003';W=R.parent/'sea-work/vegetation_meadow_20261105'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
source=D/'grass_mound_atlas_generated.png';im=Image.open(source).convert('RGBA');atlas=Image.new('RGBA',(2048,2048));tiles=[]
assert im.size==(2048,2048)
for i in range(4):
 x=i%2;y=i//2;part=im.crop((x*1024,y*1024,(x+1)*1024,(y+1)*1024))
 box=part.getchannel('A').point(lambda a:255 if a>=80 else 0).getbbox();assert box
 sprite=part.crop(box);sprite.putalpha(sprite.getchannel('A').point(lambda a:min(255,round(a*255/254))))
 atlas.paste(sprite.resize((992,992),Image.Resampling.LANCZOS),(x*1024+16,y*1024+16));tiles.append(dict(tile=i,source_crop=list(box)))
atlas.save(D/'meadow_atlas.png');dest=R/'godot/assets/textures/vegetation/meadow_atlas.png';dest.write_bytes((D/'meadow_atlas.png').read_bytes())
W.mkdir(parents=True,exist_ok=True);preview=Image.new('RGBA',atlas.size,(105,113,113,255));preview.alpha_composite(atlas);preview.convert('RGB').resize((1024,1024)).save(W/'atlas_review.jpg')
(D/'texture_production.json').write_text(json.dumps(dict(model='gpt-image-2',source=source.relative_to(R).as_posix(),source_sha256=sha(source),processed_source=(D/'meadow_atlas.png').relative_to(R).as_posix(),processed_sha256=sha(D/'meadow_atlas.png'),runtime=dest.relative_to(R).as_posix(),runtime_sha256=sha(dest),reference='video reference_04s and previous fine atlas as counter-reference',size=list(atlas.size),alpha_extrema=list(atlas.getchannel('A').getextrema()),operations=['alpha-bounded crop','normalize maximum alpha 254 to 255','16px gutter, no repainting'],tiles=tiles),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('MEADOW_ATLAS_OK')
