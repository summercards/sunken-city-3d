import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
R=Path('D:/projects/sea');D=R/'art_source/scenes/water_building_002/v001';S=D/'water_building_002_v001.blend';OUT=R/'godot/assets/models/facilities/water_building_002/water_building_002.glb';W=R.parent/'sea-work/water_building_002/v001';OUT.parent.mkdir(parents=True,exist_ok=True);W.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(S),load_ui=False);sc=bpy.context.scene;assert sc.name=='WB002_编号002水上建筑_v001';source_sha=hashlib.sha256(S.read_bytes()).hexdigest();exp=bpy.data.scenes.new('WB002_WATER_BUILDING_002_EXPORT');root=bpy.data.collections.new('WATER_BUILDING_002_GAME_OUTPUT');exp.collection.children.link(root);insts=[o for o in sc.objects if o.instance_type=='COLLECTION' and o.instance_collection];assert len(insts)==57;created=[]
for inst in insts:
 for src in inst.instance_collection.all_objects:
  if src.type!='MESH' or src.hide_render:continue
  me=src.data.copy();me.transform(inst.matrix_world@src.matrix_world);ob=bpy.data.objects.new('WB002_'+inst.name+'_'+src.name,me);root.objects.link(ob);created.append(ob)
bpy.context.window.scene=exp;bpy.data.scenes.remove(sc);bpy.ops.object.select_all(action='DESELECT');[o.select_set(True) for o in created];bpy.context.view_layer.objects.active=created[0];bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',use_selection=True,export_apply=True,export_materials='EXPORT',export_image_format='NONE',export_yup=True);sha=hashlib.sha256(OUT.read_bytes()).hexdigest();report={'asset_id':'SEA-SCENE-WATER-BUILDING-002','source_sha256':source_sha,'runtime_glb':str(OUT.relative_to(R)).replace('\\','/'),'runtime_glb_sha256':sha,'instances_expanded':len(insts),'exported_mesh_objects':len(created),'embedded_images':'none','source_not_saved':True};(W/'runtime_export.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,ensure_ascii=False),flush=True)
