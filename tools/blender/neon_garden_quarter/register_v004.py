"""Record the five verified assemblies and advance only the quarter's current source."""
import json,re,shutil,sys
from pathlib import Path
from plan_v004 import ROOT, NEW, WORK, ASSEMBLY, sha, read, write

report_path=Path(sys.argv[1]).resolve()
tests=read(report_path)['results']
for name in ['neon-garden-quarter','visual-neon-garden-quarter','water-layer','minimum-loop']:
    assert tests[name]['passed'],tests[name]
source=read(WORK/'source_verification.json');runtime=read(WORK/'import_verification.json')
assert source['passed'] and runtime['passed'] and runtime['assembly_sha256']==sha(ASSEMBLY)
master=NEW/'neon_garden_quarter.blend';assert sha(master)==source['master_sha256']
plan=read(NEW/'component_plan.json');modules=read(NEW/'module_catalog.json')['modules']
for module in modules.values():
    assert sha(ROOT/module['source'])==module['source_sha256']
    assert sha(ROOT/module['prefab'])==module['prefab_sha256']

doc='docs/development/2026-11-05_neon_garden_quarter_v004.md'
registry=read(ROOT/'assets/registry/ledger_index.json');route=registry['domains']['scenes'];rows_key=route['asset_key']
ledger_path=ROOT/route['ledger'];baseline=ledger_path.read_bytes();ledger=json.loads(baseline)
by_id={row['asset_id']:row for row in ledger[rows_key]};assembly_id='SEA-SCENE-NGQ-ASSEMBLY'
stage='runtime_component_verified_provenance_pending'
evidence=[doc,str(report_path),str(WORK/'source_verification.json'),str(WORK/'import_verification.json')]
updates={}
for key,module in modules.items():
    asset_id=module['asset_id']
    updates[asset_id]=dict(asset_id=asset_id,name=module['label'],domain='scenes',suite=plan['suite'],scope='scene_local',category='building_module',building_class='above_water',water_layer='surface',water_layer_role='part',version='v004',stage=stage,license='pending_user_supplied_reference',consumer_features=['SEA-ASSET','SEA-WORLD'],source=module['source'],source_sha256=module['source_sha256'],manifest=module['manifest'],runtime_path=module['prefab'],runtime_sha256=module['prefab_sha256'],prefab=module['prefab'],dependencies=module['dependencies'],collection=module['collection'],origin='bottom_center',front_axis='-Y',bounds=module['local_bounds'],instance_count=module['instance_count'],verification=evidence)
    write(ROOT/module['manifest'],dict(updates[asset_id],asset_ledger=route['ledger']+'#'+asset_id,palette=plan['palette'],loaded_branch=plan['branch'],collision_responsibility='quarter scene owns gameplay projections',geometry_reuse='v003 optimized leaf components, source and GLB hashes verified'))

previous=by_id[assembly_id]
history=list(previous.get('previous_sources',[]))
if previous['version']=='v003':
    assert previous['source_sha256']==plan['parent_sha256']
    assert previous['runtime_sha256']==runtime['parent_assembly_sha256']
    history.append({key:previous[key] for key in ['version','source','source_sha256','manifest','runtime_sha256']})
else:
    assert previous['version']=='v004' and previous['source_sha256']==source['master_sha256']
    assert history[-1]['source_sha256']==plan['parent_sha256']
assembly=dict(previous,version='v004',source=master.relative_to(ROOT).as_posix(),source_sha256=sha(master),manifest=(NEW/'asset_manifest.json').relative_to(ROOT).as_posix(),runtime_sha256=sha(ASSEMBLY),component_count=5,leaf_component_count=50,instance_count=506,module_instance_count=5,module_asset_ids=list(updates),previous_sources=history,verification=evidence)
main=(ROOT/'godot/scenes/main.tscn').read_text(encoding='utf-8')
node=re.search(r'^\[node name="neon_garden_quarter" parent="World/SeaStructures"[^\n]*\]\n([^\n]+)',main,re.MULTILINE)[1]
authored_anchor=list(map(float,node.split('(',1)[1].rstrip(')').split(', ')[-3:]))
assembly.update(authored_world_anchor=authored_anchor,landing='surface_fixture_verified_live_street_submerged' if authored_anchor[1]<0 else 'street_landing_verified')
updates[assembly_id]=assembly
write(ROOT/assembly['manifest'],dict(assembly,asset_ledger=route['ledger']+'#'+assembly_id,component_plan='component_plan.json',module_catalog='module_catalog.json',reference_sha256=plan['reference_sha256'],pending=['upper floors and roof gameplay access','reference commercial rights']))
for key in (set(updates)&by_id.keys())-{assembly_id}:
    assert by_id[key]['source_sha256']==updates[key]['source_sha256'] and by_id[key]['suite']==plan['suite'],'New IDs must not replace other scene rows.'
for domain,domain_route in registry['domains'].items():
    if domain!='scenes':assert not set(updates)&{r['asset_id'] for r in read(ROOT/domain_route['ledger'])[domain_route['asset_key']]}
ledger[rows_key]=[updates.get(row['asset_id'],row) for row in ledger[rows_key]]+[row for key,row in updates.items() if key not in by_id]
assert ledger_path.read_bytes()==baseline,'Concurrent ledger edit'
write(ledger_path,ledger)

