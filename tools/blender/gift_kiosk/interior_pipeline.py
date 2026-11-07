"""Run existing independently audited data pipeline for this new extension only."""
import bpy,json,hashlib,os
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/gift_kiosk_interior/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/interior/v001'
stage=bpy.context.scene.get('gki_pipeline_stage','optimize')
script={'optimize':'optimize_data.py','export':'export_data.py','audit':'audit_export.py'}[stage]
code=(R/'tools/blender/gift_kiosk'/script).read_text(encoding='utf-8')
code=code.replace("R/'art_source/scenes/gift_kiosk/v001'","R/'art_source/scenes/gift_kiosk_interior/v001'")
code=code.replace("/'gift_kiosk/v001'","/'gift_kiosk/interior/v001'").replace("'gift_kiosk_optimized_v001.blend'","'gift_kiosk_interior_optimized_v001.blend'").replace("D/'gift_kiosk.blend'","D/'gift_kiosk_interior.blend'")
code=code.replace('facilities/gift_kiosk/','facilities/gift_kiosk_interior/')
exec(code)
