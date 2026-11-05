"""Freeze one global height cap and archive the complete live v003 runtime, before edits."""
import copy,hashlib,json,zipfile
from pathlib import Path
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/sunken_city/v003';D=OLD.parent/'v004';W=R.parent/'sea-work/sunken_city/v004'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert D.is_dir() and W.is_dir()
assert not (D/'component_plan.json').exists(),'Already frozen; inspect before restarting'
cat=json.loads((OLD/'component_catalog.json').read_text(encoding='utf-8'))['components'];p=json.loads((OLD/'component_plan.json').read_text(encoding='utf-8'))
hi=max(c['bounds_size_m'][2] for c in cat if c['category']=='architecture');cap=hi/4
paths=[R/'godot/scenes/main.tscn',R/'godot/scenes/world/sunken_city.tscn',R/'godot/assets/models/scenery/sunken_city/runtime_manifest.json']
paths+=list((R/'godot/assets/models/scenery/sunken_city').rglob('*.glb'))+list((R/'godot/assets/models/scenery/sunken_city').rglob('*.import'))+list((R/'godot/scenes/components/scenery/sunken_city').glob('*.tscn'))+list((R/'godot/assets/materials/sunken_city').glob('*.tres'))
paths+=list((R/'godot/assets/materials').glob('water*.tres'))+list((R/'godot/shaders').glob('water*.gdshader'))
archive=OLD/'export/v003/runtime_preserved_before_v004.zip';assert not archive.exists()
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=3) as z:
    for path in paths:z.write(path,path.relative_to(R).as_posix())
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
protected={x.relative_to(R).as_posix():sha(x) for x in paths if x.name.startswith('water')}
sourcepaths=[OLD/'sunken_city_v003.blend',OLD/'component_catalog.json',OLD/'component_plan.json']+[R/c['component_blend'] for c in cat]
protected.update({x.relative_to(R).as_posix():sha(x) for x in sourcepaths})
contract=dict(source_max_height_m=hi,height_cap_m=cap,rule='global_max_div4_cap',below_cap_unchanged=True,method='remove complete storeys; keep normal facade dimensions; section fractured high remnants only',source_version='v003',scope='all architecture component heights including rooftop equipment; horizontal wreck orientation retained')
p=copy.deepcopy(p);p.update(version='v004',status='frozen_before_geometry',revision='v004_global_height_cap_and_shallower_placement',previous_source='art_source/scenes/sunken_city/v003/sunken_city_v003.blend',previous_source_sha256=sha(OLD/'sunken_city_v003.blend'),height_cap_contract=contract)
p['scope_lock']=dict(geometry_unchanged_keys=[c['key'] for c in cat if c['category']!='architecture' or c['bounds_size_m'][2]<=cap],short_architecture_keys=[c['key'] for c in cat if c['category']=='architecture' and c['bounds_size_m'][2]<=cap],changed_keys=[c['key'] for c in cat if c['category']=='architecture' and c['bounds_size_m'][2]>cap],terrain_and_rail='geometry and local layout locked; root uniform translation only',archive=archive.relative_to(R).as_posix())
assert len(p['components'])==50
for c in p['components']:c['version']='v004'
dump(D/'component_plan.json',p)
dump(W/'scope_lock.json',dict(passed=True,protected_sources=protected,runtime_before={x.relative_to(R).as_posix():sha(x) for x in paths},archive=archive.relative_to(R).as_posix(),archive_sha256=sha(archive),height_cap_contract=contract))
(W/'import/main_before_v004.tscn').write_bytes((R/'godot/scenes/main.tscn').read_bytes())
(W/'import/assembly_before_v004.tscn').write_bytes((R/'godot/scenes/world/sunken_city.tscn').read_bytes())
print('V004_FROZEN',hi,cap,p['scope_lock']['short_architecture_keys'],'archive',sha(archive))
