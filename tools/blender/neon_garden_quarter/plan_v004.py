"""Freeze the five module boundaries and the ownership of every v003 placement."""
import hashlib,json,os,shutil
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SUITE=ROOT/'art_source/scenes/neon_garden_quarter'
OLD=SUITE/'v003';NEW=SUITE/'v004'
WORK=Path(os.environ.get('SEA_WORK_ROOT',ROOT.parent/'sea-work'))/'neon_garden_quarter/v004'
ASSEMBLY=ROOT/'godot/scenes/facilities/neon_garden_quarter.tscn'
MODULES={
    'left_building': ('LeftBuilding','左楼','LEFT-BUILDING'),
    'rear_building': ('RearBuilding','后楼','REAR-BUILDING'),
    'right_building': ('RightBuilding','右楼','RIGHT-BUILDING'),
    'garden_bridge': ('GardenBridge','双坡菜园桥','GARDEN-BRIDGE'),
    'street_ground': ('Foundation','街道地面','STREET-GROUND'),
}

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def module_for(row):
    key=row['key'];name=row['name'];x,y,z=row['location'];host=row['host'] or ''
    if host.startswith('garden_bridge') or key in {'garden_bridge','roof_soil','crop_bed','cabbage','herb','tomato','trellis'}:
        return 'garden_bridge'
    if name in {'vine','vine.001','flowers.004','flowers.005'}:
        return 'garden_bridge'
    if key in {'fractured_ground','lantern','street_lamp','utility_cable'} or name.startswith('坠落'):
        return 'street_ground'
    if z<1 and key in {'rubble','grass','broadleaf'}:
        return 'street_ground'
    if host.startswith('back') or (y>=9 and 0<x<12):
        return 'rear_building'
    if host.startswith('right') or x>=13:
        return 'right_building'
    if host.startswith('left') or x<0:
        return 'left_building'
    raise ValueError(f'Placement needs explicit ownership: {row}')

if __name__=='__main__':
    refs=NEW/'reference';refs.mkdir(parents=True,exist_ok=True);WORK.mkdir(parents=True,exist_ok=True)
    reference=refs/'module_boundaries.png'
    shutil.copy2(Path(os.environ['TEMP'])/'codex-clipboard-86444909-7562-4205-bfaa-87767b87ef17.png',reference)
    instances=read(OLD/'component_instances.json')['instances']
    ownership={row['name']:module_for(row) for row in instances}
    assert len(ownership)==len(instances)==506
    work_snapshot=WORK/'assembly_v003_before_split.tscn'
    if not work_snapshot.exists():shutil.copyfile(ASSEMBLY,work_snapshot)
    source=OLD/'neon_garden_quarter.blend';parent_plan=read(OLD/'component_plan.json')
    plan=dict(version='v004',suite='neon_garden_quarter',building_class='above_water',branch=parent_plan['branch'],reference=reference.relative_to(NEW).as_posix(),reference_sha256=sha(reference),parent_source=source.relative_to(ROOT).as_posix(),parent_sha256=sha(source),parent_runtime_sha256=sha(work_snapshot),palette=parent_plan['palette'],poster_source=parent_plan['poster_source'],ownership=ownership,modules={key:dict(node=node,label=label,asset_id='SEA-SCENE-NGQ-'+suffix,instance_count=Counter(ownership.values())[key]) for key,(node,label,suffix) in MODULES.items()})
    write(NEW/'component_plan.json',plan)
    print('NGQ v004 frozen ownership:',Counter(ownership.values()))
