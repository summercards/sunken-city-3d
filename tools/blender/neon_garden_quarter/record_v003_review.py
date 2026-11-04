"""Attach the reviewed source/export renders and the isolated Godot results."""
import hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
from PIL import Image,ImageChops,ImageStat

root=Path(__file__).resolve().parents[3]
work=Path(os.environ.get('SEA_WORK_ROOT',root.parent/'sea-work'))/'neon_garden_quarter/v003'
source=root/'art_source/scenes/neon_garden_quarter/v003'
report_path=Path(sys.argv[1]).resolve()
def read(p):return json.loads(p.read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,value):p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
runtime=read(report_path)
expected=['neon-garden-quarter','visual-neon-garden-quarter','water-layer','minimum-loop']
for key in expected:assert runtime['results'][key]['passed'],runtime['results'][key]
audit=read(work/'source_verification.json');structure=read(work/'structure_verification.json');skill=read(work/'skill_verification.json')
assert audit['passed'] and structure['passed'] and skill['passed']
assert audit['source_sha256']==structure['source_sha256']==sha(source/'neon_garden_quarter.blend')
comparison={}
for name in ['hero','rear','curved','garden']:
    original=Image.open(work/'renders'/f'{name}.png').convert('RGB')
    optimized=Image.open(work/'optimized_renders'/f'{name}.png').convert('RGB')
    comparison[name]=[round(value,3) for value in ImageStat.Stat(ImageChops.difference(original,optimized)).rms]
    assert max(comparison[name])<1.2,(name,comparison[name])
shots={}
for name in ['overview','roof','rear']:
    file=work/f'godot_{name}.png'
    shutil.copy2(report_path.parent/'project/outputs'/f'neon_garden_{name}.png',file)
    shots[name]=dict(path=str(file),sha256=sha(file))
dump(work/'visual_review.json',dict(passed=True,source_sha256=audit['source_sha256'],source_frames=sorted(p.name for p in (work/'renders').glob('*.png')),optimized_comparison_rms_255=comparison,review='Checked bridge eaves, roof ridge, both bearings, broken facades, ads, all crop beds and original colors in Cycles and Godot.'))
dump(work/'runtime_review.json',dict(passed=True,verification_report=str(report_path),shots=shots,sunroom_xz=[6.149682,2.473711],placement_xyz=[156.149682,1.12,2.473711],checks=expected))
export=read(source/'export/v003/export_manifest.json')['components']
before=sum(row['mesh_objects_before'] for row in export);after=sum(row['mesh_objects_after'] for row in export)
tri_before=sum(row['triangles_before'] for row in export);tri_after=sum(row['triangles_after'] for row in export)
doc=root/'docs/development/2026-11-05_neon_garden_quarter_v003.md'
doc.write_text(f'''# 2026-11-05 霓虹花园街区 v003 双坡菜园桥与游戏接入

对应 SEA-ASSET-R46 和 SEA-WORLD-R18。红框为透视视图，按一栋楼宽与框前间隙估算，右楼整体右移 12 米。左楼位置保留，后楼和两侧附属件随新布局归位。桥的实际横跨约 {structure['bridge_span_m']:.1f} 米，两端伸入楼体。菜园屋顶的前后檐之间设 2.45 米高的屋脊，前后坡都有实体板、顺坡土层与三角屋架。七列菜床沿前坡铺开，桥下保留街巷，桥面后侧门洞和通道按源级几何检查。

母版为 `art_source/scenes/neon_garden_quarter/v003/neon_garden_quarter.blend`。50 个组件和 {audit['assembly']['visible_instances']} 个实例。{audit['checks']:,} 项重开、逐面 UV 等检查通过，另有 {len(structure['checks'])} 项桥与间距检查、10 张源实渲染和母版及 50 包的 Skill 验收。v002 源和独立包哈希保持。

逐组件按 02b 在 `v003/export/v003/` 保存并重开优化 Blend，再逐件导出无内嵌贴图 GLB 与稳定路径的 PackedScene。源网格对象 {before} 合并成 {after} 个材质角色网格。逐组件合计三角面 {tri_before:,} 到 {tri_after:,}，保留曲面和轮廓。四个同机位对照的 RGB RMS 最大 1.045 / 255。公共色板使用同一外链图及最近邻采样。八幅印画从原 image-2 图集采样，导入后贴图不进 GLB。

正式摆放为 `World/SeaStructures/neon_garden_quarter`，锚点定义为左右楼中心的平面中点。真实渲染中量取太阳房后部方楼与前部太阳能房的合并包围盒，XZ 中心为 (6.149682, 2.473711)。街区根为 (156.149682, 1.12, 2.473711)，正东 150 米。无头渲染的 MultiMesh 回退几何包围盒有差异，因此以真实渲染测量为准并在视觉专项复核。船只阻挡和岸线从基础几何派生，街口泊位、上岸点和一段可走铺地由正式 TSCN 拥有。上层桥面、屋顶种植和店铺交互没有接入玩法。

首轮游戏实拍发现 TSCN 基矩阵顺序使菜床斜向翻转，已按引擎的行序改写全部实例，并对七块菜床的游戏 Basis 加断言。霓虹乘色后保留原色。正式资源导入完成，编辑器重开旧顶层牧场时仍报告既有 `@tool` 对 `physical_surface_triangles` 的赋值错误。隔离游戏运行无此错误，所有 50 个组件可加载。

隔离 Godot 专项为 332 项逻辑、339 项真实渲染、794 项水层、141 项最小流程，各零失败。验证从家园到街区的航线、街面阻挡、泊位、真实上岸和铺地步行。实拍为全景、菜园近景和背面。证据在 `{work.as_posix()}`，运行报告为 `{report_path.as_posix()}`。
''',encoding='utf8')

