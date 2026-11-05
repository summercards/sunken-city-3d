"""Import five packed modules by reusing verified GLBs and transplanting existing scene transforms."""
import re
from decimal import Decimal
from pathlib import Path
from plan_v004 import ROOT, OLD, NEW, WORK, ASSEMBLY, read, sha, write

plan=read(NEW/'component_plan.json')
catalog=read(NEW/'module_catalog.json')['modules']
source_check=read(WORK/'source_verification.json')
assert source_check['passed'] and sha(NEW/'neon_garden_quarter.blend')==source_check['master_sha256']
export=read(OLD/'export/v003/export_manifest.json')
registry=read(ROOT/'assets/registry/ledger_index.json')
inventory={r['path']:r['sha256'] for r in read(ROOT/registry['runtime_inventory'])['resources']}
for part in export['components']:
    for field,digest in [('source',part['source_sha256_after']),('optimized_source',part['optimized_sha256']),('glb',part['glb_sha256']),('prefab',inventory[part['prefab']])]:
        assert sha(ROOT/part[field])==digest,part[field]
    path=part['glb']+'.import';assert sha(ROOT/path)==inventory[path],path

before=WORK/'assembly_v003_before_split.tscn'
assert sha(before)==plan['parent_runtime_sha256']==sha(ASSEMBLY),'Existing runtime assembly changed; review before applying split.'
text=before.read_text(encoding='utf-8')
header,body=text.split('[node name="NeonGardenQuarter"',1)
layout,space=body.split('[node name="Blockers"',1)
space='[node name="Blockers"'+space
assert space.count('target_path = NodePath("../Visual/Foundation")')==1
groups=re.split(r'(?=^\[node )', '[node name="NeonGardenQuarter"'+layout, flags=re.MULTILINE)
root_node,visual,*children=[s for s in groups if s]
ext={match.group(1):match.group(0) for match in re.finditer(r'^\[ext_resource type="PackedScene"[^\r\n]* id="([^"]+)"\]$',header,re.MULTILINE)}
rows=read(OLD/'component_instances.json')['instances'];assert len(rows)==len(children)==506
members={key:[] for key in catalog}
for i,(row,child) in enumerate(zip(rows,children)):
    key=row['key']
    expected='Foundation' if key=='fractured_ground' else f'{key}_{i:03d}'
    node_header=f'[node name="{expected}" parent="Visual" instance=ExtResource("{key}")]'
    assert child.startswith(node_header),(expected,child)
    members[plan['ownership'][row['name']]].append((row,child))

def num(value):return format(value.normalize(),'f')

def source_offset(module):
    x,y,z=map(lambda v:Decimal(str(v)),module['anchor_blender'])
    return (x-6,z,1-y)

for key,module in catalog.items():
    offset=source_offset(module);children=[];refs=set()
    for row,child in members[key]:
        refs.add(row['key'])
        if row['key']=='fractured_ground':child=child.replace('name="Foundation"','name="GroundMesh"',1)
        child=child.replace('parent="Visual"','parent="."',1)
        transform=re.search(r'^transform = Transform3D\(([^)]*)\)$',child,re.MULTILINE)
        assert transform,row['name']
        fields=transform.group(1).split(', ')
        old=list(map(Decimal,fields[-3:]));local=[p-delta for p,delta in zip(old,offset)]
        assert [p+delta for p,delta in zip(local,offset)]==old
        new='transform = Transform3D('+', '.join(fields[:9]+list(map(num,local)))+')'
        child=child[:transform.start()]+new+child[transform.end():]
        children.append(child)
    path=f'godot/scenes/components/facilities/neon_garden_quarter/modules/{key}.tscn'
    out=ROOT/path;out.parent.mkdir(parents=True,exist_ok=True)
    content='[gd_scene format=3]\n\n'+'\n'.join(ext[ref] for ref in sorted(refs))+'\n\n'
    content+=f'[node name="{module["node"]}" type="Node3D"]\nmetadata/asset_id = "{module["asset_id"]}"\nmetadata/asset_version = "v004"\nmetadata/module_key = "{key}"\n\n'+''.join(children).rstrip()+'\n'
    if out.exists():assert out.read_text(encoding='utf-8')==content,f'Review existing edits in {out}'
    else:out.write_text(content,encoding='utf-8')
    module.update(prefab=path,prefab_sha256=sha(out),runtime_offset=[num(p) for p in offset])

new_header='\n'.join(line for line in header.rstrip().splitlines() if not line.startswith('[ext_resource type="PackedScene"'))+'\n'
for key,module in catalog.items():
    new_header+=f'[ext_resource type="PackedScene" path="res://{module["prefab"].removeprefix("godot/")}" id="module_{key}"]\n'
new_text=new_header+'\n'+root_node.replace('metadata/asset_version = "v003"','metadata/asset_version = "v004"')+visual
for key,module in catalog.items():
    new_text+=f'[node name="{module["node"]}" parent="Visual" instance=ExtResource("module_{key}")]\n'
    new_text+='position = Vector3('+', '.join(module['runtime_offset'])+')\n\n'
new_text+=space.replace('../Visual/Foundation','../Visual/Foundation/GroundMesh')
ASSEMBLY.write_text(new_text,encoding='utf-8')
write(NEW/'module_catalog.json',dict(version='v004',modules=catalog))
write(WORK/'import_verification.json',dict(passed=True,modules=len(catalog),reused_glbs=len(export['components']),source_optimized_and_runtime_hashes_verified=True,unchanged_leaf_placements=sum(len(group) for group in members.values()),assembly_sha256=sha(ASSEMBLY),parent_assembly_sha256=sha(before)))
print('NGQ v004: five PackedScenes, 506 exact placement replays, 50 unchanged GLBs')
