import bpy,json
from mathutils import Vector
BASE='/Users/summercards/WorkBuddy/sea/outputs/tower_district';s=bpy.context.scene
for label,oldc,oldd,center,dims in [('Left_exhaust',(-9.4,2,3.6),(4.8,5,6.8),(-9.4,-.5,3.6),(6,10,7.2)),('Right_exhaust',(13.3,2.6,3.9),(5.5,5,7.2),(13.0,-.2,3.9),(6,10,7.6))]:
 ob=next(o for o in s.objects if o.name.startswith('TD_Volume_'+label));nt=ob.data.materials[0].node_tree
 for ve in ob.data.vertices:
  ve.co=Vector([center[j]+(ve.co[j]-oldc[j])/oldd[j]*dims[j] for j in range(3)])
 ob.data.update()
 sub=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeVectorMath' and n.operation=='SUBTRACT');sub.inputs[1].default_value=center
 div=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeVectorMath' and n.operation=='DIVIDE');div.inputs[1].default_value=dims
 v=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeVolumePrincipled');v.inputs['Color'].default_value=(.40,.64,.77,1);v.inputs['Anisotropy'].default_value=.12
 ramp=next(n for n in nt.nodes if n.bl_idname=='ShaderNodeValToRGB');ramp.color_ramp.elements[1].color=(.56,.56,.56,1)
for side,x in [('L',-9.7),('R',13.0)]:
 ld=bpy.data.lights.new('TD_Steam_fill_'+side,'AREA');ld.energy=600;ld.color=(.38,.7,1);ld.shape='DISK';ld.size=3
 ob=bpy.data.objects.new('TD_Steam_fill_'+side,ld);s.collection.children['TD_90_相机灯光'].objects.link(ob);ob.location=(x,-2,5.2);ob.rotation_euler=(Vector((x,1,3))-ob.location).to_track_quat('-Z','Y').to_euler()
# Reference camera plus useful static inspection cameras. Optical area light shape does not add mesh curves.
co=s.collection.children['TD_90_相机灯光']
for name,loc,target,ortho in [('TD_Detail_Camera',(2,-19,9.2),(2,5,9.4),None),('TD_Top_Camera',(0,10,75),(0,10,0),100)]:
 cd=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,cd);co.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();cd.lens=47;cd.clip_end=250
 if ortho:cd.type='ORTHO';cd.ortho_scale=ortho
s['Version']='v007';s.frame_set(1);s.render.resolution_percentage=100;s.render.filepath=BASE+'/previews/tower_district_final.png'
bpy.ops.wm.save_as_mainfile(filepath=BASE+'/source/tower_district_v007.blend')
bpy.ops.render.render(write_still=True)
print('ATMOSPHERE_FINISHED')
