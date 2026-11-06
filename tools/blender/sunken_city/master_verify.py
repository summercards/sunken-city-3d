"""Reopen the saved final master in an isolated background Blender and audit true stored data."""
import bpy,hashlib,importlib.util,json,math,os,runpy,sys
from pathlib import Path
R=Path(__file__).resolve().parents[3];VERSION=os.environ.get('SEA_SUNKEN_VERSION','v001');D=R/'art_source/scenes/sunken_city'/VERSION;W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'sunken_city'/VERSION
MAIN=D/f'sunken_city_{VERSION}.blend'
assert bpy.app.background
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
before=sha(MAIN);P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
bpy.ops.wm.open_mainfile(filepath=str(MAIN),load_ui=False,use_scripts=False)
S=bpy.data.scenes['沉没旧城_完整参考布局_'+VERSION]
if bpy.context.window:bpy.context.window.scene=S
runpy.run_path(str(Path(__file__).with_name('probe.py')),run_name='__main__')
report=json.loads((W/'probe_report.json').read_text(encoding='utf-8'))
assert report['passed'],report['errors']
if VERSION=='v002':
    runpy.run_path(str(Path(__file__).with_name('verify_detail_v002.py')),run_name='__main__')
if VERSION=='v005':
    runpy.run_path(str(Path(__file__).with_name('check_terrain_v005.py')),run_name='__main__')
elif VERSION in {'v003','v004'}:
    runpy.run_path(str(Path(__file__).with_name('check_terrain_v003.py')),run_name='__main__')
seams=json.loads((W/'floor_seams.json').read_text(encoding='utf-8'));assert seams['passed'] and seams['tiles']==100 and seams['shared_edges']==180
# Full source mesh validation in the master scene, including unused definition types.
MASTER=bpy.data.scenes['01_组件母版_独立编辑']
if bpy.context.window:bpy.context.window.scene=MASTER
vpath=Path.home()/'.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py'
assert vpath.is_file()
# Reuse the exact sea 8x8 audit adapter from package checker; every remaining installed check unchanged.
spec=importlib.util.spec_from_file_location('sunken_package',Path(__file__).with_name('package_verify.py'));pkg=importlib.util.module_from_spec(spec);spec.loader.exec_module(pkg)
spec2=importlib.util.spec_from_file_location('installed_validator',vpath);validator=importlib.util.module_from_spec(spec2);spec2.loader.exec_module(validator)
validator.audit_palette_uv=pkg.audit_grid8
sys.argv=['validator','--','--all-meshes','--max-materials','3','--shared-palette',str(R/P['palette']),'--json',str(W/'master_skill_report.json')]
try:validator.main()
except SystemExit as e:assert e.code==0,'Master generic validator failed'
assert sha(MAIN)==before
report.update(suite='sunken_city',source=str(MAIN),file=str(MAIN),source_sha256=before,palette_sha256=sha(R/P['palette']),status='passed',exit_code=0,
    reopened_from_disk=True,source_unchanged_on_reopen=True,
    checks={'geometry_uv_spatial_probe':{'passed':True,'assertion_count':report.pop('checks')},'floor_seams':{'passed':True,'tiles':100,'shared_edges':180},'master_generic_validator':{'passed':True},'source_hash_unchanged':{'passed':True}})
(W/'source_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('MASTER_REOPEN_PASS',before,report['components'],report['instances'])
