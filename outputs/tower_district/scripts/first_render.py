import bpy,json
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district'
s=bpy.context.scene;cam=s.camera;nt=s.compositing_node_group
rl=next(n for n in nt.nodes if n.bl_idname=='CompositorNodeRLayers');gl=next(n for n in nt.nodes if n.bl_idname=='CompositorNodeGlare');out=next(n for n in nt.nodes if n.bl_idname=='NodeGroupOutput')
gl.inputs['Type'].default_value='Fog Glow';gl.inputs['Quality'].default_value='High';gl.inputs['Threshold'].default_value=1.2;gl.inputs['Strength'].default_value=.35;gl.inputs['Size'].default_value=.25
nt.links.new(rl.outputs['Image'],gl.inputs['Image']);nt.links.new(gl.outputs['Image'],out.inputs['Image'])
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':
  area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL'
s['Reference']='codex-clipboard-870292bc-3d91-4ec4-aa63-bc58500cf313.jpg'
s['Scope']='Complete visible district except people; cuboid geometry; animated drone/rain/steam/paper/tunnel cars.'
s['Animation']='1–240 at 24 fps; procedural 10-second cycle. Rotor angular motion is continuous.'
s.frame_set(1);s.render.filepath=BASE+'/previews/01_composition.png'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/source/tower_district_v001.blend')
print(json.dumps({'objects':len(s.objects),'mesh_objects':sum(o.type=='MESH' for o in s.objects),'boxes':sum(o.get('box_count',0) for o in s.objects),'file':bpy.data.filepath},ensure_ascii=False))
bpy.ops.render.render(write_still=True)
print('RENDER_FINISHED')
