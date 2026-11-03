from pathlib import Path
exec(Path('D:/projects/sea/tools/blender/ocean_rooftop_farm/r3_stage0.py').read_text(encoding='utf-8'))
# Main building 48x32, 10 dense floors, roof deck 50.6m.
W,D,F,ROOF=48.0,32.0,5.0,50.6
cube('建筑主体_灰色混凝土_48x32x50m',(0,0,25),(W,D,50),'lightgray',bev=.22)
for i in range(1,10):
 z=i*F; cube(f'楼板外露接缝_{i:02d}',(0,0,z),(48.6,32.5,.28),'cloud',bev=.06)
for floor in range(10):
 z=2.2+floor*F
 for x in [-19,-11.4,-3.8,3.8,11.4,19]:
  cube(f'正立面窗框_{floor:02d}_{x}',(x,-16.12,z),(5.1,.22,3.1),'cloud',bev=.08)
  cube(f'深蓝封闭窗_{floor:02d}_{x}',(x,-16.27,z),(4.35,.06,2.35),'deepblue','03_清漆反光_紫粉点缀',.025)
  if (floor+int(x))%3==0: cube(f'破损木板封窗_{floor:02d}_{x}',(x-.4,-16.33,z),(2.0,.08,.16),'wood_dark',bev=.015,rot=(0,.12,.18),t=c_fac)
 for x in [-15.2,-5.1,5.1,15.2]:
  cube(f'外凸阳台板_{floor:02d}_{x}',(x,-17.2,z-.35),(8.2,2.1,.32),'cloud',bev=.10)
  cube(f'阳台前栏板_{floor:02d}_{x}',(x,-18.05,z+.35),(7.8,.18,1.05),'gray',bev=.06,rot=(0,0,random.uniform(-.035,.035)))
  for px in [x-3.6,x,x+3.6]: rod(f'阳台锈栏杆_{floor:02d}_{px}',(px,-18.15,z-.1),(px+random.uniform(-.12,.12),-18.15,z+1.1),.055,'steel',t=c_fac)
for floor in range(10):
 z=2.2+floor*F
 for y in [-11,-3,5,13]:
  cube(f'东侧窗框_{floor:02d}_{y}',(24.12,y,z),(.22,5.1,3.0),'cloud',bev=.08)
  cube(f'东侧玻璃_{floor:02d}_{y}',(24.27,y,z),(.06,4.3,2.3),'deepblue','03_清漆反光_紫粉点缀',.02)
for x in [-20,-10,0,10,20]: cube(f'前立面结构柱_{x}',(x,-16.3,25),(1,.85,50),'gray',bev=.13)
for y in [-12,-4,4,12]: cube(f'侧立面结构柱_{y}',(24.1,y,25),(.9,1,50),'gray',bev=.13)
for i in range(56):
 x=random.uniform(-22.2,22.2); z=random.uniform(1,49)
 cube(f'混凝土剥落斑_{i:02d}',(x,-16.48,z),(random.uniform(.45,2.7),.06,random.uniform(.18,.75)),random.choice(['stone','cloud','lightgray']),bev=.03,t=c_fac)
for i in range(22):
 x=random.choice([-20,-10,0,10,20])+random.uniform(-1,1); z=random.uniform(2,48)
 tube(f'锈黄纵向水渍_{i:02d}',[(x,-16.53,z+1.6),(x+random.uniform(-.2,.2),-16.54,z),(x+random.uniform(-.45,.45),-16.54,z-.8)],.035,'ochre','02_细腻哑光_青绿大面',c_fac)
for i in range(22):
 x=random.uniform(-22,22); z=random.uniform(1,49)
 tube(f'立面交错裂纹_{i:02d}',[(x,-16.55,z),(x+.35,-16.56,z+.5),(x+.7,-16.56,z+.85)],.018,'slate','01_精工金属_紫色骨架',c_fac)
for x in [-23.9,-15.9,-7.9,.1,8.1,16.1,23.9]: cube(f'阴面厚青苔带_{x}',(x,-16.62,random.uniform(1,48)),(2.5,.05,.18),'forest',bev=.04,t=c_veg)
cube('楼顶混凝土平台',(0,0,50.55),(48,32,.5),'stone',bev=.12)
for i in range(22): sphere(f'楼顶野生草皮_{i:02d}',(random.uniform(-20,20),random.uniform(-12,12),50.88),(random.uniform(2,4),random.uniform(1.5,3),.18),random.choice(['moss','sage','forest']),t=c_veg)
for x in range(-22,23,4):
 cube(f'女儿墙前段_{x}',(x,-15.65,51.25),(3.8,1.1,1.1),'lightgray',bev=.09); cube(f'女儿墙后段_{x}',(x,15.65,51.25),(3.8,1.1,1.1),'lightgray',bev=.09)
 cube(f'女儿墙前青苔_{x}',(x,-15.08,51.7),(3.1,.06,.13),'forest',bev=.025,t=c_veg); cube(f'女儿墙后青苔_{x}',(x,15.08,51.7),(3.1,.06,.13),'forest',bev=.025,t=c_veg)
for y in range(-12,13,4):
 cube(f'女儿墙左段_{y}',(-23.65,y,51.25),(1.1,3.8,1.1),'gray',bev=.09); cube(f'女儿墙右段_{y}',(23.65,y,51.25),(1.1,3.8,1.1),'gray',bev=.09); cube(f'女儿墙右青苔_{y}',(23.08,y,51.7),(.06,3.1,.13),'forest',bev=.025,t=c_veg)
for y in [-15.95,15.95]:
 rod('屋顶边缘锈蚀顶栏',(-22,y,52.25),(22,y,52.25),.06,'steel',t=c_sup)
 for x in range(-22,23,4): rod('屋顶边缘立柱',(x,y,51.5),(x,y,52.25),.045,'steel',t=c_sup)
for x in [-23.95,23.95]:
 rod('侧边锈蚀顶栏',(x,-14,52.25),(x,14,52.25),.06,'steel',t=c_sup)
 for y in range(-14,15,4): rod('侧边立柱',(x,y,51.5),(x,y,52.25),.045,'steel',t=c_sup)
print(json.dumps({'stage':1,'objects':len(scene.objects),'meshes':sum(o.type=='MESH' for o in scene.objects)},ensure_ascii=False))
