"""Pack the unchanged v003 meshes into five editable, bottom-centred Blender modules."""
import bpy
from mathutils import Vector
from plan_v004 import ROOT, OLD, NEW, WORK, sha, read, write

plan=read(NEW/'component_plan.json')
parent=ROOT/plan['parent_source']
assert sha(parent)==plan['parent_sha256']
assert sha(NEW/plan['reference'])==plan['reference_sha256']
bpy.ops.wm.open_mainfile(filepath=str(parent))
bpy.context.preferences.filepaths.save_version=0
scene=bpy.data.scenes['霓虹花园街区_完整装配']
bpy.context.window.scene=scene
bpy.context.view_layer.update()
placed={obj.name:obj for obj in scene.objects if obj.instance_type=='COLLECTION'}
assert set(placed)==set(plan['ownership'])
original={name:obj.matrix_world.copy() for name,obj in placed.items()}
parts={row['key']:row for row in read(OLD/'component_catalog.json')['components']}
by_name={row['name']:row for row in read(OLD/'component_instances.json')['instances']}
master=NEW/'neon_garden_quarter.blend'

def image_paths(destination):
    for img in bpy.data.images:
        if img.source!='FILE':continue
        field='palette' if img.name.startswith('SEA_') else 'poster_source'
        img.filepath=bpy.path.relpath(str(ROOT/plan[field]),start=str(destination.parent))

def extent(objects,placement):
    low=Vector((float('inf'),)*3);high=-low
    for instance in objects:
        for mesh in instance.instance_collection.objects:
            transform=placement(instance)@mesh.matrix_local
            for vertex in mesh.data.vertices:
                point=transform@vertex.co
                for axis in range(3):
                    low[axis]=min(low[axis],point[axis]);high[axis]=max(high[axis],point[axis])
    return low,high

modules={}
for key,spec in plan['modules'].items():
    objects=[obj for name,obj in placed.items() if plan['ownership'][name]==key]
    low,high=extent(objects,lambda obj:original[obj.name])
    pivot=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
    name=f'NGQ_MODULE_{key}'
    module=bpy.data.collections.new(name)
    module['asset_id']=spec['asset_id'];module['label']=spec['label']
    by_category={}
    for obj in objects:
        row=by_name[obj.name]
        category=parts[row['key']]['category']
        if category not in by_category:
            collection=bpy.data.collections.new(f'{key}__{category}')
            collection['ngq_category']=category;module.children.link(collection)
            by_category[category]=collection
        by_category[category].objects.link(obj)
        for old in list(obj.users_collection):
            if old!=by_category[category]:old.objects.unlink(obj)
        obj.location=original[obj.name].translation-pivot
    instance=bpy.data.objects.new(spec['node'],None)
    instance.instance_type='COLLECTION';instance.instance_collection=module;instance.location=pivot
    instance['asset_id']=spec['asset_id'];scene.collection.objects.link(instance)
    directory=NEW/'module_packages'/key;directory.mkdir(parents=True,exist_ok=True)
    modules[key]=dict(spec,collection=name,anchor_blender=list(pivot),bounds=[list(low),list(high)],source=(directory/f'{key}.blend').relative_to(ROOT).as_posix(),manifest=(directory/'asset_manifest.json').relative_to(ROOT).as_posix(),member_names=sorted(obj.name for obj in objects),dependencies=sorted({by_name[obj.name]['asset_id'] for obj in objects}))

for collection in list(scene.collection.children):
    if not collection.objects and not collection.children:scene.collection.children.unlink(collection)
scene['revision']='v004_five_modules'
image_paths(master)
bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)

# Reopen the master and replay every transform from the saved five module roots.
bpy.ops.wm.open_mainfile(filepath=str(master))
scene=bpy.data.scenes['霓虹花园街区_完整装配'];bpy.context.view_layer.update()
seen=set()
for key,module in modules.items():
    instance=scene.objects[module['node']]
    assert instance.instance_collection.name==module['collection']
    for child in instance.instance_collection.all_objects:
        assert child.name not in seen
        seen.add(child.name)
        matrix=instance.matrix_world@child.matrix_local
        assert max(abs(a-b) for x,y in zip(matrix,original[child.name]) for a,b in zip(x,y))<5e-6,child.name
assert seen==set(original)

for key,module in modules.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    with bpy.data.libraries.load(str(master),link=False) as (library,output):
        output.collections=[module['collection']]
    collection=output.collections[0]
    bpy.context.scene.collection.children.link(collection)
    bpy.context.scene.name=module['label'];bpy.context.scene.unit_settings.system='METRIC'
    bpy.context.scene['asset_id']=module['asset_id']
    package=ROOT/module['source'];image_paths(package)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.shading.type='MATERIAL'
                height=module['bounds'][1][2]-module['bounds'][0][2]
                area.spaces.active.region_3d.view_location=(0,0,height/2)
                area.spaces.active.region_3d.view_distance=max(20,height*1.6)
    bpy.ops.wm.save_as_mainfile(filepath=str(package),compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(package))
    collection=bpy.data.collections[module['collection']]
    members=list(collection.all_objects)
    assert sorted(obj.name for obj in members)==module['member_names']
    assert all(obj.instance_collection is not None for obj in members)
    assert set(bpy.context.scene.objects)==set(members)
    low,high=extent(members,lambda obj:obj.matrix_world)
    assert abs(low.z)<5e-6 and abs(low.x+high.x)<5e-6 and abs(low.y+high.y)<5e-6
    for img in bpy.data.images:
        if img.source=='FILE':
            assert not img.packed_file and bpy.path.abspath(img.filepath)==bpy.path.abspath(img.filepath, start=str(package.parent))
            assert (package.parent/img.filepath.removeprefix('//')).resolve().is_file(),img.filepath
    module['source_sha256']=sha(package);module['local_bounds']=[list(low),list(high)]
    print('V004 module reopened',key,len(members),flush=True)

assert sha(parent)==plan['parent_sha256']
write(NEW/'module_catalog.json',dict(version='v004',modules=modules))
write(WORK/'source_verification.json',dict(passed=True,master_sha256=sha(master),parent_source_sha256=sha(parent),modules_reopened=len(modules),placement_matrices_preserved=len(seen)))
