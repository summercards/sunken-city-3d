"""Freeze the wider, pitched bridge revision and protect its source inputs."""
import hashlib,json,os,shutil
from pathlib import Path

root=Path(__file__).resolve().parents[3]
suite=root/'art_source/scenes/neon_garden_quarter'
source=suite/'v003'
work=Path(os.environ.get('SEA_WORK_ROOT',root.parent/'sea-work'))/'neon_garden_quarter/v003'
refs=source/'reference';refs.mkdir(parents=True,exist_ok=True)
(work/'renders').mkdir(parents=True,exist_ok=True)
for name,image in [('spacing','cda6c914-10c9-4eb4-b5d1-ee734cbca703'),('roof','095e08db-b0b6-426c-b4fe-efff2a9c1e64')]:
    shutil.copy2(Path(os.environ['TEMP'])/f'codex-clipboard-{image}.png',refs/f'{name}.png')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
plan=json.loads((suite/'v002/component_plan.json').read_text(encoding='utf8'))
plan.update(version='v003',requirement='SEA-ASSET-R46',reference='reference/roof.png',reference_sha256=sha(refs/'roof.png'),parent_source=(suite/'v002/neon_garden_quarter.blend').relative_to(root).as_posix(),parent_sha256=sha(suite/'v002/neon_garden_quarter.blend'))
plan['revision_contract'].update(right_shift_m=12,reference_spacing_sha256=sha(refs/'spacing.png'),bridge=dict(span_x=[-4.8,16.8],right_shift_m=12,depth_y=[-4.2,4.2],eaves_z=26.0,ridge_y=-.3,ridge_z=28.45,roof_depth_y=[-4.2,1.8],bridge_floor_z=25.8,unroofed_rear_passage_y=[1.8,4.2]),runtime=dict(offset_east_m=150,reference='sunroom body frozen XZ center',foundation_world_y=1.12))
for item in plan['components']:
    if item['key']=='roof_soil':item['name']='菜园双坡实体屋顶'
assert len(plan['components'])==50
for path,data in [(source/'component_plan.json',plan),(work/'v002_protection.json',{p.relative_to(root).as_posix():sha(p) for p in (suite/'v002').rglob('*') if p.is_file()})]:
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
