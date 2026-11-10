"""Author 98 individually named plants, each with independent small/medium/large geometry.
No seasons, runtime replacement, old source edits, or uniform-scale masquerading as growth.
"""
import bpy,bmesh,json,hashlib,math,os,sys
from pathlib import Path
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parents[3];OUT=R/'art_source/vegetation/libraries/v002';W=Path(os.environ.get('SEA_WORK_ROOT',str(R.parent/'sea-work')))/'botanical_growth/v002/vegetation'
P=json.loads((OUT/'component_plan.json').read_text(encoding='utf-8'));PALETTE=R/P['palette'];CELLS={c['name']:c for c in json.loads(PALETTE.with_suffix('.json').read_text(encoding='utf-8'))['cells']}
TAU=math.tau

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def collection(n,parent=None):
 c=bpy.data.collections.new(n);c.instance_offset=(0,0,0)
 if parent:parent.children.link(c)
 return c

def palette_material(role,rough):
 m=bpy.data.materials.new(role);m.use_nodes=True;n=m.node_tree.nodes;n.clear();bs=n.new('ShaderNodeBsdfPrincipled');bs.inputs['Roughness'].default_value=rough
 tex=n.new('ShaderNodeTexImage');tex.image=IMG;tex.interpolation='Closest';uv=n.new('ShaderNodeUVMap');uv.uv_map='PaletteUV';o=n.new('ShaderNodeOutputMaterial');l=m.node_tree.links;l.new(uv.outputs['UV'],tex.inputs['Vector']);l.new(tex.outputs['Color'],bs.inputs['Base Color']);l.new(bs.outputs[0],o.inputs[0]);return m

