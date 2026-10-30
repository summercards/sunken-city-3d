"""Restore the installed local Blender MCP bridge in a GUI validation session."""
import bpy
import addon_utils
addon_utils.enable('addon',default_set=False,persistent=False)
def connect():
 bpy.context.scene.blendermcp_port=9876
 bpy.ops.blendermcp.start_server()
 print('FSH_GUI_MCP_RESTORED',flush=True)
 return None
bpy.app.timers.register(connect,first_interval=2)
