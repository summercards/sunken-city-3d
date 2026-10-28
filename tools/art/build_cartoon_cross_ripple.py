"""Deterministic SVG mother and grayscale export for sparse cartoon cross ripples."""
import hashlib,json,os
from pathlib import Path
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[2]
D=R/'art_source/vfx/water_cross_ripple/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'cartoon_cross_ripple_v001'
PNG=R/'godot/assets/textures/water/cartoon_cross_ripple.png'
MARKS=[(48,53,26,21,0,.85),(210,37,22,17,12,.70),(391,66,28,22,-8,1),
       (123,171,31,22,-7,.80),(309,155,24,19,8,.65),(465,190,22,17,-4,.80),
       (40,294,23,19,7,.70),(223,294,29,23,-11,.95),(392,315,26,21,5,.75),
       (112,432,25,18,9,.65),(302,452,30,24,-5,.90),(469,454,21,17,6,.70)]
PATH='M 0 -1 Q 0.025 -0.025 1 0 Q 0.025 0.025 0 1 Q -0.025 0.025 -1 0 Q -0.025 -0.025 0 -1 Z'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':
    import math
    D.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">','<rect width="512" height="512" fill="black"/>']
    hi=Image.new('L',(4096,4096),0);draw=ImageDraw.Draw(hi)
    # The same four quadratic paths drive both editable SVG and raster export.
    pieces=[((0,-1),(.025,-.025),(1,0)),((1,0),(.025,.025),(0,1)),((0,1),(-.025,.025),(-1,0)),((-1,0),(-.025,-.025),(0,-1))]
    for x,y,w,h,angle,opacity in MARKS:
        gray=round(opacity*255)
        svg.append(f'<path d="{PATH}" transform="translate({x} {y}) rotate({angle}) scale({w} {h})" fill="rgb({gray},{gray},{gray})"/>')
        points=[];c=math.cos(math.radians(angle));s=math.sin(math.radians(angle))
        for a,b,d in pieces:
            for k in range(33):
                t=k/32;u=1-t;px=(u*u*a[0]+2*u*t*b[0]+t*t*d[0])*w;py=(u*u*a[1]+2*u*t*b[1]+t*t*d[1])*h
                points.append(((x+px*c-py*s)*8,(y+px*s+py*c)*8))
        draw.polygon(points,fill=gray)
    svg.append('</svg>');src=D/'cartoon_cross_ripple.svg';src.write_text('\n'.join(svg)+'\n',encoding='utf-8')
    source_png=D/'T_VFX_Water_CartoonCross_001_TILE.png';hi.resize((2048,2048),Image.Resampling.LANCZOS).save(source_png)
    image=hi.resize((512,512),Image.Resampling.LANCZOS);PNG.parent.mkdir(parents=True,exist_ok=True);image.save(PNG)
    imp=Path(str(PNG)+'.import')
    if not imp.exists():
        rel='res://'+PNG.relative_to(R/'godot').as_posix();cache='res://.godot/imported/'+PNG.name+'-'+hashlib.md5(rel.encode()).hexdigest()+'.ctex'
        imp.write_text(f'[remap]\nimporter="texture"\ntype="CompressedTexture2D"\npath="{cache}"\n\n[deps]\nsource_file="{rel}"\ndest_files=["{cache}"]\n\n[params]\ncompress/mode=0\ncompress/hdr_as_srgb=false\nmipmaps/generate=true\nprocess/fix_alpha_border=false\nprocess/size_limit=512\ndetect_3d/compress_to=0\n',encoding='utf-8')
    pixels=list(image.getdata());positive=sum(v>8 for v in pixels)
    assert all(image.getpixel((x,y))==0 for x,y in [(x,0) for x in range(512)]+[(x,511) for x in range(512)]+[(0,y) for y in range(512)]+[(511,y) for y in range(512)])
    assert .01<positive/len(pixels)<.07
    repeat=Image.new('L',(1024,1024))
    for x in [0,512]:
        for y in [0,512]:repeat.paste(image,(x,y))
    repeat.save(W/'repeat-2x2.png');image.resize((128,128),Image.Resampling.LANCZOS).save(W/'mask-128.png')
    write(D/'asset_manifest.json',dict(asset_id='SEA-VFX-WATER-CROSS-RIPPLE-001',asset_ledger='assets/registry/ledgers/vfx.json#SEA-VFX-WATER-CROSS-RIPPLE-001',
        version='v001',source=src.relative_to(R).as_posix(),source_sha256=sha(src),runtime_path=PNG.relative_to(R).as_posix(),runtime_sha256=sha(PNG),
        category='water_surface_texture',intended_use='linear R8 grayscale light mask, sparse cartoon four-point cross ripples on submerged geometry',
        resolution=[512,512],raster_source=source_png.relative_to(R).as_posix(),raster_source_resolution=[2048,2048],raster_source_sha256=sha(source_png),marks=12,channel='R=coverage; grayscale 8-bit; no alpha; black=0 contribution',tileable=True,
        signal_coverage=positive/len(pixels),edge='clean quadratic tapered silhouette, antialiased narrow edge, zero haze',
        license='project_original_vector_authored',generator='tools/art/build_cartoon_cross_ripple.py',stage='authored_runtime_validation_pending',
        source_note='User explicitly requests simple cartoon crosses; editable SVG source with deterministic raster export, no image generation or borrowed texture.'))
    print('MASK',PNG,'coverage',positive/len(pixels),'12 editable vector crosses')
