# -*- coding: utf-8 -*-
"""Targeted Godot scene integration; no legacy whole-zone builder runs here."""
from pathlib import Path
import json,math,re,shutil,hashlib
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunny_bloom_retreat/v003/export/v001';W=R.parent/'sea-work/solar_cabin_integration';report=json.loads((D/'export_manifest.json').read_text());G=R/'godot'
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def js(p,v):write(p,json.dumps(v,ensure_ascii=False,indent=2)+'\n')
def point(x,y):return [5.128+1.15*x,2.15,.704-1.15*y]
def rect(x0,x1,y0,y1):
 a=point(x0,y1);b=point(x1,y0);return [a[0],a[2],b[0]-a[0],b[2]-a[2]]
pal=G/'assets/textures/shared/sea_cozy_8x8_512.png';pal.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/report['palette_source'],pal)
write(pal.with_suffix('.png.import'),'''[remap]
importer="texture"
type="CompressedTexture2D"
path="res://.godot/imported/sea_cozy_8x8_512.png-solar.ctex"

[deps]
source_file="res://assets/textures/shared/sea_cozy_8x8_512.png"
dest_files=["res://.godot/imported/sea_cozy_8x8_512.png-solar.ctex"]

[params]
compress/mode=0
mipmaps/generate=false
''')
shader='''shader_type spatial;
render_mode cull_disabled;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform float roughness_value = 0.62;
uniform float metallic_value = 0.0;
uniform float emission_value = 0.0;
uniform bool grid_role = false;
vec3 rgb2hsv(vec3 c) {
 vec4 K=vec4(0.0,-1.0/3.0,2.0/3.0,-1.0);
 vec4 p=mix(vec4(c.bg,K.wz),vec4(c.gb,K.xy),step(c.b,c.g));
 vec4 q=mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
 float d=q.x-min(q.w,q.y);float e=1e-10;
 return vec3(abs(q.z+(q.w-q.y)/(6.0*d+e)),d/(q.x+e),q.x);
}
vec3 hsv2rgb(vec3 c) {
 vec3 p=abs(fract(c.xxx+vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0);
 return c.z*mix(vec3(1.0),clamp(p-1.0,0.0,1.0),c.y);
}
void fragment() {
 vec3 base=texture(palette,UV).rgb;
 vec3 hsv=rgb2hsv(base);
 bool solar=ivec2(floor(UV*8.0))==ivec2(5,2);
 hsv.x=fract(hsv.x+(solar?0.02:0.0));
 hsv.y=clamp(hsv.y*(solar?0.94:1.12),0.0,1.0);
 hsv.z*=solar&&grid_role?1.30:1.0;
 ALBEDO=hsv2rgb(hsv);
 ROUGHNESS=roughness_value;METALLIC=metallic_value;SPECULAR=0.25;
 EMISSION=base*emission_value;
 __ALPHA__
}
'''
for glass in [False,True]:write(G/('shaders/sunny_palette_gloss.gdshader' if glass else 'shaders/sunny_palette.gdshader'),shader.replace('__ALPHA__','ALPHA=0.81;' if glass else ''))
for role,rough,metal,emit in [('Matte',.62,0,0),('Metal',.42,.18,0),('Gloss',.24,0,0),('Emission',.35,0,2)]:
 shader_path='sunny_palette_gloss.gdshader' if role=='Gloss' else 'sunny_palette.gdshader'
 write(G/f'assets/materials/solar_cabin/sunny_{role.lower()}.tres',f'''[gd_resource type="ShaderMaterial" load_steps=3 format=3]
[ext_resource type="Shader" path="res://shaders/{shader_path}" id="1"]
[ext_resource type="Texture2D" path="res://assets/textures/shared/sea_cozy_8x8_512.png" id="2"]
[resource]
resource_name = "SEA_{role}"
shader = ExtResource("1")
shader_parameter/palette = ExtResource("2")
shader_parameter/roughness_value = {rough}
shader_parameter/metallic_value = {metal}
shader_parameter/emission_value = {emit}
shader_parameter/grid_role = {'true' if role=='Metal' else 'false'}
''')
write(G/'src/world/sunny_bloom_visual.gd','''@tool
extends Node3D
## Component GLBs + Collection-style instances; root stays at identity.
const DATA = "res://assets/models/facilities/solar_cabin/instances.json"
const MATERIALS = {
 "Matte": preload("res://assets/materials/solar_cabin/sunny_matte.tres"),
 "Metal": preload("res://assets/materials/solar_cabin/sunny_metal.tres"),
 "Gloss": preload("res://assets/materials/solar_cabin/sunny_gloss.tres"),
 "Emission": preload("res://assets/materials/solar_cabin/sunny_emission.tres")}
var component_meshes := 0
var visual_instances := 0
func _ready() -> void:
 build()
func meshes(root_node: Node) -> Array:
 var out := []
 if root_node is MeshInstance3D: out.append(root_node)
 for c in root_node.get_children(): out.append_array(meshes(c))
 return out
func build() -> void:
 for c in get_children(): c.free()
 component_meshes=0;visual_instances=0
 var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DATA))
 var groups := {}
 for entry in data.instances:
  if not groups.has(entry.component): groups[entry.component]=[]
  groups[entry.component].append(entry)
 for key in groups:
  var packed: PackedScene=load("res://assets/models/facilities/solar_cabin/components/%s/%s.glb" % [key,key])
  var imported: Node3D=packed.instantiate()
  var entries: Array=groups[key]
  for mi in meshes(imported):
   var mesh: ArrayMesh=mi.mesh.duplicate()
   for surface in mesh.get_surface_count():
    var mat: Material=mesh.surface_get_material(surface)
    var role: String="Matte"
    if mat != null:
     for candidate in MATERIALS:
      if candidate in mat.resource_name: role=candidate
    mesh.surface_set_material(surface,MATERIALS[role])
   var mm := MultiMesh.new()
   mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=entries.size()
   for i in entries.size():
    var a: Array=entries[i].transform
    var basis := Basis(Vector3(a[0][0],a[1][0],a[2][0]),Vector3(a[0][1],a[1][1],a[2][1]),Vector3(a[0][2],a[1][2],a[2][2]))
    mm.set_instance_transform(i,Transform3D(basis,Vector3(a[0][3],a[1][3],a[2][3]))*mi.transform)
   var visual := MultiMeshInstance3D.new();visual.name=key+"_"+str(component_meshes);visual.multimesh=mm
   visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;visual.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
   visual.set_meta("asset_component",key);visual.set_meta("category",entries[0].category)
   add_child(visual);component_meshes+=1;visual_instances+=entries.size()
  imported.free()
''')
write(G/'scenes/facilities/solar_cabin_surface.tscn','''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://src/world/sunny_bloom_visual.gd" id="1"]
[node name="太阳能木屋-海上区域" type="Node3D"]
script = ExtResource("1")
metadata/asset_id = "SEA-SCENE-SBR-ASSEMBLY"
metadata/front_godot = Vector3(0, 0, 1)
metadata/deck_height = 2.15
''')
# Bind legacy surfaces by their original slot names, not by new primitive order.
bindings={
 'detail':['baked_tn_0000','baked_tn_0001','baked_tn_0110','baked_tn_0111','baked_tn_1000'],
 'unit_01':['baked_tn_0000','baked_tn_0100','baked_tn_0111','baked_tn_1000','baked_t0_1000','baked_t1_1000'],
 'unit_02':['baked_tn_0000','baked_tn_1000','baked_t1_1000'],
 'unit_03':['baked_tn_0000','baked_tn_1000','baked_t1_1000','baked_t2_0000']}
