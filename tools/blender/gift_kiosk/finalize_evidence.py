"""Collect the verified delivery previews and a compact reproducible receipt."""
import argparse,hashlib,json,os,re,shutil
from pathlib import Path
from PIL import Image
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/gift_kiosk/v001';W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);a=p.parse_args();report=json.loads(a.report.read_text(encoding='utf-8'));out=Path(report['run_dir'])/'project/outputs';final=W/'final';final.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name in ['hero-day','hero-night','storefront-character','boarding','top-day','back-day','right-day','supply-panel','old-rest-stop']:
 shutil.copy2(out/f'gift-kiosk-{name}.png',final/f'godot-{name}.png')
shutil.copy2(W/'hero.png',final/'blender-hero.png')
frames=[]
for i in range(20):
 im=Image.open(out/f'gift-kiosk-motion-{i:02d}.png').convert('RGB');im.thumbnail((960,600));frames.append(im.convert('P',palette=Image.Palette.ADAPTIVE,colors=192))
frames[0].save(final/'floating-support.gif',save_all=True,append_images=frames[1:],duration=358,loop=0,optimize=False)
own=['godot/scenes/main.tscn','godot/scenes/facilities/floating_shop.tscn','godot/scenes/facilities/floating_rest_stop.tscn','godot/src/player/actor_controller.gd','godot/src/player/character_motor.gd','godot/src/navigation/ground_space.gd','godot/src/world/zones.gd','godot/src/facilities/floating_shop_zone.gd','godot/tools/gift_kiosk_import.gd','godot/tools/capture_gift_kiosk.gd','godot/tests/test_gift_kiosk.gd','godot/tests/test_water_layer.gd']
staged=Path(report['run_dir'])/'project'
for name in own:
 candidate=staged/name.removeprefix('godot/');assert candidate.is_file() and sha(candidate)==sha(R/name),name+' changed since final verification'
runtime=json.loads((R/'assets/registry/runtime_resource_inventory.json').read_text(encoding='utf-8'))['resources'];owned=[e for e in runtime if 'gift_kiosk' in e['path'] or e['path'] in own]
receipt={'schema':'sea.gift_kiosk.delivery_verification','feature_ids':['SEA-ASSET-R55','SEA-WORLD-R24','SEA-MOVE-R25','SEA-NAV-R18'],'source':str(D/'gift_kiosk.blend'),'source_verification':json.loads((W/'source_verification.json').read_text()),'export_audit':json.loads((W/'export_audit.json').read_text()),'fidelity':json.loads((W/'fidelity.json').read_text()),'placement':json.loads((W/'placement.json').read_text()),'registration':json.loads((W/'registration.json').read_text()),'final_runtime_report':str(a.report.resolve()),'results':report['results'],'import':report.get('asset_import'),'raw_runtime_evidence':str(out/'gift-kiosk-verification.json'),'real_render_evidence':str(out/'gift-kiosk-render.json'),'media':str(final),'authored_runtime_sha256':{name:sha(R/name) for name in own},'reviewed_resources':owned,'expected_rejections':['sea/prop/wall walking is rejected','open-water actor save is rejected','old navigation-only rest stop has no playable zone or duplicate supply interaction'],'unexpected_runtime_errors':[],'not_executed':['user final art preference','commercial reference rights review','low-end GPU/large-scale LOD performance','controller/touch controls'],'other_baseline_drift':['SEA-DECO-ANIMAL-FISH-SCHOOL source','godot/assets/materials/water.tres','godot/src/bootstrap/main.gd']}
target=R/'docs/development/2026-11-07_gift_kiosk_verification.json';target.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'receipt':str(target),'media':str(final),'snapshot_matches_current_authored_runtime':True},ensure_ascii=False))
