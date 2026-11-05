"""Create stable purely visual component wrappers + one new assembly, incrementally mount in main.
Consumes only 02b-exported GLBs. Never regenerates an existing assembly or overwrites author edits.
"""
import hashlib,json,math,struct
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v003';O=D/'export/v003';W=R.parent/'sea-work/sunken_city/v003/import'
G=R/'godot';CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));E=json.loads((O/'export_manifest.json').read_text(encoding='utf-8'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert E['passed'] and len(E['components'])==50
for p,h in E['protected_sources'].items():assert sha(R/p)==h,p
q=lambda s:json.dumps(str(s),ensure_ascii=False)
def write(p,s):
    assert p.parent.is_dir(),p.parent
    if p.exists():assert p.read_text(encoding='utf-8')==s,'Do not overwrite authored runtime file '+str(p)
    else:p.write_text(s,encoding='utf-8')
roles={'SEA_Matte':('matte',0,.78,0),'SEA_Metal':('metal',.15,.82,0),'SEA_Gloss':('gloss',.08,.3,.3)}
for role,(key,metal,rough,coat) in roles.items():
    text='[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n\n[ext_resource type="Texture2D" path="res://assets/textures/shared/sea_cabin_timber_8x8_512.png" id="palette"]\n\n[resource]\n'
    text+=f'resource_name = "{role}_SUN KEN"\nalbedo_color = Color(1, 1, 1, 1)\nalbedo_texture = ExtResource("palette")\ntexture_filter = 0\ntexture_repeat = false\ncull_mode = 2\nmetallic = {metal}\nroughness = {rough}\nclearcoat_enabled = {str(coat>0).lower()}\nclearcoat = {coat}\nemission_enabled = false\n'
    text=text.replace('SUN KEN','SUNKEN')
    write(G/f'assets/materials/sunken_city/{key}.tres',text)
records=[]
for entry in E['components']:
    key=entry['key'];c=next(c for c in CAT if c['key']==key);path=R/entry['glb'];assert sha(path)==entry['glb_sha256']
    data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+n]);assert not doc.get('images') and not doc.get('textures')
    assert len(doc['scenes'][0]['nodes'])==1
    rootidx=doc['scenes'][0]['nodes'][0];node0=doc['nodes'][rootidx]
    used=set(r for node in entry['mesh_nodes'] for r in node['roles'])
    text='[gd_scene format=3]\n\n'
    text+=f'[ext_resource type="PackedScene" path={q("res://"+str(path.relative_to(G)).replace(chr(92),"/"))} id="model"]\n'
    for role in sorted(used):text+=f'[ext_resource type="Material" path="res://assets/materials/sunken_city/{roles[role][0]}.tres" id="{roles[role][0]}"]\n'
    text+=f'\n[node name={q(c["name"])} type="Node3D"]\nmetadata/asset_id = {q(c["component_id"])}\nmetadata/key = {q(key)}\nmetadata/asset_version = "v003"\nmetadata/building_class = "underwater"\nmetadata/source_suite = "sunken_city"\nmetadata/water_layer = "submerged"\nmetadata/water_layer_role = "part"\nmetadata/collision = false\nmetadata/interactive = false\nmetadata/blocks_water = false\nmetadata/shoreline_source = false\n\n[node name="Visual" parent="." instance=ExtResource("model")]\n'
    def traverse(idx,parentpath):
        nonlocal_dummy=None
        node=doc['nodes'][idx];out=''
        if 'mesh' in node:
            if idx==rootidx:path_parts=[]
            else:path_parts=parentpath+[node['name']]
            if idx==rootidx:out='[node name="Visual" parent="." index="0"]\n'
            else:
                parent='Visual/'+node0['name']+('/'+'/'.join(parentpath) if parentpath else '')
                out=f'[node name={q(node["name"])} parent={q(parent)} index="0"]\n'
            prims=doc['meshes'][node['mesh']]['primitives']
            for surface,prim in enumerate(prims):
                role=doc['materials'][prim['material']]['name'];out+=f'surface_material_override/{surface} = ExtResource("{roles[role][0]}")\n'
            out+='cast_shadow = 1\n'
        newparent=parentpath+([node['name']] if idx!=rootidx else [])
        for child in node.get('children',[]):out+=traverse(child,newparent)
        return out
    text+=traverse(rootidx,[])
    prefab=G/f'scenes/components/scenery/sunken_city/{key}.tscn';write(prefab,text)
    records.append(dict(key=key,asset_id=c['component_id'],prefab='res://'+prefab.relative_to(G).as_posix(),glb='res://'+path.relative_to(G).as_posix(),triangles=entry['triangles_after'],bounds_blender=entry['bounds_blender'],roles=sorted(used),prefab_sha256=sha(prefab),glb_sha256=sha(path),source_sha256=c['source_sha256']))
