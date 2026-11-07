"""Reviewable minimal replacement of one facility instance and one new placement."""
import hashlib,json,math,os,re,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[3];W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'gift_kiosk/v001'
MAIN=R/'godot/scenes/main.tscn';ZONES=R/'godot/assets/data/zones.json'
assert json.loads((R/'art_source/scenes/gift_kiosk/v001/export/v001/optimization_manifest.json').read_text(encoding='utf-8'))['fidelity']['passed']
if '[node name="floating_rest_stop"' in MAIN.read_text(encoding='utf-8') and (W/'placement.json').exists():
 print('Already placed. Preserve authored main transforms and original reference; use check_placed_positions.py after manual placement.')
 raise SystemExit(0)
probe=Path('D:/projects/sea-work/verification/20261107-133259-gift-kiosk-placement-probe-834547/project/outputs/sunroom-body-probe.json')
# Locate the output by the explicit probe label rather than assuming runner's project folder name.
matches=list((R.parent/'sea-work/verification').glob('*gift-kiosk-placement-probe-*/**/sunroom-body-probe.json'))
assert matches,'Run the isolated sunroom-body-probe first'
data=json.loads(max(matches,key=lambda p:p.stat().st_mtime).read_text(encoding='utf-8'))
boxes=[n['meta'] for n in data['nodes']]
lo=[min(b[i] for b in boxes) for i in range(3)];hi=[max(b[i]+b[i+3] for b in boxes) for i in range(3)]
centre=[(lo[0]+hi[0])/2,(lo[2]+hi[2])/2];offset=200/math.sqrt(2)
reference=[round(centre[0]+offset,6),1.12,round(centre[1]+offset,6)]
text=MAIN.read_text(encoding='utf-8')
backup=W/'before_import';backup.mkdir(exist_ok=True)
if not (backup/'main.tscn').exists():shutil.copy2(MAIN,backup/'main.tscn')
if not (backup/'zones.json').exists():shutil.copy2(ZONES,backup/'zones.json')
old=('[node name="floating_shop" parent="World/SeaStructures" unique_id=1826540312 instance=ExtResource("33_floating_shop")]')
if old in text:
 assert text.count(old)==1
 rest=old.replace('name="floating_shop"','name="floating_rest_stop"').replace('("33_floating_shop")','("40_rest_stop")')
 text=text.replace(old,rest)
 extra='[ext_resource type="PackedScene" path="res://scenes/facilities/floating_rest_stop.tscn" id="40_rest_stop"]\n'
 at=text.index('\n[sub_resource') if '\n[sub_resource' in text else text.index('\n[node')
 text=text[:at]+extra+text[at:]
 if re.search(r'load_steps=(\d+)',text):text=re.sub(r'load_steps=(\d+)',lambda m:'load_steps='+str(int(m[1])+1),text,count=1)
 target='[node name="floating_shop" parent="World/SeaStructures" instance=ExtResource("33_floating_shop")]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, '+', '.join(str(v) for v in reference)+')\n\n'
 anchor='[node name="rooftop_ranch" parent="World/SeaStructures"'
 idx=text.index(anchor);text=text[:idx]+target+text[idx:]
 MAIN.write_text(text,encoding='utf-8')
else:assert '[node name="floating_rest_stop"' in text,'Unexpected authored main; refuse regeneration'
zones=json.loads(ZONES.read_text(encoding='utf-8'));cfg=next(z for z in zones if z['id']=='sea_supply')
cfg.update(origin=reference,camera=[reference[0],1.42,reference[2]],hover=[reference[0],4.5,reference[2]],purpose='参考图圆角方形海上礼品商亭；初次参考位为阳光房当前主体中心东南200米，可走环廊/入口、单一泊位、补给入口及承载角色的竖向浮动。')
zone_text=ZONES.read_text(encoding='utf-8')
zone_block='\n'.join('  '+line for line in json.dumps(cfg,ensure_ascii=False,indent=2).splitlines())
zone_text,count=re.subn(r'  \{\n    "id": "sea_supply",.*?\n  \}',lambda _:zone_block,zone_text,count=1,flags=re.S)
assert count==1
ZONES.write_text(zone_text,encoding='utf-8')
ledger=R/'docs/features/world/placed_positions.md';lt=ledger.read_text(encoding='utf-8')
oldrow=next(line for line in lt.splitlines() if line.startswith('| `World/SeaStructures/floating_shop`'))
restrow=oldrow.replace('World/SeaStructures/floating_shop','World/SeaStructures/floating_rest_stop').replace('`sea_supply`','`retired_marine_rest_stop`')
restrow=restrow[:restrow.rfind('|')].rstrip()+' 2026-11-07 降级为旧驿站景观，原模型及用户完整变换保留；不再拥有sea_supply身份、泊位、行走面或补给交互。 |'
fmt='('+', '.join(str(v) for v in reference)+')'
newrow=f'| `World/SeaStructures/floating_shop` | `sea_supply` | `{fmt}` | `{fmt}` | 0 m | 等比（无缩放） | 2026-11-07 初次带入参考位：按本轮运行探针测得阳光房主体中心东南方向200米计算。正式TSCN拥有后续摆位；根保持静态参考，内部甲板与支撑竖向浮动。 |'
if 'World/SeaStructures/floating_rest_stop' not in lt:
 lt=lt.replace(oldrow,restrow+'\n'+newrow);ledger.write_text(lt,encoding='utf-8')
placement={'sunroom_body_centre_xz':centre,'southeast_offset_m':offset,'reference_position':reference,'initial_distance_m':math.dist(centre,[reference[0],reference[2]]),'position_authority':'main.tscn; reference coordinates are not future assertions','old_transform_preserved':True,'probe':str(max(matches,key=lambda p:p.stat().st_mtime))}
(W/'placement.json').write_text(json.dumps(placement,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(placement,ensure_ascii=False))
