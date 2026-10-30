import json,hashlib,shutil
from pathlib import Path
R=Path('D:/projects/sea');old=R/'art_source/scenes/floating_shop/v001';D=old.parent/'v002';W=Path('D:/projects/sea-work/floating_shop/v002');W.mkdir(parents=True,exist_ok=True)
if D.exists():raise RuntimeError('v002 already exists; inspect before rewriting')
D.mkdir()
for n in ['reference.png','component_plan.json','catalog.json','component_instances.json']:shutil.copy2(old/n,D/n)
ref=Path('C:/Users/ZHUANG~1/AppData/Local/Temp/codex-clipboard-9c08bf1e-7ac7-4e08-8982-89f0159af8a4.png');shutil.copy2(ref,D/'revision_reference.png')
plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));plan['version']='v002';plan['status']='frozen_before_geometry';plan['revision_reference_sha256']=hashlib.sha256(ref.read_bytes()).hexdigest();plan['revision_from']='v001';plan['revision_request']='外环可站平台加宽至少两倍，正面护栏开可进入口子'
plan['dimension_contract'].update({'deck_diameter_m':18,'walkway_width_m':3.0,'walkway_width_ratio_to_v001':2.5,'railing_radius_m':8.8,'front_rail_opening_width_m':3.43,'front_entry_angle_degrees':0,'revision_note':'保持12m店体及高度，仅外环平台与边缘设施扩大；正面开口与店门对齐。'})
(D/'component_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(str(D))