# Full Euler+nonuniform tangent scale conversion C*R*S*C^-1, not just a yaw shortcut.
def matmul(a,b):return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
C=[[1,0,0],[0,0,1],[0,-1,0]];CI=[[1,0,0],[0,0,-1],[0,1,0]]
def transform(a):
    x,y,z=[math.radians(v) for v in a['rotation_euler_deg']];cx,sx=math.cos(x),math.sin(x);cy,sy=math.cos(y),math.sin(y);cz,sz=math.cos(z),math.sin(z)
    rx=[[1,0,0],[0,cx,-sx],[0,sx,cx]];ry=[[cy,0,sy],[0,1,0],[-sy,0,cy]];rz=[[cz,-sz,0],[sz,cz,0],[0,0,1]]
    r=matmul(rz,matmul(ry,rx));s=a['scale'];r=[[r[i][j]*s[j] for j in range(3)] for i in range(3)]
    b=matmul(C,matmul(r,CI));p=a['position_m']
    return [b[i][j] for j in range(3) for i in range(3)]+[p[0],p[2],-p[1]]
instances=[];text='[gd_scene format=3]\n\n'
for i,c in enumerate(CAT):text+=f'[ext_resource type="PackedScene" path="res://scenes/components/scenery/sunken_city/{c["key"]}.tscn" id="c{i}"]\n'
text+='\n[node name="SunkenCity" type="Node3D"]\nmetadata/asset_id = "SEA-SCENE-SCITY-ASSEMBLY"\nmetadata/building_class = "underwater"\nmetadata/source_suite = "sunken_city"\nmetadata/asset_version = "v003"\nmetadata/water_layer = "submerged"\nmetadata/water_layer_role = "entity"\nmetadata/collision = false\nmetadata/blocks_water = false\nmetadata/shoreline_source = false\n\n'
for a in P['instances']:
    matrix=transform(a);idx=next(i for i,c in enumerate(CAT) if c['key']==a['key'])
    # Manifest/API columns differ from native Variant text basis rows; every instance is runtime-asserted.
    serial=[matrix[0],matrix[3],matrix[6],matrix[1],matrix[4],matrix[7],matrix[2],matrix[5],matrix[8]]+matrix[9:]
    text+=f'[node name={q(a["instance_id"])} parent="." instance=ExtResource("c{idx}")]\ntransform = Transform3D('+', '.join(f'{v:.10g}' for v in serial)+')\n'
    text+=f'metadata/instance_id = {q(a["instance_id"])}\nmetadata/urban_role = {q(a.get("urban_role",""))}\n\n'
    instances.append(dict(a,godot_transform=matrix))
assembly=G/'scenes/world/sunken_city.tscn';write(assembly,text)
manifest=dict(schema='sea.sunken_city.runtime_manifest',suite='sunken_city',version='v003',source_master_sha256=sha(D/'sunken_city_v003.blend'),components=records,instances=instances,assembly='res://scenes/world/sunken_city.tscn',terrain_contract=P['terrain_contract'],rail_extension=P['rail_extension'],pure_visual=True)
manifestpath=G/'assets/models/scenery/sunken_city/runtime_manifest.json';write(manifestpath,json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
# Incremental mount; save real current file before one ext_resource+one node addition.
main=G/'scenes/main.tscn';before=main.read_bytes();s=before.decode('utf-8');backup=W/'main_before_sunken_city.tscn'
if not backup.exists():backup.write_bytes(before)
resource='[ext_resource type="PackedScene" path="res://scenes/world/sunken_city.tscn" id="38_sunken_city"]'
node='[node name="SunkenCity" parent="World" instance=ExtResource("38_sunken_city")]\n'
if resource not in s:
    anchor='[sub_resource type="ArrayMesh"';index=s.index(anchor);s=s[:index]+resource+'\n'+s[index:]
if node.strip() not in s:
    anchor='[node name="Gameplay"';index=s.index(anchor);s=s[:index]+node+'\n'+s[index:]
# Remove exactly the added blocks and prove the rest is unchanged.
rest=s.replace(resource+'\n','').replace(node+'\n','');assert rest==before.decode('utf-8'),'unexpected main edit'
assert main.read_bytes()==before,'concurrent main edit detected'
main.write_bytes(s.encode('utf-8'))
write(W/'runtime_build.json',json.dumps({'passed':True,'components':len(records),'instances':len(instances),'assembly':str(assembly.relative_to(R)).replace('\\','/'),'main_sha256_before':hashlib.sha256(before).hexdigest(),'main_sha256_after':sha(main),'main_scope':'only new resource and World/SunkenCity instance; inverse diff equals original bytes','runtime_manifest':str(manifestpath.relative_to(R)).replace('\\','/')},ensure_ascii=False,indent=2)+'\n')
print('SCITY_RUNTIME_PREPARED',len(records),len(instances),'main patched incrementally')
