# 场景Skill水上／水下分类与差异（2026-11-02）

归属SEA-ASSET-R06/R07/R40。用户要求水下观赏建筑沿用同一套风格，制作先判断水上／水下，再加载差异。

已在现有sea-scene-component-authoring中实现：入口先判海上主场景范围、再读building_class，水上加载references/above-water.md，水下加载references/underwater-scenery.md；混合设施按总成／组件分别判定。共用尺寸、比例、倒角、色板和材质只有一份，保持一位小数；原水线偏移只在水上附件应用。水下只观赏，全子树无空间／玩法功能，不将其误认为独立海底场景。

项目／用户Skill入口、两个原尺寸附件和两个新差异附件同步；用户级不引用失效的仓库相对规范文件，两个差异附件可独立随Skill安装。未修改模型、场景、资产记录或源／运行哈希，不声称修复现有运行职责缺口。

备份及校验输出：D:/projects/sea-work/skill-water-branches-20261102/。Skill格式、附件可达性、共用数据保真与两副本一致性以及工程sync／复核结果见该目录；本轮不运行Godot或真实渲染。

最终校验：五文件项目／用户副本逐字节一致，入口与两分支附件链接可达；原measurement、bevels和一位小数默认数值保持，水线偏移只在水上差异应用，共12项检查通过。两个Skill quick_validate均退出0。工程sync／复核已执行，退出结果见外部verification.json；未覆盖其它任务的条款、运行哈希或索引来强制消除报错。
