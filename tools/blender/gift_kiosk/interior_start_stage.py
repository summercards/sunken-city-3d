import argparse,subprocess,os
from pathlib import Path
R=Path(__file__).resolve().parents[3];W=R.parent/'sea-work/gift_kiosk/interior/v001'
p=argparse.ArgumentParser();p.add_argument('--port',type=int,required=True);p.add_argument('--file',required=True);a=p.parse_args()
start=W/f'start_{a.port}.py'
start.write_text("import bpy,addon_utils\naddon_utils.enable('addon',default_set=False,persistent=False)\ndef start():\n bpy.context.scene.blendermcp_port="+str(a.port)+"\n bpy.ops.blendermcp.start_server()\n print('GKI_STAGE_READY',flush=True)\nbpy.app.timers.register(start,first_interval=2)\n",encoding='utf-8')
with (W/f'gui_{a.port}.log').open('w') as out,(W/f'gui_{a.port}_error.log').open('w') as err:
 proc=subprocess.Popen(['D:/Program Files/Blender Foundation/Blender 4.5/blender.exe','--factory-startup',str(Path(a.file).resolve()),'--python',str(start)],stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
print('GUI PID',proc.pid,'port',a.port)
