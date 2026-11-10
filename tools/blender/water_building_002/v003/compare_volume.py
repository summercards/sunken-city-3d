"""Same-camera visual evidence for volume-only user change."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib
R=Path('D:/projects/sea');W=R.parent/'sea-work/water_building_002/v003';D=R/'art_source/scenes/water_building_002/v003'
images=[D/'reference.jpg',W/'before.png',W/'hero.png'];font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25);small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
width=600;height=850;canvas=Image.new('RGB',(width*3,height+145),(27,35,37));draw=ImageDraw.Draw(canvas)
labels=['原画参考','调整前 · 树冠偏稀','调整后 · 仅改现有体积']
for i,(p,label) in enumerate(zip(images,labels)):
 im=Image.open(p).convert('RGB');im.thumbnail((width-20,height-20));x=i*width+(width-im.width)//2;y=55+(height-im.height)//2;canvas.paste(im,(x,y));draw.text((i*width+20,15),label,font=font,fill=(230,235,230))
draw.text((22,height+65),'28 种组件 / 167 个实例 / 18 个树冠实例保持不变',font=font,fill=(230,235,230));draw.text((22,height+106),'不加叶片，不加枝条，不增细节。整栋 10,342 三角面，6,293 多边形。',font=small,fill=(189,202,197));canvas.save(W/'reference_before_after.jpg',quality=94)
metrics={}
for name,p in [('before',W/'before.png'),('after',W/'hero.png')]:
 im=Image.open(p).convert('RGB');px=im.getdata();n=0
 for rr,g,b in px:
  if g>rr*1.12 and g>b*1.25 and g>45:n+=1
 metrics[name]={'method':'green-pixel ratio of identical full-frame render; not reference segmentation','green_pixels':n,'image_pixels':im.width*im.height,'green_frame_ratio':n/(im.width*im.height)}
metrics['relative_green_pixel_multiplier']=metrics['after']['green_pixels']/max(metrics['before']['green_pixels'],1)
metrics['mesh_and_topology_proof']='volume_revision.json and source_verification.json';metrics['changed_existing_crowns']=18;metrics['added_meshes']=0;metrics['added_triangles']=0;metrics['source_sha256']=hashlib.sha256((D/'water_building_002_v003.blend').read_bytes()).hexdigest()
(W/'volume_visual_comparison.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(metrics,ensure_ascii=False,indent=2))
