"""Resolve original-vs-normalized pixel coordinates and produce the delivery contact sheet."""
from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageFont
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v001';W=Path('D:/projects/sea-work/bld_20261109_a/v001')
p=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));m=json.loads((D/'reference_measurements.json').read_text(encoding='utf-8'));ref=Image.open(D/'reference.jpg')
m['original_image_size_px']=list(ref.size);m['image_size_px']=[1080,1080];m['coordinate_space']='Reference resized to 1080x1080 for every landmark; multiply normalized pixel coordinates by 1200/1080 for original image coordinates.'
m['uncertainty_note']='Point-selection tolerance only. Perspective, stylization and occlusion introduce additional unknown metric uncertainty; inferred dimensions are adopted modelling dimensions, not physically calibrated survey measurements.'
m['scale_formula']='normalized vertical_px_per_m = 298/5.1 = 58.43; floor pitch comes from the project specification. Adopted width/depth 8.6/8.2 m are perspective-informed proportion estimates, not direct px/58.43 horizontal conversion.'
p['measurement']=m
for path,data in [(D/'reference_measurements.json',m),(D/'component_plan.json',p)]:path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
im=ref.convert('RGB').resize((1080,1080));dr=ImageDraw.Draw(im)
# Use unoccluded sign and roof landmarks rather than misleading horizontal pixel-to-metre lines.
for points,col,label in [([(551,381),(881,288),(881,403),(551,499),(551,381)],'#f958a9','SIGN: adopted 9.1 x 2.3 m'),([(309,129),(537,52),(653,116),(429,189),(309,129)],'#35dce6','ROOF: projected proportions')]:
 dr.line(points,fill=col,width=3)
 for x,y in points[:-1]:dr.ellipse((x-4,y-4,x+4,y+4),fill=col)
 dr.text((points[0][0]+8,points[0][1]+8),label,font=font,fill=col,stroke_width=2,stroke_fill='#25303b')
dr.line([(535,651),(535,353)],fill='#fff05c',width=3)
for y in [651,353]:dr.line([(524,y),(546,y)],fill='#fff05c',width=3)
dr.text((273,589),'~298 px / adopted 5.1 m',font=font,fill='#fff05c',stroke_width=2,stroke_fill='#25303b')
dr.rectangle((14,12,1066,43),fill='#25303b');dr.text((22,18),'NORMALIZED 1080px | ORIGINAL 1200px | SINGLE-VIEW PROPORTION ESTIMATES',font=font,fill='white')
dr.rectangle((16,999,1064,1065),fill='#25303b');dr.text((24,1006),'Body adopted: 8.6 x 8.2 m | Floor pitch: 5.1 m | Slab: 0.2 m',font=font,fill='white');dr.text((24,1036),'No calibrated camera: hidden depths and all absolute metric sizes are not survey results.',font=font,fill='white')
im.save(W/'reference_measured.png')
# A single review surface: reference and final hero above, close and roof below.
canvas=Image.new('RGB',(2000,2220),'#202631');draw=ImageDraw.Draw(canvas);titlefont=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',30)
for pos,file,title in [((0,0),D/'reference.jpg','参考图'),((1000,0),W/'hero.png','B1109A · Blender 源'),((0,1100),W/'close.png','店面近景'),((1000,1100),W/'roof_close.png','天台近景')]:
 img=Image.open(file).convert('RGB');img.thumbnail((960,990));x,y=pos;canvas.paste(img,(x+(1000-img.width)//2,y+60+(990-img.height)//2));draw.text((x+24,y+15),title,font=titlefont,fill='#e4eaf2')
draw.text((24,2160),'49组件 · 92实例 · 390194三角面 · 源级通过 / Godot未接入 / 正式名字待定',font=titlefont,fill='#e4eaf2');canvas.save(W/'reference_comparison.jpg',quality=95)
print('MEASUREMENT_COORDINATES_NORMALIZED_AND_COMPARISON_READY')