js(G/'assets/models/facilities/legacy_home/material_bindings.json',bindings)
write(G/'src/world/legacy_facility_materials.gd','''@tool
extends Node3D
func _ready() -> void:
 var bindings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/facilities/legacy_home/material_bindings.json"))
 apply(self,bindings)
func apply(node: Node, bindings: Dictionary) -> void:
 if node is MeshInstance3D:
  for i in node.mesh.get_surface_count():
   var m: Material=node.mesh.surface_get_material(i)
   if m==null: continue
   var name_parts: PackedStringArray=m.resource_name.split(".")[0].rsplit("_",true,1)
   if name_parts.size()!=2: continue
   var unit: String=name_parts[0];var slot: int=int(name_parts[1])
   if bindings.has(unit) and slot<bindings[unit].size():
    node.set_surface_override_material(i,load("res://assets/materials/models/"+str(bindings[unit][slot])+".tres"))
 for c in node.get_children(): apply(c,bindings)
''')
def legacy_scene(name,entries):
 text=f'[gd_scene load_steps={len(entries)+2} format=3]\n[ext_resource type="Script" path="res://src/world/legacy_facility_materials.gd" id="bind"]\n'
 for i,e in enumerate(entries):text+=f'[ext_resource type="PackedScene" path="res://{e["glb"].removeprefix("godot/")}" id="g{i}"]\n'
 text+=f'[node name="{name}" type="Node3D"]\nscript = ExtResource("bind")\n'
 for i,e in enumerate(entries):
  p=e['origin_godot'] if e['key']!='salvage_station' else [0,0,0]
  text+=f'[node name="{e["key"]}" parent="." instance=ExtResource("g{i}")]\nposition = Vector3({p[0]}, {p[1]}, {p[2]})\n'
 return text
