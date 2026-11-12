# 场景工坊门窗和破旧无效果修复

用户2026-11-12 15:17反馈。SEA-WORKSHOP R53–R56。

## 根因

1. UI基础window_width/height/sill与architecture_window_*两套值。Config.window_settings后者覆盖前者，生成按钮提交后基础改动被旧架构值吃掉。
2. _apply_architecture_window提交整套_architecture_ui_patch，窗按钮可能顺带提交屋顶/形体，却不提交基础窗尺寸；刷新会吞掉尚未提交的楼宽。
3. _apply_window_override会先切single并从session回填，导致用户刚填的值丢失。
4. shell_validate明确拒绝非0damage，旧UI却仍称结构破损。aging只换旧木色，默认cozy墙无效果。
5. window_sill min=.01 step=.1使输入1.10实际落1.11，双控件不同步；改step=.01。
6. 稀疏配方architecture.window无width/height/sill时，UI收集会补齐同效默认值但fingerprint不同，误报未应用；has_pending_fields仅对此继承等值情形消去额外键再比较，不放过真实改动。

## 实现

- 全局尺寸双向无信号同步，floor/facade/single不串。窗局部按钮只提交对应window字典和global顶层三尺寸，重建后保留其它UI待提交输入。顶部生成提交全局参数。
- 破旧页“结构破损”改“门窗破损”，新增“应用破旧并生成”，明确承重结构破洞未实现。
- aging四档0/轻/中/重取原共享色盘cream/stone/mint_white/gray；每层每run净空间允许时至多一个六边闭合窗下斑驳，2mm离墙4mm厚，无碰撞。公共PNG和四材质不改。
- shell_damage_geometry：玻璃侧边锯齿破口、木门底部纤维形缺口，双线性映射共用洞口pull，活动玻璃按原铰链旋转，再统一taper。凹多边形挤出断面封厚，保持单件单连通闭合。damage=0使用原路径。缺失量随damage增大，seed独立于植物与结构。
- 承重墙/板/屋顶及其碰撞保持不变；不称残楼、墙破洞、框损伤或坍塌；外部prefab不保证随原生破损参数变化。
- editor最小隔离复制helper，保存manifest源hash收录helper。

## 实测

- shell：`D:/projects/sea-work/verification/20261112-161332-weathering-shell-final-606baa/report.json`，9872/0、exit0/PASS。
- editor：`D:/projects/sea-work/verification/20261112-162447-window-weathering-signed-9542fb/report.json`，20015/0、exit0/PASS、unexpected=[]、scene_unchanged=true。
- architecture/rules/deep在160656-window-weathering-kernel-593668均PASS。
- 窗.9×1.3、窗台1.1检查实际glass尺寸减2mm装配缝；门1.3×2.2检查实际door包络；全局/楼层/立面/单窗不串；保留未应用楼宽。
- aging0/.2/.5/.9实际墙UV hash与斑驳变化；damage0/.4/.9/1实际破口缺失面积递增、射线穿透、重复seed一致、承重网格与碰撞不变。
- 保存后重新打开，实际破口、色格、斑驳保持；共享四材质身份与文件hash保持。
- 同机位_clean/_windows_edited/_weathered/_damaged已真实捕获，玻璃锯齿空缺与墙面色调可见。用户美术终审未签。

首批shell新增语义缺hex字段导致4项色采样失败，补齐原色盘事实后通过；首批editor19999/22失败为窗台步长/dirty语义和稀疏配方误dirty，后修正。一次中途退出无completion_marker且GPU资源退出报错，该批未签，未过滤为PASS。原日志保留。

## 使用

门窗页选全局或明确局部范围，调窗型和尺寸后点“应用当前范围窗构造”；全局也可直接点顶部生成。破旧页调表面老化/门窗破损后点“应用破旧并生成”。老化为分档色盘表现，不是连续污渍贴图；破损不破坏承重墙。
