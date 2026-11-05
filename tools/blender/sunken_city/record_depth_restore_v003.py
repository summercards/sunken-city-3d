"""Record the user-approved one-line depth restore; preserve all unrelated editor changes."""
import hashlib,json,re
from pathlib import Path
R=Path(__file__).resolve().parents[3];W=R.parent/'sea-work/sunken_city/v003/import';main=R/'godot/scenes/main.tscn'
before=(W/'main_before_depth_restore.tscn').read_bytes();after=main.read_bytes()
old=b'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 38.04888, 0)';new=b'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)'
assert before.count(old)==1 and before.replace(old,new)==after,'Restore changed more than authorized city root Y'
sha=lambda x:hashlib.sha256(x).hexdigest()
report={'passed':True,'user_confirmed':'恢复原水下深度（推荐）','scope':'Only SunkenCity root translation Y 38.04888 -> 0; all other latest editor bytes retained',
 'before_file':str(W/'main_before_depth_restore.tscn'),'before_sha256':sha(before),'after_file':str(main),'after_sha256':sha(after),'previous_registered_main_sha256':json.loads((W/'runtime_build.json').read_text(encoding='utf-8'))['main_sha256_after']}
(W/'depth_restore_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('DEPTH_RESTORE_EXACT_SINGLE_LINE',report['after_sha256'])