write(G/'scenes/facilities/solar_cabin_submerged_base.tscn',legacy_scene('太阳能木屋-海下基座',[e for e in report['legacy'] if e['key']!='salvage_station']))
write(G/'scenes/facilities/salvage_station.tscn',legacy_scene('绞盘打捞台',[e for e in report['legacy'] if e['key']=='salvage_station']))
scene=G/'scenes/zones/zone1_home_harbor.tscn';s=scene.read_text();s=s.replace('; >>> models（由 tools/build_zone_scenes.gd 生成，手改会被覆盖）','; >>> models（手工装配：旧运行模型保留为隐藏回退，禁止旧构建器覆盖）')
for name in ['detail','unit_01','unit_02','unit_03']:
 pattern=r'(\[node name="'+name+r'" parent="Models" instance=[^\n]+\]\n)';s,n=re.subn(pattern,r'\1visible = false\n',s);assert n==1
ext=''
for id,path in [('sunny_surface','solar_cabin_surface'),('home_base','solar_cabin_submerged_base'),('independent_salvage','salvage_station')]:ext+=f'[ext_resource type="PackedScene" path="res://scenes/facilities/{path}.tscn" id="{id}"]\n'
s=s.replace('[node name="Zone1HomeHarbor"',ext+'\n[node name="Zone1HomeHarbor"',1)
nodes='''
[node name="太阳能木屋-海上区域" parent="Models" instance=ExtResource("sunny_surface")]
[node name="太阳能木屋-海下基座" parent="Models" instance=ExtResource("home_base")]
[node name="绞盘打捞台" parent="Models" instance=ExtResource("independent_salvage")]
position = Vector3(-12, 0, 13)
'''
s=s.replace('; <<< models',nodes+'; <<< models',1)
# Walk only on the open forecourt and the two dock strips, excluding house walls.
walks=[rect(-1.3,1.0,-5.82,-2.85),rect(-2.52,-.70,-5.85,-5.60),rect(-2.52,-1.58,-8.70,-5.60),rect(-1.30,-.35,-8.70,-5.60)]
walk_text='rects = ['+', '.join('Rect2('+', '.join(f'{v:.6f}' for v in r)+')' for r in walks)+']'
start=s.index('[node name="Walk_zone1_home_dock"');end=s.index('[node name="Walk_zone1_salvage"');block=s[start:end];block=re.sub(r'^rects = .*$',walk_text,block,flags=re.M);block=re.sub(r'^polygons = .*$','polygons = []',block,flags=re.M);s=s[:start]+block+s[end:]
stand=point(-.82,-8.15);edge=point(-.82,-8.75);park=[stand[0],1.12,13.3]
start=s.index('[node name="Landing_main"');end=s.index('[node name="Landing_salvage"');block=s[start:end]
def v3(p):return 'Vector3('+', '.join(f'{v:.6f}' for v in p)+')'
block=re.sub(r'(\[node name="Landing_main"[^\]]*\]\n)position = .*',lambda m:m[1]+'position = '+v3(stand),block)
block=re.sub(r'(\[node name="BoatPark"[^\]]*\]\n)position = .*',lambda m:m[1]+'position = '+v3([park[i]-stand[i] for i in range(3)]),block);block=re.sub(r'rotation = Vector3\(0, -1.05, 0\)',f'rotation = Vector3(0, {math.pi/2}, 0)',block)
block=re.sub(r'(\[node name="DockEdge"[^\]]*\]\n)position = .*',lambda m:m[1]+'position = '+v3([edge[i]-stand[i] for i in range(3)]),block);s=s[:start]+block+s[end:]
plot=point(.35,-4.65);s=re.sub(r'(\[node name="home_plot"[^\]]*\]\n)position = .*',lambda m:m[1]+'position = '+v3(plot),s)
count=len(re.findall(r'^\[ext_resource|^\[sub_resource',s,flags=re.M))+1;s=re.sub(r'load_steps=\d+',f'load_steps={count}',s,count=1);write(scene,s)
zones=json.loads((G/'assets/data/zones.json').read_text());z=next(x for x in zones if x['id']=='zone1');z['hover']=[4.3,6.2,-.4];z['camera']=[4.3,3.2,2.4]
landing=next(x for x in z['landings'] if x['id']=='main');landing.update(boatPark=park,boatYaw=math.pi/2,dockEdge=edge,landStand=stand)
walk=next(x for x in z['walk'] if x['id']=='zone1_home_dock');walk['rects']=[[r[0],r[0]+r[2],r[1],r[1]+r[3]] for r in walks];walk['polygons']=[]
js(G/'assets/data/zones.json',zones)
build=json.loads((G/'assets/data/build_sites.json').read_text());home=next(x for x in build['sites'] if x['id']=='home_cabin');p=point(-1.0,-3.1);home.update(x=p[0],y=p[1],z=p[2]);js(G/'assets/data/build_sites.json',build)
gather=json.loads((G/'assets/data/gather_spots.json').read_text())
for e in gather['spots']:
 if e['id'] in ['zone1_shell','zone1_wood']:
  p=point(.2,-5.5) if e['id']=='zone1_shell' else point(-1.0,-3.5);e.update(x=p[0],y=p[1],z=p[2])
