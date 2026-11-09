import bpy, json, hashlib
from pathlib import Path
from mathutils import Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v004_lowpoly';S=D/'bld_20261109_a_v004_lowpoly.blend';OUT=R/'godot/assets/models/facilities/water_building_001/water_building_001.glb';W=R.parent/'sea-work/bld_20261109_a/v004_lowpoly';OUT.parent.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False)
sc=bpy.context.scene
assert sc.name=='BLDA_编号海上建筑_v004_lowpoly'
source_sha=hashlib.sha256(S.read_bytes()).hexdigest()
# Build a temporary export-only scene by expanding the 92 collection instances.
exp=bpy.data.scenes.new('BLDA_WATER_BUILDING_001_EXPORT')
exp.unit_settings.system='METRIC';exp.unit_settings.scale_length=1.0
root=bpy.data.collections.new('WATER_BUILDING_001_GAME_OUTPUT');exp.collection.children.link(root)
instance_empties=[o for o in sc.objects if o.instance_type=='COLLECTION' and o.instance_collection]
assert len(instance_empties)==92, len(instance_empties)
created=[]
for inst in instance_empties:
    col=inst.instance_collection
    for src in col.all_objects:
        if src.type!='MESH' or src.hide_render: continue
        me=src.data.copy(); world=inst.matrix_world @ src.matrix_world; me.transform(world)
        ob=bpy.data.objects.new(f'WB001_{inst.name}_{src.name}',me);root.objects.link(ob);created.append(ob)
        for mat in src.data.materials:
            if mat and mat.name not in [m.name for m in me.materials]: me.materials.append(mat)
# Keep only the export scene in the glTF. Leaving the authoring scene datablock
# produces a second empty glTF scene in Blender 4.5, which breaks some importers.
bpy.context.window.scene=exp
bpy.data.scenes.remove(sc)
bpy.ops.object.select_all(action='DESELECT')
for ob in created: ob.select_set(True)
if created: bpy.context.view_layer.objects.active=created[0]
# No image is embedded. Runtime wrapper supplies the shared palette role materials.
bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',use_selection=True,export_apply=True,export_materials='EXPORT',export_image_format='NONE',export_yup=True)
# The export-only scene is intentionally left in memory until Blender exits;
# source file is never saved here.
sha=hashlib.sha256(OUT.read_bytes()).hexdigest()
report={'asset_id':'SEA-SCENE-WATER-BUILDING-001','source_path':str(S.relative_to(R)).replace('\\','/'),'source_sha256':source_sha,'optimized_path':str(S.relative_to(R)).replace('\\','/'),'runtime_glb':str(OUT.relative_to(R)).replace('\\','/'),'runtime_glb_sha256':sha,'instances_expanded':len(instance_empties),'exported_mesh_objects':len(created),'source_not_saved':True,'embedded_images':'none','axis':'Blender Z-up exported glTF Y-up; Godot import preserves scene-space orientation'}
(W/'runtime_export.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,ensure_ascii=False),flush=True)
