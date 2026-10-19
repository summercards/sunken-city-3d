import bpy,json
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district';s=bpy.context.scene
for label,center,dimensions in [('Left_exhaust',(-9.4,2,3.6),(4.8,5,6.8)),('Right_exhaust',(13.3,2.6,3.9),(5.5,5,7.2))]:
 ob=next(o for o in s.objects if o.name.startswith('TD_Volume_'+label));nt=ob.data.materials[0].node_tree
 geom=nt.nodes.new('ShaderNodeNewGeometry');geom.label='Explicit world-space mist coordinates'
 sub=nt.nodes.new('ShaderNodeVectorMath');sub.operation='SUBTRACT';sub.inputs[1].default_value=center;nt.links.new(geom.outputs['Position'],sub.inputs[0])
 div=nt.nodes.new('ShaderNodeVectorMath');div.operation='DIVIDE';div.inputs[1].default_value=dimensions;nt.links.new(sub.outputs['Vector'],div.inputs[0])
 length=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeVectorMath' and n.operation=='DISTANCE');length.inputs[1].default_value=(0,0,0);nt.links.new(div.outputs['Vector'],length.inputs[0])
 noise=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeTexNoise');noise.inputs['Scale'].default_value=.78;nt.links.new(geom.outputs['Position'],noise.inputs['Vector'])
 ramp=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeValToRGB');ramp.color_ramp.elements[1].color=(.60,.60,.60,1)
# Point light surfaces shouldn't present as floating circles in the finished scene.
for o in s.objects:
 if o.type=='LIGHT' and ('Green_spill' in o.name or 'Terminal_spill' in o.name):o.data.shadow_soft_size=.03
# Clean generated iteration data and give the four shared surface roles stable names.
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=False,do_recursive=True)
for role in ['Metal','Matte','WetPaint','Emission']:
 active=next(m for o in s.objects if o.type=='MESH' and not o.name.startswith('TD_Volume_') for m in o.data.materials if m.name.startswith('TD_'+role))
 active.name='TD_'+role
s['Version']='v006';s.frame_set(1);s.render.filepath=BASE+'/previews/tower_district_final.png'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/source/tower_district_v006.blend')
bpy.ops.render.render(write_still=True)
print('FOG_POLISH_RENDER_COMPLETE')