js(G/'assets/data/gather_spots.json',gather)
plants=json.loads((G/'assets/data/plants_zone1_home_harbor.json').read_text());before=len(plants['plants'])
plants['plants']=[e for e in plants['plants'] if e['p'][1]<=1.12 or (-16.7<=e['p'][0]<=-7.1 and 9<=e['p'][2]<=17.2)]
js(G/'assets/data/plants_zone1_home_harbor.json',plants)
shore=json.loads((G/'assets/baked/shore.json').read_text())
for r in [rect(-3.9,3.6,-6.0,3.2),rect(-2.59,-1.51,-8.75,-6.0),rect(-1.36,-.28,-8.75,-6.0)]:shore['shapes'].append(dict(x=r[0]+r[2]*.5,z=r[1]+r[3]*.5,hx=r[2]*.5,hz=r[3]*.5,round=False,asset_id='SEA-SCENE-SBR-ASSEMBLY'))
js(G/'assets/baked/shore.json',shore)
js(W/'integration.json',dict(scale=1.15,source_front='-Y',front_godot='+Z',yaw_degrees=0,deck_height=2.15,anchor_godot=[5.128,1.368,.704],stand=stand,edge=edge,boatPark=park,boatYaw=math.pi/2,home_plot=plot,walk_rects=walks,old_plants_removed=before-len(plants['plants']),legacy_models_hidden=['detail','unit_01','unit_02','unit_03']))
print('Integrated: component surface, original underwater bases, independent salvage; anchors aligned')
