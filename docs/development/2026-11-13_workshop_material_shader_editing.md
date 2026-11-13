# 2026-11-13 · 工坊材质球与着色器实例级编辑

## 目标

让场景工坊编辑出的楼房遵守正式场景的材质球和贴图规则，同时允许作者调整质感，而不是复制材质、修改公共材质或另建一套贴图。

## 规则基线

- 材质角色固定为 `SEA_Matte`、`SEA_Metal`、`SEA_Gloss`、`SEA_Emission`。
- 四个角色继续引用 `godot/assets/materials/solar_cabin/sunny_*.tres`。
- 四个角色共用 `godot/assets/textures/shared/sea_cabin_timber_8x8_512.png`。
- 颜色只通过 PaletteUV / UV2 选择8×8色格；材质实例参数只表达粗糙度、金属度、镜面、发光和透明度。
- 不修改公共 ShaderMaterial 的 `shader_parameter/*`，不复制材质，不复制色板。

## 实施内容

### 配方

`architecture.shading.materials` 是稀疏角色覆盖：

```json
{
  "architecture": {
    "shading": {
      "materials": {
        "SEA_Matte": {
          "roughness": 0.74,
          "metallic": 0.02,
          "specular": 0.31,
          "emission_energy": 0.0,
          "transparency": 0.0
        }
      }
    }
  }
}
```

角色范围：

- `SEA_Matte`：roughness 0.72–0.90，metallic 0–0.05。
- `SEA_Metal`：roughness 0.28–0.45，metallic 0.60–0.85。
- `SEA_Gloss`：roughness 0.12–0.22，metallic 0.05–0.20，透明度 0.45–0.95。
- `SEA_Emission`：roughness 0.30–0.45，emission 1.0–2.0。

非法角色和超出角色范围的参数在 Recipe/ArchitectureConfig 边界拒绝。

### 着色器

`sunny_palette.gdshader` 与 `sunny_palette_gloss.gdshader` 增加实例级参数：

- `sea_material_role`
- 四角色 `sea_*_controls`
- 四角色 `sea_*_emission_energy`

实例默认值为负值哨兵，表示继续使用原有共享材质默认参数。这样旧场景和未设置 `architecture.shading` 的配方不改变外观。

Gloss 的透明度、室内玻璃和发光逻辑继续保留；PaletteUV 采样逻辑未替换。

### 构建和保存链

以下路径统一调用 `MeshBuilder.apply_build_shading`：

- `Session.build`
- `Session.preview_candidate`
- `Store.export_revision`

应用原则：

1. 识别最终 MeshInstance3D 的 active material 是否属于四个共享角色。
2. 只有节点单一角色时写入实例参数。
3. `structure_union` 若包含多个角色 surface，不强行用一个节点参数覆盖，保持共享默认，避免错误地把墙、柱、楼板统一成一个质感。
4. 保存静态 TSCN 时保留 MeshInstance3D instance shader parameters。
5. 槽位独立模块导出复制实例参数。

## 编辑器

“配色”页增加“材质球与着色器实例参数”区域：

- 材质角色选择。
- 粗糙度。
- 金属度。
- 镜面强度。
- 发光强度。
- 玻璃透明度。

全部使用工坊统一 HSlider，遵循当前值/范围显示、160ms实时预览、一次拖拽一条撤销和失败保留最后成功模型的事务规则。

## 验证

- 规则与Shell专项：
  - `/Users/zyq/work/sea-work/verification/20261113-075826-workshop-shading-rules-shell-bba9a1/report.json`
  - `workshop-rules` exit0。
  - `workshop-shell` exit0。
- 真实编辑器保存重载专项：
  - `/Users/zyq/work/sea-work/verification/20261113-080411-workshop-shading-editor-save-final-c8d0bb/report.json`
  - `editor-workshop-upgrade` exit0。
  - 内部 `794 checks / 0 failures`。
- 覆盖：材质角色控件、合规范围拒绝、Matte粗糙度实时实例参数、预览Mesh、配方重载、静态TSCN重载、四共享材质身份和文件hash、PaletteUV原有64色功能。

## 当前边界

- `structure_union` 内部多个材质 surface 当前不支持按墙/柱/腰线分别写不同实例参数；若要做到，需要面级角色参数或拆分可见节点，不能用单节点实例参数伪装。
- 不提供任意Shader代码编辑器，只提供白名单实例参数，避免破坏正式场景着色契约。
- 不修改公共 `.tres`、shader默认参数、共享色板 PNG 或主场景。
- 完整美术终验、性能门禁、正式世界接入和全库历史hash漂移仍不在本轮签署范围。