class PlantMesh:
 def __init__(self):self.v=[];self.f=[];self.colors=[];self.organs={};self.roles=[];self.vertex_kinds=[]
 def add(self,vs,fs,color,kind,role=0):
  start=len(self.v);self.v.extend([tuple(v) for v in vs]);self.vertex_kinds.extend([kind]*len(vs));self.f.extend([tuple(start+i for i in f) for f in fs]);self.colors.extend([color]*len(fs));self.roles.extend([role]*len(fs));self.organs[kind]=self.organs.get(kind,0)+1
 def tube(self,points,radius,color='leaf_dark',kind='stem',segments=6):
  vs=[];fs=[];pts=[Vector(p) for p in points]
  for i,p in enumerate(pts):
   tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized();side=tangent.cross(Vector((0,0,1)))
   if side.length<.01:side=Vector((1,0,0))
   side.normalize();other=tangent.cross(side).normalized();r=radius*(1-.32*i/max(len(pts)-1,1))
   for j in range(segments):vs.append(p+r*(math.cos(j*TAU/segments)*side+math.sin(j*TAU/segments)*other))
  fs.append(tuple(reversed(range(segments))))
  for i in range(len(pts)-1):
   for j in range(segments):a=i*segments+j;b=i*segments+(j+1)%segments;fs.append((a,b,b+segments,a+segments))
  fs.append(tuple((len(pts)-1)*segments+j for j in range(segments)));self.add(vs,fs,color,kind)
 def ellipsoid(self,center,scale,color,kind,segments=8,rings=4,role=0):
  # Rounded closed mesh without coincident pole rings.
  c=Vector(center);vs=[c+Vector((0,0,-scale[2]))];fs=[]
  for i in range(1,rings):
   phi=-math.pi/2+math.pi*i/rings
   for j in range(segments):
    a=j*TAU/segments;vs.append(c+Vector((scale[0]*math.cos(phi)*math.cos(a),scale[1]*math.cos(phi)*math.sin(a),scale[2]*math.sin(phi))))
  top=len(vs);vs.append(c+Vector((0,0,scale[2])))
  for j in range(segments):fs.append((0,1+(j+1)%segments,1+j))
  for i in range(rings-2):
   for j in range(segments):a=1+i*segments+j;b=1+i*segments+(j+1)%segments;fs.append((a,b,b+segments,a+segments))
  base=1+(rings-2)*segments
  for j in range(segments):fs.append((base+j,base+(j+1)%segments,top))
  self.add(vs,fs,color,kind,role)
 def leaf(self,base,tip,width,color='leaf',kind='leaf',shape='oval',curve=.12,thickness=.025,twist=0):
  b=Vector(base);t=Vector(tip);d=t-b;unit=d.normalized();side=unit.cross(Vector((0,0,1)))
  if side.length<.02:side=Vector((math.cos(twist),math.sin(twist),0))
  side.normalize();normal=side.cross(unit).normalized()
  if normal.z<0:normal=-normal
  steps=3 if kind=='frond_leaf' else 5;across=2 if kind=='frond_leaf' else 4;vs=[];fs=[]
  for layer in [-1,1]:
   for i in range(steps+1):
    u=i/steps
    profile=max(.075,math.sin(math.pi*u)**(.65 if shape in ['round','heart','succulent','cabbage'] else 1.05))
    if shape=='heart':profile*=1+.25*math.sin(2*math.pi*u)
    for j in range(across+1):
     q=2*j/across-1;rib=(1-q*q)*math.sin(math.pi*u);bend=curve*math.sin(math.pi*u)+.035*math.sin(TAU*u+twist)*q
     ripple=.04*math.sin(u*TAU*2+q*3)*abs(q) if shape=='cabbage' else 0
     p=b+d*u+side*(q*width*.5*profile*(1+ripple))+normal*(bend+rib*width*.12+layer*thickness*.5*profile)
     vs.append(p)
  stride=across+1;half=(steps+1)*stride
  for i in range(steps):
   for j in range(across):
    a=i*stride+j;fs.append((a,a+1,a+stride+1,a+stride));a+=half;fs.append((a,a+stride,a+stride+1,a+1))
  for i in range(steps):
   a=i*stride;b2=(i+1)*stride;fs.append((a,b2,b2+half,a+half));a=i*stride+across;b2=(i+1)*stride+across;fs.append((a,a+half,b2+half,b2))
  for j in range(across):fs.append((j,j+half,j+1+half,j+1));a=steps*stride+j;fs.append((a,a+1,a+1+half,a+half))
  self.add(vs,fs,color,kind)
 def lily(self,rad,h,offset,idx):
  # A filled, thickness-bearing notched disc, not a solid circle painted with a gap.
  sides=22;angles=[.24+(TAU-.48)*i/sides for i in range(sides+1)];vs=[Vector(offset)+Vector((0,0,h))]
  for a in angles:vs.append(Vector(offset)+Vector((math.cos(a)*rad,math.sin(a)*rad,h+.025*rad*math.sin(a*3))))
  topn=len(vs);vs.extend([p+Vector((0,0,-.018)) for p in vs]);fs=[]
  for j in range(1,len(angles)):fs.append((0,j,j+1));fs.append((topn,topn+j+1,topn+j))
  edge=[0]+list(range(1,len(angles)+1))
  for i,a in enumerate(edge):b=edge[(i+1)%len(edge)];fs.append((a,b,b+topn,a+topn))
  self.add(vs,fs,'leaf' if idx%2 else 'jade','leaf')

