"""Freeze the small reusable kit before authoring; no legacy source is edited."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
DEST=ROOT/'art_source/vegetation/v001'
ASSETS=[
 ('grass_fine','细叶柔草','grass',70),('grass_round','圆叶短草','grass',70),
 ('mound_round','圆润草堆','mound',1700),('mound_spread','铺展草堆','mound',1700),
 ('broadleaf','宽叶盆栽','leaf',700),('daisy','白瓣野花','flower',850),
 ('pink_flower','粉瓣野花','flower',850),('turf_pad','柔边草皮基底','base',160)]
def write(p,v):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':
 assert not (DEST/'component_plan.json').exists(), 'Plan already exists; explicitly version revisions.'
 write(DEST/'component_plan.json',dict(schema_version=1,status='frozen_before_geometry',suite='shared_vegetation',version='v001',palette='art_source/shared/palettes/sea_cabin_timber_8x8_512.png',consumers=['solar_cabin','rooftop_ranch'],reference='user video b586549578ed79117367dc27e97b38c22c1a0e49546c614324369bbc946750e6; aesthetic only, original geometry',components=[dict(key=k,label=l,profile=p,triangle_budget=b,asset_id='SEA-VEG-'+k.upper().replace('_','-')) for k,l,p,b in ASSETS],contract=dict(uv0='PaletteUV',color='linear RGBA main bend / detail / phase / AO',root='bottom_center',collision='none',optimization='separate persistent optimized.blend')))
