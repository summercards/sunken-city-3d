"""Derive v004 from saved v003; all edits are in the new source only."""
import bpy,bmesh,json,math,hashlib,os
from pathlib import Path
from mathutils import Matrix,Vector,Euler
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v004';OLD=D.parent/'v003';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'solar_cabin_revision_v004';P=json.loads((D/'component_plan.json').read_text());assert P['status']=='frozen_before_geometry'
PAL=R/P['palette'];cells={x['name']:x for x in json.loads(PAL.with_suffix('.json').read_text())['cells']}
oldcat=json.loads((OLD/'catalog.json').read_text())['components'];cat={x['key']:x.copy() for x in oldcat};spec={x['key']:x for x in P['components']}
bpy.ops.wm.open_mainfile(filepath=str(OLD/'sunny_bloom_retreat.blend'));bpy.context.preferences.filepaths.save_version=0;S=bpy.context.scene;S.name='太阳能木屋-海上区域-v004';LIB=next(s for s in bpy.data.scenes if s!=S)
M={key:bpy.data.materials['SEA_'+key] for key in ['Matte','Metal','Gloss','Emission']}
def paint(me,color,faces=None):
 uv=me.uv_layers.get('PaletteUV') or me.uv_layers.new(name='PaletteUV')
 for layer in list(me.uv_layers):
  if layer.name!='PaletteUV':me.uv_layers.remove(layer)
 me.uv_layers.active_index=0;uv=me.uv_layers['PaletteUV'];uv.active_render=True;c=cells[color];u=(c['column']+.5)/8;v=1-(c['row']+.5)/8
 for f in me.polygons if faces is None else faces:
  for k,l in enumerate(f.loop_indices):
   a=2*math.pi*k/len(f.loop_indices);uv.data[l].uv=(u+.025*math.cos(a),v+.025*math.sin(a))
def recolor(key,color,wood_only=False):
 for o in bpy.data.collections[cat[key]['collection']].objects:
  if o.type!='MESH':continue
  fs=list(o.data.polygons);uv=o.data.uv_layers['PaletteUV']
  if wood_only:fs=[f for f in fs if int(uv.data[f.loop_indices[0]].uv.y*8)==6]
  paint(o.data,color,fs)
def select(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o

def box_mesh(key,dimensions,color,bevel=.045):
 col=bpy.data.collections.get(cat[key]['collection']) if key in cat else None
 if col:
  for o in list(col.objects):bpy.data.objects.remove(o,do_unlink=True)
 else:
  col=bpy.data.collections.new(spec[key]['asset_id']);LIB.collection.children.link(col)
 S.collection.children.link(col)
 bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,dimensions[2]/2));o=bpy.context.object;o.scale=dimensions
 for c in list(o.users_collection):c.objects.unlink(o)
 col.objects.link(o);select(o);bpy.ops.object.transform_apply(location=True,rotation=False,scale=True)
 b=o.modifiers.new('实体倒角','BEVEL');b.width=bevel;b.segments=3;bpy.ops.object.modifier_apply(modifier=b.name)
 for f in o.data.polygons:f.use_smooth=True
 n=o.modifiers.new('加权法线','WEIGHTED_NORMAL');n.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=n.name)
 o.name=key+'_mesh';o.data.materials.clear();o.data.materials.append(M['Matte']);paint(o.data,color)
 root=bpy.data.objects.new('ROOT_'+key,None);col.objects.link(root);o.parent=root;S.collection.children.unlink(col)
 cat[key]=dict(spec[key],collection=col.name,root=root.name,source_anchor=[0,0,0]);return col