def plant_geometry(p,index):
 b=PlantMesh();v=p['variants'][index];h=v['height_target'];w=v['spread_target'];n=v['organ_budget'];f=p['family'];t=p['traits'];rot=t['azimuth'];q=(p['seed']%997)/996;greens=[x for x in t['green_cycle'] if x!='leaf_light'];shape=t['leaf_shape'];stage=index
 if f=='broadleaf':
  if shape=='citrus':
   b.tube([(0,0,0),(.025*w,0,h*.48),(0,0,h*.88)],max(.012,.023*w),'bark','trunk',7)
   branches=[(i*TAU/(2+stage)+rot,.32+.16*i) for i in range(2+stage)]
   for a,z in branches:
    end=(math.cos(a)*w*.32,math.sin(a)*w*.32,h*min(.9,z+.28));b.tube([(0,0,h*z),end],.012*w,'bark','branch')
   for j in range(n):
    a=j*2.399963+rot;z=h*(.4+.5*(j%4)/3);base=(0,0,z);tip=(math.cos(a)*w*.46,math.sin(a)*w*.46,z+.12*h);b.leaf(base,tip,w*.2,greens[j%len(greens)],shape='oval',curve=.08*h)
   for j in range([0,1,3][stage]):
    a=rot+j*2.5;fruit=Vector((math.cos(a)*w*.28,math.sin(a)*w*.28,h*.55));b.tube([(0,0,h*.68),fruit+Vector((0,0,.06*w))],max(.004,.008*w),'bark','fruit_stem',5);b.ellipsoid(fruit,(.07*w,)*3,'gold','fruit',10,5,1)
  else:
   core=h*(.34 if shape!='succulent' else .16)
   b.tube([(0,0,0),(0,0,core)],max(.01,w*.018),'leaf_dark')
   for j in range(n):
    a=j*2.399963+rot;layer=j%3;z=core*(.25+.65*layer/2);r=w*(.27+.18*(1-layer/3));base=(0,0,z);tip=(math.cos(a)*r,math.sin(a)*r,h*(.55+.42*layer/2))
    if shape in ['succulent','cabbage']:tip=(math.cos(a)*r,math.sin(a)*r,h*(.45+.52*layer/2))
    width=w*([.32,.30,.28][stage] if shape not in ['lance'] else .15)
    b.leaf(base,tip,width,greens[(j+stage)%len(greens)],shape=shape,curve=h*(.08 if shape=='succulent' else .12),thickness=max(.008,width*(.23 if shape=='succulent' else .06)),twist=rot)
 elif f=='flower':
  # small foliage only; medium one bud; large one/two/three open heads depending on original identity.
  leafn=[3,6,10][stage]
  for j in range(leafn):
   a=j*2.39996+rot;z=h*.10*(j%2);b.leaf((0,0,z),(math.cos(a)*w*.41,math.sin(a)*w*.41,h*(.18+.15*(j%3))),w*.21,greens[j%len(greens)],curve=.04*h)
  heads=[0,1,2 if 'CLUSTER' in p['asset_id'] or 'FLOWERS' in p['asset_id'] else 1][stage]
  if not heads:b.tube([(0,0,0),(0,0,h*.74)],max(.009,w*.015))
  for j in range(heads):
   a=rot+j*2.7;x=math.cos(a)*w*.18*(j>0);y=math.sin(a)*w*.18*(j>0);top=Vector((x,y,h*(.82 if j else .92)))
   b.tube([(0,0,0),(x*.4,y*.4,h*.5),top],max(.009,w*.014),'leaf_dark')
   if stage==1:b.ellipsoid(top,(w*.095,w*.095,h*.085),t['petal_color'],'bud',8,4)
   else:
    radius=w*(.22 if heads>1 else .27)
    for k in range(t['petals']):
     a=k*TAU/t['petals']+rot;outer=top+Vector((math.cos(a)*radius,math.sin(a)*radius,.025*h));inner=top+Vector((math.cos(a)*radius*.12,math.sin(a)*radius*.12,0));b.leaf(inner,outer,radius*.70,t['petal_color'],'petal','round',curve=.035*h,thickness=.012*w)
    b.ellipsoid(top+Vector((0,0,.02*h)),(radius*.22,radius*.22,radius*.12),'gold','flower_center',8,4)
 elif f=='palm':
  trunk=h*(.32 if stage==0 else (.48 if stage==1 else .62));b.tube([(0,0,0),(w*.025,0,trunk*.5),(0,0,trunk)],max(.018,w*.04),'bark','trunk',8)
  for j in range(n):
   a=j*TAU/n+rot;center=Vector((0,0,trunk));length=w*.49;end=Vector((math.cos(a)*length,math.sin(a)*length,h*(.68+.15*math.sin(a))));mid=center.lerp(end,.58);mid.z=h
   b.tube([center,mid,end],max(.007,w*.01),'leaf_dark','frond_stem',5)
   for k in range(4 if stage==0 else (6 if stage==1 else 7)):
    u=.08+k*.14;base=center.lerp(mid,u/.58) if u<=.58 else mid.lerp(end,(u-.58)/.42);side=Vector((-math.sin(a),math.cos(a),0));forward=Vector((math.cos(a),math.sin(a),-.12))
    for sign in [-1,1]:
     tip=base+side*(sign*w*.23*(1-.70*u))+forward*w*.16*(1-u);b.leaf(base,tip,w*.085*(1-.35*u),greens[(j+k)%len(greens)],'frond_leaf','lance',curve=.035*h,thickness=.009*w)
 elif f=='vine':
  strands=1 if stage==0 else 2 if stage==1 else 3
  for s in range(strands):
   points=[]
   for k in range(7):u=k/6;points.append((math.sin(u*4+rot+s)*w*.12+s*w*.09,math.cos(u*3+s)*w*.06,-h*u*(1-.15*s)))
   b.tube(points,max(.008,w*.018),'leaf_dark','vine_stem')
  for j in range(n):
   u=(j+1)/(n+1);s=j%strands;base=Vector((math.sin(u*4+rot+s)*w*.12+s*w*.09,math.cos(u*3+s)*w*.06,-h*u*(1-.15*s)));a=rot+(j%2)*math.pi+.45*s;tip=base+Vector((math.cos(a)*w*.30,math.sin(a)*w*.30,-h*.035));b.leaf(base,tip,w*.26,greens[j%len(greens)],shape='heart',curve=.03*w,thickness=.018*w)
 elif f in ['grass','kelp']:
  for j in range(n):
   a=j*2.399963+rot;rad=w*.13*math.sqrt((j+1)/n);base=(math.cos(a)*rad,math.sin(a)*rad,0);tip=(math.cos(a)*w*(.25+.19*(j%3)/2),math.sin(a)*w*(.25+.19*(j%3)/2),h*(.72+.28*((j*7)%n)/max(n-1,1)))
   b.leaf(base,tip,w*(.14 if f=='kelp' else .07),greens[j%len(greens)],'blade','lance',curve=h*.10,thickness=max(.006,w*.012),twist=a)
 elif f=='reed':
  for j in range(n):
   a=j*2.39996+rot;rad=w*.26*math.sqrt(j/max(n-1,1));x=math.cos(a)*rad;y=math.sin(a)*rad;hi=h*(.72+.28*(j%3)/2);b.tube([(x,y,0),(x+.04*w,y,hi)],max(.009,w*.014),'leaf','reed_stem')
   for k in range(1+stage):
    z=hi*(.25+.19*k);a2=a+k*2.4;b.leaf((x,y,z),(x+math.cos(a2)*w*.34,y+math.sin(a2)*w*.34,z+hi*.12),w*.07,greens[(j+k)%len(greens)],'leaf','lance',curve=.025*h)
   if stage>0:b.ellipsoid((x+.04*w,y,hi),(.025*w,.025*w,hi*.09),'ochre','reed_head',8,4)
 elif f=='moss':
  for j in range(n):
   a=j*2.39996+rot;r=w*.36*math.sqrt(j/max(n-1,1));size=w*(.11 if stage==0 else .10);z=h*.23;center=(math.cos(a)*r,math.sin(a)*r,z);b.ellipsoid(center,(size,size*.9,h*.23),greens[j%len(greens)],'moss_cushion',7,3)
   if j%2==0:b.leaf(center,(center[0]+math.cos(a)*size*.9,center[1]+math.sin(a)*size*.9,h*.80),size*.65,'moss_light','moss_leaf',curve=h*.06,thickness=.008)
 elif f=='water_leaf':
  for j in range(n):
   a=rot+j*2.39996;r=w*.18*(j>0);b.lily(w*(.44-.06*j),h*(.45+.15*j),(math.cos(a)*r,math.sin(a)*r,0),j)
   base=(math.cos(a)*r,math.sin(a)*r,0);b.tube([base,(base[0],base[1],h*.45)],.009,'leaf_dark','petiole')
 elif f=='tomato':
  b.tube([(0,0,0),(0,0,h*.85)],max(.012,w*.022),'leaf_dark')
  for j in range(n):
   a=j*2.39996+rot;z=h*(.18+.62*j/max(n-1,1));tip=(math.cos(a)*w*.4,math.sin(a)*w*.4,z+h*.08);b.tube([(0,0,z),tip],.007*w,'leaf_dark','branch');b.leaf((math.cos(a)*w*.12,math.sin(a)*w*.12,z),tip,w*.18,greens[j%len(greens)],curve=.04*h)
  for j in range([0,1,4][stage]):
   a=rot+j*2.4;fruit=Vector((math.cos(a)*w*.22,math.sin(a)*w*.22,h*(.38+.13*(j%3))));b.tube([(0,0,fruit.z+.12*h),fruit+Vector((0,0,.075*w))],max(.004,.008*w),'leaf_dark','fruit_stem',5);b.ellipsoid(fruit,(.085*w,)*3,'red' if stage==2 else 'leaf_mid','fruit',10,5,1)
 else:raise ValueError(f)
 # Anchor and dimensions are an explicit authoring choice, not display scaling.
 pts=[Vector(v) for v in b.v];lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)));hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)));span=hi-lo
 target_h=h;target_w=w;factor_z=target_h/max(span.z,1e-6);factor_xy=target_w/max(span.x,span.y,1e-6)
 cx=(lo.x+hi.x)/2;cy=(lo.y+hi.y)/2;anchor=hi.z if f=='vine' else lo.z
 b.v=[((v[0]-cx)*factor_xy,(v[1]-cy)*factor_xy,(v[2]-anchor)*factor_z) for v in b.v]
 return b

