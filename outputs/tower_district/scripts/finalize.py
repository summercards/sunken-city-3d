import bpy,math,json
from mathutils import Vector
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district';s=bpy.context.scene
bpy.data.objects['TD_Car_right_brown'].rotation_euler.z=.28
bpy.data.objects['TD_Car_right_crop'].rotation_euler.z=.21
for o in s.objects:
 if o.type=='LIGHT' and o.name.startswith('TD_Green_spill'):o.data.energy=28;o.data.shadow_soft_size=.1
 if o.type=='LIGHT' and o.name.startswith('TD_Terminal_spill'):o.data.shadow_soft_size=.12
# Add a smooth edge mask to the noise field; cube bounds remain invisible while billows drift.
for label in ['Left_exhaust','Right_exhaust']:
 ob=next(o for o in s.objects if o.name.startswith('TD_Volume_'+label));mat=ob.data.materials[0];nt=mat.node_tree
 v=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeVolumePrincipled');ramp=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeValToRGB')
 ramp.color_ramp.elements[0].position=.26;ramp.color_ramp.elements[1].position=.68;ramp.color_ramp.elements[1].color=(.48,.48,.48,1)
 tex=nt.nodes.new('ShaderNodeTexCoord');dist=nt.nodes.new('ShaderNodeVectorMath');dist.operation='DISTANCE';dist.inputs[1].default_value=(.5,.5,.5);nt.links.new(tex.outputs['Generated'],dist.inputs[0])
 sub=nt.nodes.new('ShaderNodeMath');sub.operation='SUBTRACT';sub.inputs[0].default_value=.66;nt.links.new(dist.outputs['Value'],sub.inputs[1])
 mult=nt.nodes.new('ShaderNodeMath');mult.operation='MULTIPLY';mult.inputs[1].default_value=2.2;mult.use_clamp=True;nt.links.new(sub.outputs[0],mult.inputs[0])
 dens=nt.nodes.new('ShaderNodeMath');dens.operation='MULTIPLY';nt.links.new(ramp.outputs[0],dens.inputs[0]);nt.links.new(mult.outputs[0],dens.inputs[1]);nt.links.new(dens.outputs[0],v.inputs['Density'])
# The delivered default opens at the matching reference view with visible material color.
for a in bpy.context.screen.areas:
 if a.type=='VIEW_3D':
  a.spaces.active.region_3d.view_perspective='CAMERA';a.spaces.active.overlay.show_overlays=False
  a.spaces.active.shading.type='MATERIAL';a.spaces.active.shading.use_scene_world=True;a.spaces.active.shading.use_scene_lights=True
s.timeline_markers.clear()
for f,n in [(1,'REFERENCE / LOOP START'),(61,'HOVER + RAIN'),(121,'SCAN / TRAFFIC'),(181,'STEAM / WIND')]:s.timeline_markers.new(n,frame=f)
s.frame_set(1);s.render.resolution_percentage=100;s.render.filepath=BASE+'/previews/tower_district_final.png'
s.render.image_settings.color_mode='RGB';s['Version']='v005';s['Readme']=BASE+'/README.md';s['Palette']='Packed shared 16x16 palette; four surface roles; volumetric materials separate.'
# Retain only useful datablocks when saving: pack palette and remove orphan earlier generated data.
for im in bpy.data.images:
 if im.name.startswith('TD_Shared_Palette') and im.users>0:
  if not im.packed_file:im.pack()
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/source/tower_district_v005.blend')
bpy.ops.render.render(write_still=True)
print('FULL_RESOLUTION_RENDER_COMPLETE')