# Shared palette remains unchanged. The new wine board uses berry swatch only;
# its bounded HSV treatment is duplicated by the Godot shader.
for mat in M.values():
 n=mat.node_tree.nodes;lk=mat.node_tree.links;uv=next(x for x in n if x.type=='UVMAP');sat=next(x for x in n if x.type=='HUE_SAT');bs=next(x for x in n if x.type=='BSDF_PRINCIPLED')
 sep=n.new('ShaderNodeSeparateXYZ');lk.new(uv.outputs['UV'],sep.inputs[0]);tests=[]
 for axis,cell in [('X',5),('Y',2)]:
  mul=n.new('ShaderNodeMath');mul.operation='MULTIPLY';mul.inputs[1].default_value=8;lk.new(sep.outputs[axis],mul.inputs[0]);fl=n.new('ShaderNodeMath');fl.operation='FLOOR';lk.new(mul.outputs[0],fl.inputs[0]);eq=n.new('ShaderNodeMath');eq.operation='COMPARE';eq.inputs[1].default_value=cell;eq.inputs[2].default_value=.01;lk.new(fl.outputs[0],eq.inputs[0]);tests.append(eq)
 mask=n.new('ShaderNodeMath');mask.operation='MULTIPLY';lk.new(tests[0].outputs[0],mask.inputs[0]);lk.new(tests[1].outputs[0],mask.inputs[1]);wine=n.new('ShaderNodeHueSaturation');wine.inputs['Hue'].default_value=.567;wine.inputs['Saturation'].default_value=.95;wine.inputs['Value'].default_value=.75;lk.new(sat.outputs[0],wine.inputs['Color']);mix=n.new('ShaderNodeMixRGB');lk.new(mask.outputs[0],mix.inputs[0]);lk.new(sat.outputs[0],mix.inputs[1]);lk.new(wine.outputs[0],mix.inputs[2]);lk.new(mix.outputs[0],bs.inputs['Base Color'])