def build_component(p,index,parent):
 b=plant_geometry(p,index);v=p['variants'][index];c=collection(v['collection'],parent);c['asset_id']=p['asset_id'];c['growth_key']=v['growth_key'];c['display_name']=p['display_name'];c['season_variants']=False;c['anchor_policy']=p['anchor'];c['reference_source']=p['source'];c['source_migration']=False
 me=bpy.data.meshes.new(v['collection']+'__Mesh');me.from_pydata(b.v,[],b.f);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
 me.materials.append(MATTE);me.materials.append(GLOSS)
 uv=me.uv_layers.new(name='PaletteUV');uv.active_render=True
 for poly,color,role in zip(me.polygons,b.colors,b.roles):
  poly.use_smooth=True;poly.material_index=role;cell=CELLS[color];cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
  for j,li in enumerate(poly.loop_indices):a=j*TAU/len(poly.loop_indices);uv.data[li].uv=(cx+.022*math.cos(a),cy+.022*math.sin(a))
 wind=me.color_attributes.new(name='WindData',type='FLOAT_COLOR',domain='POINT')
 for vert,d in zip(me.vertices,wind.data):
  u=abs(vert.co.z)/v['height_target'];rigid=b.vertex_kinds[vert.index] in ['trunk','fruit','moss_cushion','flower_center'];d.color=(0 if rigid else max(0,min(1,u))*.8,0 if rigid else max(0,min(1,u))*.3,(p['seed']%997)/997,1)
 me.color_attributes.active_color=wind
 ob=bpy.data.objects.new(v['collection']+'__植物',me);c.objects.link(ob);ob['asset_id']=p['asset_id'];ob['growth_key']=v['growth_key'];ob['organ_counts']=json.dumps(b.organs)
 c.asset_mark();c.asset_data.description=p['display_name']+' · '+v['label']+'型；无季节变化；纯模型未接入'
 for tag in ['sea','植物',v['growth_key'],p['family']]:c.asset_data.tags.new(tag)
 me.calc_loop_triangles();bounds=[[min(v.co[i] for v in me.vertices) for i in range(3)],[max(v.co[i] for v in me.vertices) for i in range(3)]]
 assert len(me.loop_triangles)<=v['triangle_budget'],(p['asset_id'],len(me.loop_triangles),v['triangle_budget'])
 fingerprint=hashlib.sha256(json.dumps({'v':[[round(x,6) for x in v.co] for v in me.vertices],'f':[list(p.vertices) for p in me.polygons]},sort_keys=True).encode()).hexdigest()
 row={'asset_id':p['asset_id'],'display_name':p['display_name'],'original_name':p['original_name'],'family':p['family'],'growth_key':v['growth_key'],'growth_label':v['label'],'collection':c.name,'object':ob.name,'organ_counts':b.organs,'bounds':bounds,'vertices':len(me.vertices),'polygons':len(me.polygons),'triangles':len(me.loop_triangles),'triangle_budget':v['triangle_budget'],'geometry_fingerprint':fingerprint,'anchor':p['anchor'],'reference_source':p['source'],'legacy_binary_remodeled':p['legacy_binary'],'season_variants':False,'subsuite':p['subsuite']}
 return c,row

