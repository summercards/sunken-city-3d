"""Record the visual review of the final Blender renders and append project records."""
import hashlib,json,os
from pathlib import Path

root=Path(__file__).resolve().parents[3]
source=root/'art_source/scenes/neon_garden_quarter/v002'
work=Path(os.environ.get('SEA_WORK_ROOT',root.parent/'sea-work'))/'neon_garden_quarter/v002'
audit=json.loads((work/'source_verification.json').read_text(encoding='utf8'))
structural=json.loads((work/'structure_verification.json').read_text(encoding='utf8'))
skill=json.loads((work/'skill_verification.json').read_text(encoding='utf8'))
assert audit['passed'] and structural['passed'] and skill['passed']
assert audit['source_sha256']==structural['source_sha256']
names='hero reference garden top rear signs architecture curved bridge ground'.split()
renders={name:hashlib.sha256((work/'renders'/f'{name}.png').read_bytes()).hexdigest() for name in names}
review=dict(passed=True,reviewer='Codex inspection of Blender Cycles images',source_sha256=audit['source_sha256'],renders=renders,observations=['横跨街巷的菜园与粗梁在参考镜头和近景均可读','右楼从地坪、七层楼板到女儿墙共用同一弧角轮廓','街面可辨认裂开的铺板、下层基层和坠落灯笼','广告牌按店面、墙体、桥承台归位，图案缺角与厚背板缺口一致','剖开墙角可看到后方楼板及少量断筋','背面保有完整体量、服务设施与室外楼梯'])
(work/'visual_review.json').write_text(json.dumps(review,ensure_ascii=False,indent=2)+'\n',encoding='utf8')

doc=root/'docs/development/2026-11-05_neon_garden_quarter_v002.md'
if not doc.exists():
    doc.write_text(f'''# 2026-11-05 霓虹花园街区 v002

对应 SEA-ASSET-R45，衔接 R44 的 Blender 源级制作。参考图一用于判断菜园桥与街道的关系，图二用于识别旧弧窗构造的问题。两张反馈图和哈希记录在 v002 源目录及组件计划中。源级分类为 `above_water`。

原来位于后楼屋顶的菜园移至两楼间的 **{structural['bridge_span_m']:.1f} 米实体连接桥**。桥有 0.2 米板、前后承重边梁、次梁和两端承台。两端与同层楼板相接，开门洞并在菜畦后留横向通道。街道继续从桥下穿过。

右楼采用 **4 米半径的转角**，并把该轮廓延续到基坪、各层墙与楼板、弧形窗带、屋顶和女儿墙。弧段接入建筑的直立面。右楼的弧面炭火广告按墙体圆心制作实体背壳，保留倾斜与下边大缺角。

左楼切掉一整处转角墙体与楼板边，右楼移除多层的部分窗墙及梁段，保留少量断柱、短筋和露出的楼板。地面沿各楼轮廓收边，裂开的铺装下有基层。五盏灯笼摔裂、熄灭后侧倒，按实际铺装起伏放置。{structural['mounted_signs']} 块悬挂招牌重新按宿主定位并配挂架，另有一块落地。复用原有 image-2 图集与四个色板材质角色。

母版 `art_source/scenes/neon_garden_quarter/v002/neon_garden_quarter.blend`。共 50 个独立组件包、{audit['assembly']['visible_instances']} 个实例、{audit['assembly']['triangles']:,} 展开三角面。母版和全部独立包共 {audit['checks']:,} 项检查零失败，{audit['source_palette_faces']:,} 个母版面的 PaletteUV 已逐面核验。Skill 检查覆盖母版与 50 个组件包。另有 {len(structural['checks'])} 项结构断言和 10 张 Cycles 渲染目视验收。证据在 `{work.as_posix()}`。

当前账本维护 51 条 v002 源记录，包括总成和 50 个组件。旧墙面裂痕贴件、外挂弧窗和外挂弧阳台三条标为历史组件。原图集继续使用其稳定 AssetID，v001 磁盘文件逐个验证哈希。正式运行接入、碰撞、导航、泊位及参考图商业授权为 pending。
''',encoding='utf8')

spec='''

## 2026-11-05 霓虹花园街区 v002 结构修订

| 条款 ID | 规则与验收 |
|---|---|
| SEA-ASSET-R45 | 按两张反馈图将菜园移至两楼之间的承重连接桥，核对两端承台、同层门洞、桥面通道及下方街巷。右楼以同一弧角贯通地坪、实体墙、七层楼板、玻璃、屋顶和女儿墙，原外挂弧件退役。招牌按店面、墙和桥承台归位，使用实体挂架、完整倾斜变换和可见缺角。建筑采用实际缺失的墙、梁和楼板表现较重破损，地面沿建筑轮廓收边并铺设大块裂板，灯笼破损熄灭并接触地面。保留 R44 的水上分类、公共色板、image-2 图集和植物分离。独立源包重开并检查结构与真实渲染后登记。 |
'''
ledger=f'''

## 2026-11-05 霓虹花园街区 v002 结构返工

| 对应设计条款 | 当前实施状态 | 证据 |
|---|---|---|
| SEA-ASSET-R45 | v002 Blender 源级验收完成。{structural['bridge_span_m']:.1f} 米菜园桥接两楼，右楼实墙、楼板和屋顶同弧。挂架定位、落地灯笼、严重缺墙断板和裂分地坪已完成。50 组件／{audit['assembly']['visible_instances']} 实例，{audit['checks']} 项重开检查与 {len(structural['checks'])} 项结构检查零失败。Skill 验证覆盖母版与 50 包，10 张 Cycles 实图复核。51 条 v002 主记录，3 条历史组件，复用原图集。 | [本轮交付](../../development/2026-11-05_neon_garden_quarter_v002.md) · [母版](../../../art_source/scenes/neon_garden_quarter/v002/neon_garden_quarter.blend)。Godot、碰撞、导航、泊位、商业授权 pending。 |
'''
for path,payload in [(root/'docs/features/asset/spec.md',spec),(root/'docs/features/asset/ledger.md',ledger)]:
    before=path.read_bytes()
    if b'SEA-ASSET-R45' not in before:
        with path.open('a',encoding='utf8',newline='') as handle:handle.write(payload)
        assert path.read_bytes().startswith(before)