# Concrete rear roof and structural beams, plus deliberately gray top cap.
for key in ['canopy_post','canopy_beam','canopy_hook','chimney','roof_sofa','coffee_table']:recolor(key,'cloud',True)
recolor('cap','gray')
# Replace roof paving mesh with a single smooth thick concrete roof slab.
box_mesh('terrace',(5.20,3.73,.355),'cloud',.075)
box_mesh('platform_board',(7.5,.518,.22),'berry',.05)
box_mesh('concrete_slab',(7.5,6.2,.24),'cloud',.05)
box_mesh('dock_board',(2.48,.435,.24),'wood_light',.05)
# Widen the actual front wall opening and the matching window. Frames retain
# their original width, instead of scaling slender posts into thick blocks.
col=bpy.data.collections[cat['house']['collection']];S.collection.children.link(col);body=next(o for o in col.objects if o.type=='MESH')
bpy.ops.mesh.primitive_cube_add(size=1,location=(-1.33,-1.73,1.44));cut=bpy.context.object;cut.scale=(.94,.70,1.82);select(cut);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);select(body);mod=body.modifiers.new('加宽前窗实洞','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cut;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cut,do_unlink=True);body.data.materials.clear();body.data.materials.append(M['Matte']);paint(body.data,'white');S.collection.children.unlink(col)
col=bpy.data.collections[cat['narrow_window']['collection']]
# Stretch central pane span while translating the left/right frame profiles.
for o in col.objects:
 if o.type!='MESH':continue
 for v in o.data.vertices:
  x=v.co.x
  v.co.x=x+(.295 if x>.17 else -.295 if x<-.17 else x*(.94/.35-1))
# Rebuild scene instances from saved, explicit transforms, never regenerate source kit.
oldinstances=[o for o in S.objects if o.instance_type=='COLLECTION'];oldnames={v['asset_id']:v['key'] for v in oldcat};saved=[]
for o in oldinstances:saved.append((o.name,oldnames[o.instance_collection.name],o.matrix_world.copy()));bpy.data.objects.remove(o,do_unlink=True)
for c in list(S.collection.children):
 if not c.name.startswith('90 '):S.collection.children.unlink(c)
B=bpy.data.collections.new('太阳能木屋-海上区域');S.collection.children.link(B);F=bpy.data.collections.new('花朵与植物-独立');S.collection.children.link(F)
partnames={'rear_building':'01 后部方形建筑','solar_room':'02 前部倾斜太阳能房','front_platform':'03 前方可行动平台-酒红','bridge':'04 栈桥-暖木'};groups={}
for key,label in partnames.items():groups[key]=bpy.data.collections.new(label);B.children.link(groups[key])
flora_groups={}
for key in ['rear_building','solar_room','front_platform']:
 flora_groups[key]=bpy.data.collections.new(partnames[key]+'-花草');F.children.link(flora_groups[key])
instances=[];used=set();scale_pivot=Vector((-.72,.96,.68));enlarge=Matrix.Translation(scale_pivot)@Matrix.Diagonal((1.5,1.5,1.5,1))@Matrix.Translation(-scale_pivot)
solar_hinge=Vector((1.02,-.40,.68));forward=Matrix.Translation(solar_hinge)@Matrix.Diagonal((1.12,1.42,1,1))@Matrix.Translation(-solar_hinge)
def add(key,m,module,name=None):
 if key not in spec:return
 item=cat[key];o=bpy.data.objects.new(name or key,None);category=spec[key]['category'];(flora_groups[module] if category=='flora' else groups[module]).objects.link(o);o.instance_type='COLLECTION';o.instance_collection=bpy.data.collections[item['collection']];o.matrix_world=enlarge@m;o['module']=module;o['asset_id']=spec[key]['asset_id'];used.add(key)
 instances.append(dict(name=o.name,asset_id=spec[key]['asset_id'],position=list(o.location),rotation_euler_xyz=list(o.rotation_euler),scale=list(o.scale),category=category,module=module))
for name,key,m in saved:
 if key not in spec or key=='dock_board':continue
 p=m.translation
 # Clear the complete front apron, including decorative plants and planter walls.
 if p.y < -2.4 and p.z < 2.0 and key not in {'entry','porch_side','porch_return','lantern','sofa','table','stool','umbrella','cooler','vase','bottle','mat','bollard','pot','sprout'} and p.x<3.1:continue
 if key=='cooler' and p.x<0:continue
 if key=='bollard' and abs(p.x+1.7)<.05 and p.y<-4:continue
 if spec[key]['category']=='flora' and -1.15<p.x<.10 and -1.4<p.y<-.45 and 3.0<p.z<4.7:continue
 # Remove the orphan planter formerly holding the large roof palm.
 if key=='pot' and abs(p.x+2.83)<.02 and abs(p.y-.06)<.02:continue
 if spec[key]['category']=='flora' and p.x>1.9 and p.y>0 and 2.5<p.z<5.6:continue
 module='rear_building'
 lounge=key in {'sofa','table','stool','umbrella','cooler','vase','bottle','mat','bollard'} or (p.y<-2.4 and (key in {'pot','sprout'} or p.x>3.1))
 if lounge:
  module='bridge' if key=='bollard' and p.y<-6 else 'front_platform'
  if key=='sofa':m.translation.y-=1.03
  if key in {'table','vase','sprout'} and 2.5<p.x<2.9 and -3.5<p.y<-2.8:m.translation.y-=.95
  if key=='cooler':m.translation.y-=.65
  if key=='mat':m.translation.y-=1.05
  if key in {'pot','sprout'} and p.x<.3 and p.y<-2.4:m.translation.y-=.85
 if key in {'slope','solar','awning','entry','porch_side','porch_return'} or (key=='lantern' and p.y<-1.2) or (spec[key]['category']=='flora' and p.y<0 and p.z>2.5 and p.x>-.95):
  module='solar_room';m=forward@m
 add(key,m,module,name)
# Extend the rear rooftop to the right of the upper room. A solid floor,
# supporting rear/right walls and parapets replace the previously open gap.
add('concrete_slab',Matrix.Translation((2.52,.96,3.302))@Matrix.Diagonal((1.44/7.5,3.73/6.2,.3266/.24,1)),'rear_building','后侧加长水泥屋顶')
for pos,sc in [((3.18,.96,.68),(1,3.5/.3,.92)),((2.50,2.70,.68),(1.36/.3,.7,.92)),((2.50,-.78,.68),(1.36/.3,.7,.92))]:
 add('wall_pier',Matrix.Translation(pos)@Matrix.Diagonal((*sc,1)),'rear_building','后部扩建厚墙')
for y in [-.29,.86,2.01]:
 add('parapet',Matrix.Translation((3.18,y,3.6286))@Euler((0,0,math.pi/2)).to_matrix().to_4x4(),'rear_building','后侧女儿墙')
for x in [-.28,.87,2.02,2.96]:
 add('parapet',Matrix.Translation((x,2.73,3.6286))@Matrix.Diagonal((.64 if x>2.8 else 1,1,1,1)),'rear_building','后缘女儿墙')
# Ground is concrete behind the forecourt; the forward platform and bridge
# are distinct, full-width transversal boards without longitudinal patchwork.
add('concrete_slab',Matrix.Translation((-.15,.30,.44)),'rear_building','后区整块水泥地坪')
for row in range(6):add('platform_board',Matrix.Translation((-.15,-3.0666667-row*(3.2/6),.46)),'front_platform',f'平台横向长板_{row+1:02}')
for row in range(6):add('dock_board',Matrix.Translation((-1.435,-6.23-row*.46,.44)),'bridge',f'桥横向长板_{row+1:02}')
# Source roof and ground match the exact existing .68m datum. Full source is 1.5x.
entries=[]
for key in sorted(used):
 item=dict(cat[key]);item.update(spec[key]);col=bpy.data.collections[item['collection']];coords=[v.co for o in col.objects if o.type=='MESH' for v in o.data.vertices];lo=[min(v[i] for v in coords) for i in range(3)];hi=[max(v[i] for v in coords) for i in range(3)];item.update(bounds_min=lo,bounds_size=[hi[i]-lo[i] for i in range(3)],instance_count=sum(e['asset_id']==item['asset_id'] for e in instances),component_source=str((D/'components'/key/(key+'.blend')).relative_to(R)),material_roles=sorted({m.name for o in col.objects if o.type=='MESH' for m in o.data.materials}),collision_owner='Godot authored walk rectangles',triangle_budget=max(item.get('triangle_budget',500),10000))
 item['geometry_fingerprint']=hashlib.sha256(b''.join(repr(tuple(v.co)).encode() for o in col.objects if o.type=='MESH' for v in o.data.vertices)).hexdigest();entries.append(item)
# Remove unused masters, retain only one explicit mother collection per component.
for key,item in cat.items():
 if key in used:continue
 col=bpy.data.collections.get(item['collection'])
 if col:bpy.data.collections.remove(col)
P['components']=[spec[e['key']] for e in entries];(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n')
for im in bpy.data.images:
 if im.source=='FILE' and 'sea_cozy' in im.name:im.filepath=bpy.path.relpath(str(PAL),start=str(D))
S['revision']='v004';S['scale_over_previous']=1.5;S['front_axis']='-Y';S['component_sections']='后部方形建筑 / 前部太阳能房 / 前方平台 / 栈桥';S['feature_id']='SEA-ASSET'
# Expand the saved reference camera around the enlarged composition.
cam=S.camera;target=Vector((-.15,-2.7,4.3));cam.location=(-18,-28,19);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=22.5
for o in S.objects:
 if o.type=='LIGHT':o.location*=1.5;o.data.energy*=2.25;o.data.size*=1.5
S.render.resolution_x=1000;S.render.resolution_y=1000;S.cycles.samples=32
for screen in bpy.data.screens:
 for a in screen.areas:
  if a.type=='VIEW_3D':a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.shading.type='MATERIAL'
(D/'catalog.json').write_text(json.dumps({'components':entries},ensure_ascii=False,indent=2)+'\n');(D/'component_instances.json').write_text(json.dumps({'coordinate_contract':{'plane':'XY','up':'+Z','godot':'(x,y,z) -> (x,z,-y)'},'instances':instances},ensure_ascii=False,indent=2)+'\n')
bpy.ops.wm.save_as_mainfile(filepath=str(D/'sunny_bloom_retreat.blend'),compress=True)
print('BUILT',len(entries),len(instances),flush=True)
(W/'previews').mkdir(exist_ok=True);S.render.filepath=str(W/'previews/beauty.png');bpy.ops.render.render(write_still=True)