index_path=ROOT/'assets/registry/current_source_index.json';index=read(index_path)
index['sources']=[{key:row[key] for key in ['asset_id','source','source_sha256','manifest']} for item in registry['domains'].values() for row in read(ROOT/item['ledger'])[item['asset_key']]]
write(index_path,index)
view_path=ROOT/route['building_views']['above_water'];view=read(view_path)
view['asset_ids']=[row['asset_id'] for row in ledger[rows_key] if row.get('building_class')=='above_water']
write(view_path,view)

inventory_path=ROOT/registry['runtime_inventory'];inventory=read(inventory_path)
runtime_assets={row['runtime_path']:row for row in updates.values()}
inventory['resources']=[row for row in inventory['resources'] if row['path'] not in runtime_assets]
for path,row in runtime_assets.items():
    inventory['resources'].append(dict(path=path,bytes=(ROOT/path).stat().st_size,sha256=row['runtime_sha256'],asset_id=row['asset_id'],status=stage))
inventory['resources'].sort(key=lambda row:row['path']);write(inventory_path,inventory)

for name in ['overview','roof','rear']:
    shutil.copy2(report_path.parent/'project/outputs'/f'neon_garden_{name}.png',WORK/f'godot_{name}.png')
write(WORK/'registration_report.json',dict(passed=True,new_modules=5,updated_assembly=assembly_id,runtime_verification=str(report_path),unchanged_leaf_assets=50))

def append(relative,title,body):
    path=ROOT/'docs/features'/f'{relative}.md';before=path.read_bytes()
    if title.encode() in before:return
    with path.open('ab') as stream:stream.write(f'\n\n## {title}\n\n{body}\n'.encode('utf-8'))
    assert path.read_bytes().startswith(before)

title='2026-11-05 霓虹花园街区五组件拆分'
link='[交付与验收](../../development/2026-11-05_neon_garden_quarter_v004.md)'
append('asset/spec',title,'| 条款 ID | 规则与验收 |\n|---|---|\n| SEA-ASSET-R48 | 四个红框分别对应左楼、后楼、右楼、双坡菜园桥。街道地面作为第五个组件独立管理。各组件使用底心原点，独立 Blender 源包和稳定 Godot PackedScene，复用通过 02b 验收的 50 个下层资产，保留结构、植物、设施与招牌的子层。 |')
append('asset/ledger',title,f'| 条款 ID | 当前实施 | 证据 |\n|---|---|---|\n| SEA-ASSET-R48 | v004 五件独立 Blend 和 PackedScene 已接入。506 个叶实例保留原姿态并唯一归属。场景分账新增五个 AssetID，原总成升级到 v004。 | {link} |')
append('world/spec',title,'| 条款 ID | 规则与验收 |\n|---|---|\n| SEA-WORLD-R19 | 正式街区总成引用五个稳定模块。保留 R18 的坐标、泊位与街口步行契约。水面阻挡仍从街道模块的铺地网格派生。运行回归验证五个可独立加载的模块、完整装配、航线、上岸和实景。 |')
append('world/ledger',title,f'| 条款 ID | 当前实施 | 证据 |\n|---|---|---|\n| SEA-WORLD-R19 | 五件模块已经在正式街区总成装配。当前工作区主场景街区已下沉，实拍保留现有标高，水下街道没有隐形水面阻挡。恢复设计水线的隔离工况中，原街道基础阻挡、泊位、上岸和步行通过。水层及最小流程专项通过。 | {link} |')

details='\n'.join(f'| {m["label"]} | `{m["asset_id"]}` | {m["instance_count"]} | `{Path(m["prefab"]).stem}.tscn` |' for m in modules.values())
(ROOT/doc).write_text(f'''# {title}

对应 SEA-ASSET-R48 和 SEA-WORLD-R19。图中四个红框为三栋楼和菜园桥，另按要求将街道地面分出。五个模块在 Blender 可独立打开，在 Godot 可独立实例化。

| 组件 | AssetID | 子实例数 | PackedScene |
|---|---|---:|---|
{details}

三栋楼各含屋顶、门窗、挂在楼上的设施与招牌。桥包含双坡屋顶、菜床、作物与桥头附属件。街道包含铺地、路灯、碎石、落地灯笼和共用跨街线缆。独立包以几何底心为原点，内部仍能单独编辑各下层件。源包和模块清单在 `art_source/scenes/neon_garden_quarter/v004/`。Godot 模块在 `godot/scenes/components/facilities/neon_garden_quarter/modules/`。

本轮是既有几何的分组导入。逐件核对了 v003 的 50 个制作源、50 个独立优化源、50 个 GLB、导入配置和原 PackedScene 哈希。运行模块直接引用这些资产。506 个 Blender 变换经重开重放，506 个 Godot 子件的平移经局部偏移精确重建，旋转缩放原值保留。五个模块是正式总成 `neon_garden_quarter.tscn` 的直接视觉实例。

主场景的 XZ 仍是太阳房正东 150 米。工作期间现有主场景标高改为 Y=-21.726082，本轮保留该编辑。街口活动面与泊位仍由总成维护，阻挡目标为 `Visual/Foundation/GroundMesh`。当前实景验收覆盖五件装配、海报和色板、航线、下沉街道零水面阻挡与三张游戏实拍。原街口阻挡、泊位、角色上岸与步行在 Y=1.12 的隔离工况另测，当前主场景街道上岸因下沉未通过。报告为 `{report_path.as_posix()}`，制作和实拍证据在 `{WORK.as_posix()}`。
''',encoding='utf-8')
print('NGQ v004: registered five new module IDs and updated the assembly')
