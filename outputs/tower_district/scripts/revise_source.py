p='outputs/tower_district/scripts/build_scene.py'
s=open(p).read()
s=s.replace("s=bpy.data.scenes.new('TD_TOWER_DISTRICT_v001')", "s=bpy.data.scenes.new('TD_TOWER_DISTRICT_v002')")
s=s.replace("'tower_district_v001.blend'", "'tower_district_v002.blend'")
s=s.replace("source/tower_district_v001.blend", "source/tower_district_v002.blend")
s=s.replace("cam.location=(0,-44,6.1);target=Vector((0,6,6.5))", "cam.location=(0,-44,4.4);target=Vector((0,6,5.4))")
s=s.replace("cd.dof.aperture_fstop=5.6", "cd.dof.aperture_fstop=3.2")
s=s.replace("for x in [-13.15,13.15]:", "for x in [-9.2,12.8]:")
s=s.replace("for x in [-11.5,11.5]:", "for x in [-7.6,11.2]:")
s=s.replace("volume('Global_cold_haze',(0,22,12),(110,110,32),.008", "volume('Global_cold_haze',(0,22,12),(110,110,32),.0035")
s=s.replace("volume('Left_exhaust',(-11.6,2,3.6),(4.8,5,6.8),.13", "volume('Left_exhaust',(-9.4,2,3.6),(4.8,5,6.8),.17")
s=s.replace("volume('Right_exhaust',(13.3,2.6,3.9),(5.5,5,7.2),.14", "volume('Right_exhaust',(13.3,2.6,3.9),(5.5,5,7.2),.17")
s=s.replace("volume('Red_scan_dust',(3.4,.8,5.2),(4,5,10),.035", "volume('Red_scan_dust',(3.4,.8,5.2),(4,5,10),.065")
s=s.replace(".32\ns.world", ".32\ns.world")
s=s.replace("default_value=0.32", "default_value=0.16")
s=s.replace("9000,24,(0,5,0)", "5500,24,(0,5,0)")
s=s.replace("3500,24,(0,4,6)", "1800,24,(0,4,6)")
s=s.replace("2500,.5,(2.8,.1,0)", "7500,.5,(2.8,.1,0)")
s=s.replace("angle=.5)", "angle=.65)")
s=s.replace("scan.rotation_euler=(0,.06,0)", "scan.rotation_euler=(0,-.06,0)")
s=s.replace("drone.rotation_euler=(.12,-.10,-.14)", "drone.rotation_euler=(.67,-.10,-.16)")
s=s.replace("'11.3+0.13*sin", "'10.9+0.13*sin")
s=s.replace("scan.parent=drone;scan.location=(0,-.65,-.5);scan.rotation_euler=(0,-.06,0)", "scan.parent=drone;scan.location=(0,-.65,-.5);scan.rotation_euler=(-.67,-.06,0)")
s=s.replace("'neonorange':'ffb86c'", "'neonorange':'ff9d44'")
s=s.replace("s.view_settings.look='AgX - Medium High Contrast'", "s.view_settings.look='AgX - Medium High Contrast'")
s=s.replace("s.view_settings.view_transform='AgX'", "s.view_settings.view_transform='AgX';s.view_settings.exposure=-.25")
s=s.replace("b.box((18.6,7,6.7),(10,10,13.4),'dark',1)", "b.box((18.6,7,4.55),(10,10,9.1),'dark',1);b.box((23.5,8,12),(6,12,24),'navy',1)")
s=s.replace("x=side*11.8;y=2.1", "x=(-9.15 if side<0 else 12.8);y=2.1")
# Move only the ATM facade panel to its reference screen position.
a=s.index("b=Batch('ATM_and_posters'");b=s.index("b=Batch('Information_terminal'",a)
seg=s[a:b].replace('-20.1','-16.2').replace('-20.32','-16.42').replace('-21,','-17.1,')
s=s[:a]+seg+s[b:]
# Add the recessed left side annex extending toward the underpass.
a=s.index("# LIQUOR vertical sign")
s=s[:a]+'''b=Batch('Left_recessed_shop_annex',C['06_左侧店面'])
b.box((-11.3,6,3.3),(3.4,5,6.6),'dark',1)
for x in [-12.65,-11.85,-11.05,-10.25]:
 rect(b,x,3.38,3.05,.72,5.7,.08,'window',2);frame(b,x,3.29,3.05,.72,5.7,.06,.08,'steel')
 for z in [.6,4.9,5.6]:rect(b,x,3.23,z,.68,.05,.03,'steel2',0)
rect(b,-11.5,3.19,4.65,.82,.52,.1,'rust',0)
for dx in [-.17,.17]:
 for dz in [-.1,.1]:rect(b,-11.5+dx,3.12,4.65+dz,.07,.08,.03,'redmid',3)
b.done()
''' +s[a:]
# Fine stepped roof; no large stair treads, no rooftop stray grille.
s=s.replace("for k in range(5):\n  b.box((0,-.12,1.28+k*.13),(2.15-k*.075,2.65-k*.21,.13),body if k==4 else 'glass',2)", "for k in range(18):\n  b.box((0,-.12,1.28+k*.035),(2.15-k*.017,2.65-k*.061,.036),'glass',2)")
s=s.replace("for k in range(7):b.box((0,-1.36+k*.085,1.30+k*.13),(1.85-k*.04,.025,.025),'steel',0)", "for k in range(5):b.box((0,-1.42+k*.13,1.30+k*.14),(1.80-k*.025,.012,.009),'steel',0)")
s=s.replace("gl.inputs['Strength'].default_value=.35;gl.inputs['Size'].default_value=.25", "gl.inputs['Strength'].default_value=.65;gl.inputs['Size'].default_value=.32")
s=s.replace("previews/01_composition.png", "previews/02_composition.png")
# More authored mechanical texture without changing the reference silhouette.
a=s.index('# Underpass receding walls')
s=s[:a]+'''b=Batch('Facade_micro_paneling',C['04_机电管线'])
for i in range(110):
 x=random.uniform(-17,18);z=random.uniform(7.0,8.65)
 if random.random()<.45:
  for j in range(5):rect(b,x,3.66,z+j*.045,.21,.012,.025,'black',1)
 else:
  rect(b,x,3.62,z,.11,.085,.02,'gold',0)
  rect(b,x,3.60,z,.04,.035,.02,'black',1)
for i in range(300):
 x=random.uniform(-20,20);z=random.uniform(8.4,9.05)
 rect(b,x,4.19,z,random.uniform(.01,.08),random.uniform(.01,.2),.012,random.choice(['rust','steel','dirty']),1)
b.done()
''' +s[a:]
open(p,'w').write(s)