def label(text,loc,size,parent):
 cu=bpy.data.curves.new('中文标签','FONT');cu.body=text;cu.size=size;cu.align_x='CENTER';cu.font=FONT
 o=bpy.data.objects.new('标签_'+text,cu);parent.objects.link(o);o.location=loc;cu.materials.append(TEXTMAT)
 return o

def main():
 global IMG,MATTE,GLOSS,FONT,TEXTMAT
 path=R/P['path']
 if path.exists():
  old=json.loads((OUT/'library_manifest.json').read_text(encoding='utf-8'));assert sha(path)==old['sha256'],'User-edited candidate; refuse overwrite';assert '--rebuild-owned' in sys.argv,'Explicit candidate rebuild required'
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
 IMG=bpy.data.images.load(str(PALETTE));IMG.filepath='//'+os.path.relpath(PALETTE,path.parent).replace('\\','/');MATTE=palette_material('SEA_Matte',.82);GLOSS=palette_material('SEA_Gloss',.4)
 FONT=bpy.data.fonts.load('C:/Windows/Fonts/msyh.ttc');TEXTMAT=bpy.data.materials.new('展示标签');TEXTMAT.use_nodes=True;TEXTMAT.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.015,.055,.035,1)
 scene=bpy.context.scene;scene.name='01_小中大对照';masterscene=bpy.data.scenes.new('02_植物母版');master=collection('植物母版_按中文名与AssetID',masterscene.collection);gallery=collection('小中大_展示实例',scene.collection);support=collection('展示支持_不导出',scene.collection)
 groups={};members=[];species=[]
 ordered=sorted(P['plants'],key=lambda x:(x['family'],x['display_name']))
 for idx,p in enumerate(ordered):
  group=groups.get(p['subsuite'])
  if group is None:group=collection(p['subsuite'],master);groups[p['subsuite']]=group
  parent=collection(p['display_name']+'__'+p['asset_id'],group);parent['asset_id']=p['asset_id'];parent['display_name']=p['display_name']
  largest=p['variants'][2];common_scale=min(1.0,1.7/largest['height_target'],1.7/largest['spread_target'])
  block=idx%7;row=idx//7;gx=block*6.7;gy=-row*3.9
  for k,v in enumerate(p['variants']):
   c,m=build_component(p,k,parent);ins=bpy.data.objects.new('展示_'+c.name,None);gallery.objects.link(ins);ins.instance_type='COLLECTION';ins.instance_collection=c;ins.scale=(common_scale,)*3;ins.location=(gx+k*1.95,gy,largest['height_target']*common_scale if p['anchor']=='top_center_attachment' else 0)
   m['gallery_instance']=ins.name;m['display_scale']=common_scale;m['gallery_position']=list(ins.location);members.append(m)
   label(v['label'],(gx+k*1.95,gy-.94,.015),.15,support)
  label(p['display_name'],(gx+1.95,gy-1.35,.015),.20,support);label(p['asset_id'].replace('SEA-SCENE-','').replace('SEA-PLANT-','')[:38],(gx+1.95,gy-1.65,.015),.082,support)
  species.append({'asset_id':p['asset_id'],'display_name':p['display_name'],'family':p['family'],'gallery_center':[gx+1.95,gy,.55],'display_scale':common_scale})
 width=6*6.7+5.4;depth=(math.ceil(len(ordered)/7)-1)*3.9
 # Ground and lighting exist only in the display scene.
 me=bpy.data.meshes.new('展示地面');me.from_pydata([(-2,-depth-3,-.045),(width+2,-depth-3,-.045),(width+2,3,-.045),(-2,3,-.045)],[],[(0,1,2,3)]);o=bpy.data.objects.new('展示地面',me);support.objects.link(o)
 bg=bpy.data.materials.new('展示奶油底');bg.use_nodes=True;bg.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.72,.78,.69,1);bg.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.9;me.materials.append(bg)
 scene.world=bpy.data.worlds.new('柔和植物环境');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.76,.69,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
 target=Vector((width/2,-depth/2,.4))
 for i,(pos,power,size) in enumerate([((width/2,-depth/2,28),6500,32),((-8,5,20),2800,22)]):
  ld=bpy.data.lights.new('展示柔光'+str(i),'AREA');ld.energy=power;ld.size=size;o=bpy.data.objects.new(ld.name,ld);support.objects.link(o);o.location=pos;o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler()
 cd=bpy.data.cameras.new('对照相机');cd.type='ORTHO';cam=bpy.data.objects.new('对照相机',cd);support.objects.link(cam);scene.camera=cam;cam.location=target+Vector((0,-32,70));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cd.ortho_scale=max(width+7,depth+7)
 scene.render.engine='CYCLES';scene.cycles.samples=20;scene.render.resolution_x=2800;scene.render.resolution_y=2800;scene.render.resolution_percentage=100;scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
 scene['review_target']=list(target);scene['review_width']=width;scene['review_depth']=depth;scene['library_id']=P['library_id'];scene['season_variants']=False
 bpy.ops.wm.save_as_mainfile(filepath=str(path),check_existing=False)
 manifest={'schema_version':2,'library_id':P['library_id'],'path':P['path'],'sha256':sha(path),'season_variants':False,'growth_axis':['small','medium','large'],'plant_count':98,'member_count':294,'plants':species,'members':members,'triangles':sum(x['triangles'] for x in members),'polygons':sum(x['polygons'] for x in members),'source_plan':'art_source/vegetation/libraries/v002/component_plan.json','palette':P['palette'],'palette_sha256':sha(PALETTE),'primary_source_migration':False,'runtime_integration':False,'status':'source_built_verification_pending','naming':'unique Chinese management names; not botanical species identification','generation':'Independent species traits and organ topology; no scale-only growth','protected_inputs':P['protected_inputs']}
 dump(OUT/'library_manifest.json',manifest);print('VEGETATION_GROWTH_BUILT '+json.dumps({'plants':98,'models':294,'triangles':manifest['triangles'],'path':str(path)},ensure_ascii=False))
if __name__=='__main__':main()
