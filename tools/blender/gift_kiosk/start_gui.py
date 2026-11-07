"""Start the local MCP bridge in a clean GUI with stable solid viewport shading."""
import bpy,addon_utils,sys
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':area.spaces.active.shading.type='MATERIAL' if '--gks-present' in sys.argv else 'SOLID'
addon_utils.enable('addon',default_set=False,persistent=False)
def start():
 bpy.context.scene.blendermcp_port=9877
 bpy.ops.blendermcp.start_server()
 print('GKS_CLEAN_GUI_MCP_READY',flush=True)
 return None
bpy.app.timers.register(start,first_interval=2)
