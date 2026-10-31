"""Repair only this task's misrouted package outputs and restore clean v001 files."""
import json,shutil,subprocess
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';old=(D.parent/'v001/component_packages').resolve();W=Path('D:/projects/sea-work/floating_shop/v003/misrouted_candidates').resolve();W.mkdir(parents=True,exist_ok=True)
changed=['awning_blue','awning_white','controller','deck','roof','under_brace'];added=['bench','bollard','cargo_crate','corner_post','plinth','rail_straight','roof_vent','sign_panel','wall_panel']
paths=[]
for k in changed:
 for file in [k+'.blend','asset_manifest.json']:paths.append((old/k/file).relative_to(R).as_posix())
subprocess.run(['git','restore','--source=HEAD','--worktree','--',*paths],cwd=R,check=True)
for k in added:
 src=(old/k).resolve();target=(W/k).resolve();assert src.is_relative_to(old) and target.is_relative_to(W) and not target.exists()
 if src.exists():shutil.move(str(src),str(target))
p=D/'catalog.json';cat=json.loads(p.read_text(encoding='utf-8'))
for e in cat['components']:e['component_source']=f"art_source/scenes/floating_shop/v003/component_packages/{e['key']}/{e['key']}.blend"
p.write_text(json.dumps(cat,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Restored v001 files; new components will be saved only to v003')
