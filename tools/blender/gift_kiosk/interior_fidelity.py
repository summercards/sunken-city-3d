"""Reuse the same established kiosk fidelity tolerance for five fixed views."""
from pathlib import Path
R=Path(__file__).resolve().parents[3]
code=(R/'tools/blender/gift_kiosk/check_fidelity.py').read_text(encoding='utf-8')
code=code.replace("R/'art_source/scenes/gift_kiosk/v001'","R/'art_source/scenes/gift_kiosk_interior/v001'").replace("/'gift_kiosk/v001'","/'gift_kiosk/interior/v001'")
code=code.replace("['hero','front','back','right']","['game','front','rear','side','top']").replace("W/(name+'.png')","W/('source-'+name+'.png')").replace("W/('optimized_'+name+'.png')","W/('optimized-'+name+'.png')")
exec(code)