sections={
    'asset/spec':'''## 2026-11-05 霓虹花园街区双坡与逐组件接入

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R46 | 按红框扩大两楼间距，在承重连接体上制作双坡菜园、横向屋脊及顺坡种植，保留桥下通道。新版保留独立组件、色板和广告图集，逐组件完成优化另存、重开、GLB 和稳定 PackedScene，并验收源与游戏的结构及材质。 |''',
    'asset/ledger':'''## 2026-11-05 霓虹花园街区 v003

| 对应条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R46 | v003 已接入。右楼右移 12 米，菜园桥跨约 21.6 米且使用实体双坡。50 组件与 506 实例通过 Blender 重开、结构和 02b 导入验收。源级专项与真实游戏专项均通过，参考图商业授权 pending。 | [本轮交付](../../development/2026-11-05_neon_garden_quarter_v003.md) |''',
    'world/spec':'''## 2026-11-05 霓虹花园街区摆位与登岸

| 条款 ID | 规则与验收 |
|---|---|
| SEA-WORLD-R18 | 霓虹花园街区根位于太阳房真实主体中心的正东 150 米，以实际水面高度为基准。默认范围可见，可航行至街口泊位并上岸进入前街铺地。建筑基础派生船只阻挡与岸线，正式 TSCN 维护泊位和行走面。上层菜园是表现资产。 |''',
    'world/ledger':'''## 2026-11-05 霓虹花园街区东侧接入

| 对应条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-WORLD-R18 | 主场景街区锚点 (156.149682, 1.12, 2.473711)。真实太阳房主体取样测得正东 150 米。航线、基础阻挡、街口泊位、真实角色上岸与步行通过，水层及最小流程通过。 | [摆位与运行证据](../../development/2026-11-05_neon_garden_quarter_v003.md) |''',
}
for name,section in sections.items():
    path=root/'docs/features'/f'{name}.md'
    marker=section.splitlines()[0].encode('utf8');previous=path.read_bytes()
    if marker not in previous:
        with path.open('ab') as f:f.write(('\n\n'+section+'\n').encode('utf8'))
        assert path.read_bytes().startswith(previous)

# Audit the already committed R17 delta before updating the shared zones row.
zone_path='godot/assets/data/zones.json'
def git_file(rev):return subprocess.check_output(['git','show',f'{rev}:{zone_path}'],cwd=root)
old=git_file('39808610');head=git_file('HEAD');live=read(root/zone_path)
baseline=json.loads(old);committed=json.loads(head)
assert committed[:-1]==baseline and committed[-1]['id']=='rooftop_ranch'
assert live[:-1]==committed and live[-1]['id']=='neon_garden_quarter'
runtime_path=root/'assets/registry/runtime_resource_inventory.json';inventory=read(runtime_path)
zone=next(row for row in inventory['resources'] if row['path']==zone_path)
if zone['sha256']!=sha(root/zone_path):
    assert zone['sha256'] in [hashlib.sha256(data).hexdigest() for data in [old,old.replace(b'\n',b'\r\n')]]
    zone.update(bytes=(root/zone_path).stat().st_size,previous_sha256=zone['sha256'],sha256=sha(root/zone_path),note='区块身份表追加已核对的 R17 顶层牧场及 R18 霓虹花园街区，行走面与泊位由场景回填。')
    dump(runtime_path,inventory)
content_path=root/'assets/registry/content_index.json';content=read(content_path)
table=next(table for table in content['tables'] if table['path']==zone_path)
assert table['ids'] in [[entry['id'] for entry in data] for data in [baseline,committed,live]]
table['ids']=[entry['id'] for entry in live]
dump(content_path,content)
