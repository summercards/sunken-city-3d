import bpy,json
from pathlib import Path
ROOT=Path('/Users/summercards/WorkBuddy/sea');QA=ROOT/'outputs/tower_district/component_migration_v008/qa'
def ready():
 try:
  sc=bpy.data.scenes['TD_组件实例街区_v008'];bpy.context.window.scene=sc;sc.frame_set(1)
  for area in bpy.context.screen.areas:
   if area.type=='VIEW_3D':
    area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL';area.spaces.active.overlay.show_overlays=False
   if area.type=='OUTLINER':area.spaces.active.display_mode='VIEW_LAYER'
  if hasattr(sc,'blendermcp_port'):
   sc.blendermcp_port=9876;bpy.ops.blendermcp.start_server()
  (QA/'opened_in_blender.json').write_text(json.dumps({'file':bpy.data.filepath,'scene':sc.name,'frame':sc.frame_current,'camera':sc.camera.name,'source_component_count':sc.get('ComponentCount'),'instances':sc.get('InstanceCount'),'mcp_running':bool(getattr(sc,'blendermcp_server_running',False))},ensure_ascii=False,indent=2))
 except Exception as exc:
  (QA/'opened_in_blender.json').write_text(json.dumps({'error':str(exc)},ensure_ascii=False))
 return None
bpy.app.timers.register(ready,first_interval=1.0)
