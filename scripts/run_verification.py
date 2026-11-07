#!/usr/bin/env python3
"""Run sea checks with isolated user data, full logs and unmasked exit codes."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
GODOT_ROOT = ROOT / 'godot'
TESTS = {
    'sunroom-collision': ('tests/test_sunroom_underwater_collision.gd', r'\[sunroom-collision\] \d+ checks, 0 failures'),
    'sunroom-underwater': ('tests/test_sunroom_underwater_region.gd', r'\[sunroom-underwater\] \d+ checks, 0 failures'),
    'visual-sunroom-underwater': ('tests/test_sunroom_underwater_region.gd', r'\[sunroom-underwater\] \d+ checks, 0 failures'),
    'visual-frame-diagnosis': ('tools/profile_frame_diagnosis.gd', r'\[frame-diagnosis\] complete'),
    'visual-frame-process': ('tools/profile_frame_process.gd', r'\[frame-process\] complete'),
    'visual-frame-subsystems': ('tools/profile_frame_subsystems.gd', r'\[frame-subsystems\] complete'),
    'visual-frame-functions': ('tools/profile_frame_functions.gd', r'\[frame-functions\] complete'),
    'shop-sightline': ('tests/test_shop_sightline.gd', r'\[shop-sightline\] \d+ checks, 0 failures'),
    'visual-shop-sightline': ('tools/capture_shop_sightline.gd', r'\[shop-sightline-render\] \d+ checks, 0 failures'),
    'gift-kiosk-interior': ('tests/test_gift_kiosk_interior.gd', r'\[gift-kiosk-interior\] \d+ checks, 0 failures'),
    'visual-gift-kiosk-interior': ('tools/capture_gift_kiosk_interior.gd', r'\[gift-kiosk-interior-render\] \d+ checks, 0 failures'),
    'dive-maps': ('tests/test_dive_maps.gd', r'\[dive-maps\] \d+ checks, 0 failures'),
    'visual-dive-maps': ('tests/test_dive_maps.gd', r'\[dive-maps\] \d+ checks, 0 failures'),
    'roof-reveal-component': ('tests/test_roof_reveal_component.gd', r'\[roof-reveal-component\] \d+ checks, 0 failures'),
    'roof-reveal': ('tests/test_roof_reveal.gd', r'\[roof-reveal\] \d+ checks, 0 failures'),
    'visual-roof-reveal': ('tools/capture_roof_reveal.gd', r'\[roof-reveal-render\] \d+ checks, 0 failures'),
    'gift-kiosk': ('tests/test_gift_kiosk.gd', r'\[gift-kiosk\] \d+ checks, 0 failures'),
    'visual-gift-kiosk': ('tools/capture_gift_kiosk.gd', r'\[gift-kiosk-render\] \d+ checks, 0 failures'),
    'seabed-scene': ('tools/test_seabed_scene.gd', r'\[seabed-scene\] \d+ checks, 0 failures'),
    'seabed-authoring': ('tools/build_sunken_seabed.gd', r'\[seabed-authoring\] \d+ checks, 0 failures'),
    'scenic-fish-distribution': ('tests/test_scenic_fish_distribution.gd', r'\[scenic-fish-distribution\] \d+ checks, 0 failures'),
    'visual-scenic-fish-structure': ('tests/test_scenic_fish_distribution.gd', r'\[scenic-fish-distribution\] \d+ checks, 0 failures'),
    'visual-scenic-fish-distribution': ('tools/capture_scenic_fish_distribution.gd', r'\[scenic-fish-render\] \d+ checks, 0 failures'),
    'sea-fauna': ('tests/test_sea_fauna.gd', r'\[sea-fauna\] \d+ checks, 0 failures'),
    'visual-sea-fauna': ('tools/capture_sea_fauna.gd', r'\[sea-fauna-render\] \d+ checks, 0 failures'),
    'visual-sunken-seabed': ('tools/capture_sunken_seabed.gd', r'\[sunken-seabed-render\] \d+ checks, 0 failures'),
    'sunken-city': ('tests/test_sunken_city.gd', r'\[sunken-city\] \d+ checks, 0 failures'),
    'visual-sunken-city': ('tools/capture_sunken_city.gd', r'\[sunken-city-render\] \d+ checks, 0 failures'),
    'modules': ('tests/test_feature_modules.gd', r'\[modules\] \d+ checks, 0 failures'),
    'npc-shop': ('tests/test_npc_shop.gd', r'\[npc-shop\] \d+ checks, 0 failures'),
    'npc-people': ('tests/test_npc_people.gd', r'\[npc-people\] \d+ checks, 0 failures'),
    'npc-profile-ui': ('tests/test_npc_profile_ui.gd', r'\[npc-profile-ui\] \d+ checks, 0 failures'),
    'npc-shop-site': ('tests/test_npc_shop_site.gd', r'\[npc-shop-site\] \d+ checks, 0 failures'),
    'npc-rules': ('tests/test_npc_rules.gd', r'\[npc-rules\] \d+ checks, 0 failures'),
    'shop-rules': ('tests/test_shop_rules.gd', r'\[shop-rules\] \d+ checks, 0 failures'),
    'npc-world': ('tests/test_npc_world.gd', r'\[npc-world\] \d+ checks, 0 failures'),
    'npc-performance': ('tests/test_npc_performance.gd', r'\[npc-performance\] \d+ checks, 0 failures'),
    'npc-clock': ('tests/test_npc_clock.gd', r'\[npc-clock\] \d+ checks, 0 failures'),
    'rooftop-npc-access': ('tests/test_rooftop_npc_access.gd', r'\[rooftop-npc-access\] \d+ checks, 0 failures'),
    'visual-npc-world': ('tools/capture_npc_world.gd', r'\[npc-world-render\].*0 failures'),
    'npc-appearance': ('tests/test_npc_appearance.gd', r'\[npc-appearance\] \d+ checks, 0 failures'),
    'visual-npc-appearance': ('tools/capture_npc_appearance.gd', r'\[npc-appearance-render\] \d+ PNG, 0 failures'),
    'residence': ('tests/test_residence.gd', r'\[residence\] \d+ checks, 0 failures'),
    'visual-residence': ('tests/test_residence.gd', r'\[residence\] \d+ checks, 0 failures'),
    'flower-crops': ('tests/test_flower_crops.gd', r'\[flower-crops\] \d+ checks, 0 failures'),
    'npc-careers': ('tests/test_npc_careers.gd', r'\[npc-careers\] \d+ checks, 0 failures'),
    'npc-integration': ('tests/test_npc_integration.gd', r'\[npc-integration\] \d+ checks, 0 failures'),
    'npc-relocation': ('tests/test_npc_relocation.gd', r'\[npc-relocation\] \d+ checks, 0 failures'),
    'npc-save': ('tests/test_npc_save.gd', r'\[npc-save\] \d+ checks, 0 failures'),
    'npc-save-seed': ('tests/test_npc_save.gd', r'\[npc-save\] \d+ checks, 0 failures'),
    'npc-save-restart': ('tests/test_npc_save.gd', r'\[npc-save\] \d+ checks, 0 failures'),
    'visual-npc-release': ('tools/capture_npc_release.gd', r'\[npc-release-render\] \d+ checks, 0 failures'),
    'visual-npc-people': ('tools/capture_npc_people.gd', r'\[npc-people-render\] \d+ checks, 0 failures'),
    'parity': ('tests/test_core.gd', r'\d+ checks, 0 failures'),
    'farming': ('tests/test_farming.gd', r'\[farming\] \d+ checks, 0 failed'),
    # 作物品种与四阶段形态：隔离运行，不加载 main.tscn（SEA-CROP-R05 的证据）。
    'crops': ('tests/test_crops.gd', r'\[crops\] \d+ checks, 0 failed'),
    # 作物 12 阶段真实渲染：正视图 + 俯视图，作为 SEA-CROP-R06 的渲染证据。
    # 必须以 visual- 开头，harness 才会给真实渲染器；headless 下截不了图（会挂住）。
    'visual-crops': ('tools/capture_crops.gd', r'\[crops-render\] \d+ checks, 0 failures'),
    'surface': ('tests/test_surface_movement.gd', r'\[surface\].*failures=0'),
    'click': ('tests/test_click_controls.gd', r'\[click-controls\] \d+ checks, 0 failures'),
    # 键盘操控：方向键走人 / 划船、镜头不再被方向键平移、E 上下船
    # （SEA-MOVE-R20 / SEA-NAV-R15 / SEA-CAMERA-R12 / SEA-INTERACT-R13）。
    'keyboard-control': ('tests/test_keyboard_control.gd', r'\[keyboard-control\] \d+ checks, 0 failures'),
    'keyboard-panels': ('tests/test_keyboard_panels.gd', r'\[keyboard-panels\] \d+ checks, 0 failures'),
    'visual-keyboard-panels': ('tests/test_keyboard_panels.gd', r'\[keyboard-panels\] \d+ checks, 0 failures'),
    'keyboard-building': ('tests/test_keyboard_building.gd', r'\[keyboard-building\] \d+ checks, 0 failures'),
    'keyboard-farm-loop': ('tests/test_keyboard_farm_loop.gd', r'\[keyboard-farm-loop\] \d+ checks, 0 failures'),
    'visual-keyboard-farm-loop': ('tests/test_keyboard_farm_loop.gd', r'\[keyboard-farm-loop\] \d+ checks, 0 failures'),
    'visual-keyboard-building': ('tests/test_keyboard_building.gd', r'\[keyboard-building\] \d+ checks, 0 failures'),
    'keyboard-entry': ('tests/test_keyboard_entry.gd', r'\[keyboard-entry\] \d+ checks, 0 failures'),
    'keyboard-travel': ('tests/test_keyboard_travel.gd', r'\[keyboard-travel\] \d+ checks, 0 failures'),
    # 手感参数：加减速时间常数、反向弧线、步频耦合、镜头前视/零滞后、船转向惯性与侧滑、E 去抖
    # （SEA-MOVE-R22 / SEA-CAMERA-R13 / SEA-NAV-R16）。
    'control-feel': ('tests/test_control_feel.gd', r'\[control-feel\] \d+ checks, 0 failures'),
    'boat-unstick': ('tests/test_boat_unstick.gd', r'\[boat-unstick\] \d+ checks, 0 failures'),
    'visual-boat-unstick': ('tests/test_boat_unstick.gd', r'\[boat-unstick\] \d+ checks, 0 failures'),
    'shift-jog': ('tests/test_shift_jog.gd', r'\[shift-jog\] \d+ checks, 0 failures'),
    'visual-shift-jog': ('tests/test_shift_jog.gd', r'\[shift-jog\] \d+ checks, 0 failures'),
    'facing-interaction': ('tests/test_facing_interaction.gd', r'\[facing-interaction\] \d+ checks, 0 failures'),
    'visual-facing-interaction': ('tests/test_facing_interaction.gd', r'\[facing-interaction\] \d+ checks, 0 failures'),
    # 纯键盘可达性：采集点在场且站得上去、船上 E 能打捞/靠岸、泊位里朝岸=下船。
    # （SEA-GATHER-R04/R05 / SEA-INTERACT-R15/R16 / SEA-MOVE-R24）
    'interaction-reach': ('tests/test_interaction_reach.gd', r'\[interaction-reach\] \d+ checks, 0 failures'),
    'visual-interaction-reach': ('tools/capture_interaction_reach.gd', r'\[interaction-reach-render\] failures=0'),
    'probe-control-gaps': ('tools/probe_indoor_keys.gd', r'\[gap\] '),
    'probe-gather-reach': ('tools/probe_gather_reach.gd', r'\[gr\] '),
    'management': ('tests/test_management_loop.gd', r'\[management\] \d+ checks, 0 failed'),
    'camera': ('tests/test_camera_follow.gd', r'\[camera-follow\].*failures=0'),
    # 缩放上限 38 m：连续往外滚拉不出去，往里仍能到 9 m（SEA-CAMERA-R11，真实渲染）。
    'visual-camera-zoom': ('tools/capture_camera_zoom.gd', r'\[camera-zoom\] \d+ checks, 0 failures'),
    # 取景对照探针：同一构图只改距离，各存一张图（SEA_ZOOM_SET="38,54.25,78"）。
    'visual-zoom-framing': ('tools/probe_zoom_framing.gd', r'\[framing\] '),
    # 取景标定：同一栋家园小屋在不同距离下占画面多宽，用来把"看图定距离"变成可复算的数。
    'visual-home-framing': ('tools/probe_home_framing.gd', r'\[home-framing\] distance='),
    # 连通块包围盒量尺：同一算法跑参考图与候选图，系统偏差互相抵消。
    # 参考图路径由 SEA_FRAMING_REF 给绝对路径（不放 assets）；不给则只输出候选宽度。
    'visual-silhouette': ('tools/probe_silhouette.gd', r'\[silhouette\] (done|no reference)'),
    # 交互热区必须跟着物体走：出货箱曾偏 2.07 米，看得见却点不到。
    'interact-focus': ('tests/test_interact_focus.gd', r'\[interact-focus\] \d+ checks, 0 failures'),
    # 走不到的地方点开操作菜单：图标贴边可命中、菜单钉住、逐项写明原因。
    # 交互热区按模型本体算：土箱之间的甲板缝不能被吞，否则点地面走不了路。
    'pick-mesh': ('tests/test_pick_mesh.gd', r'\[pick-mesh\] \d+ checks, 0 failures'),
    'visual-pick-mesh': ('tools/capture_pick_mesh.gd', r'\[shot\] done'),
    'unreachable-menu': ('tests/test_unreachable_menu.gd', r'\[unreachable-menu\] \d+ checks, 0 failures'),
    # 点船 = 上船；靠岸图标随「点击会干什么」换宿主（岸上贴船、船上贴码头）。
    'board-click': ('tests/test_board_by_click.gd', r'\[board-click\] \d+ checks, 0 failures'),
    'ocean': ('tests/test_ocean.gd', r'\[ocean\].*failures=0'),
    'selftest': (None, r'\[selftest\] \d+ passed, 0 failed'),
}
CORE = list(TESTS)
TESTS.update({
    'visual-vegetation': ('tools/capture_vegetation.gd', r'\[vegetation-render\] 0 failures'),
    'visual-vegetation-study': ('tools/capture_vegetation_study.gd', r'\[vegetation-study\] complete'),
    'visual-proton-scatter': ('tools/capture_proton_scatter.gd', r'\[proton-scatter-trial\] 0 failures'),
    'visual-proton-preview': ('tests/test_proton_preview.gd', r'\[proton-preview\] 11542 instances, 0 failures'),
    'vegetation-contract': ('tests/test_vegetation.gd', r'\[vegetation\] \d+ checks, 0 failures'),
    'visual-vegetation-performance': ('tools/profile_vegetation.gd', r'\[vegetation-performance\] complete'),
    'neon-garden-quarter': ('tests/test_neon_garden_quarter.gd', r'\[neon-garden-quarter\] \d+ checks, 0 failures'),
    # 家园外围残楼围挡：20 段接入主场景，四边连续挡船、不侵入可活动范围（SEA-ASSET-R47）。
    'sea-barrier': ('tests/test_sea_barrier.gd', r'\[sea-barrier\] \d+ checks, 0 failures'),
    'visual-sea-barrier': ('tools/capture_sea_barrier.gd', r'\[sea-barrier-render\] 0 failures'),
    'visual-neon-garden-quarter': ('tests/test_neon_garden_quarter.gd', r'\[neon-garden-quarter\] \d+ checks, 0 failures'),
    'rowing-fit': ('tests/test_rowing_fit.gd', r'\[rowing-fit\] \d+ checks, 0 failures'),
    'visual-rowing-fit': ('tests/test_rowing_fit.gd', r'\[rowing-fit\] \d+ checks, 0 failures'),
    'visual-rowing-game': ('tools/capture_rowing_fit.gd', r'\[rowing-game\] \d+ checks, 0 failures'),
    # 划船装配标尺：角色整体尺度、座板、桨架、握柄与桨叶的实际米制关系（只读探针）。
    'rowing-scale-probe': ('tools/probe_rowing_scale.gd', r'\[rowing-scale\] '),
    'building-5m-experience': ('tests/test_building_5m_experience.gd', r'\[building-5m-experience\] \d+ checks, 0 failures'),
    'visual-building-5m-experience': ('tests/test_building_5m_experience.gd', r'\[building-5m-experience\] \d+ checks, 0 failures'),
    'building-5m-rules': ('tests/test_building_5m_rules.gd', r'\[building-5m-rules\] \d+ checks, 0 failures'),
    'building-ui-unified': ('tests/test_building_ui_unified.gd', r'\[building-ui-unified\] \d+ checks, 0 failures'),
    'visual-building-ui-unified': ('tests/test_building_ui_unified.gd', r'\[building-ui-unified\] \d+ checks, 0 failures'),
    'building-demolition': ('tests/test_building_demolition.gd', r'\[building-demolition\] \d+ checks, 0 failures'),
    'building-surfaces': ('tests/test_building_surfaces.gd', r'\[building-surfaces\] \d+ checks, 0 failures'),
    'visual-building-surfaces': ('tests/test_building_surfaces.gd', r'\[building-surfaces\] \d+ checks, 0 failures'),
    'visual-recipe-cards': ('tools/capture_recipe_cards.gd', r'\[recipe-cards\] \d+ checks, 0 failures'),
    'visual-kit-uv': ('tools/capture_kit_uv.gd', r'\[kit-uv\] \d+ checks, 0 failures'),
    'kit-safety': ('tests/test_kit_safety.gd', r'\[kit-safety\] \d+ checks, 0 failures'),
    # 平台只有一类：旧板与两种浮台必须贴边拼、接缝可走、不能隔空起板（SEA-BUILDING-R22）。
    'building-join': ('tests/test_building_join.gd', r'\[building-join\] \d+ checks, 0 failures'),
    'building-save-compat': ('tests/test_building_save_compat.gd', r'\[building-save-compat\] \d+ checks, 0 failures'),
    'visual-building-save-compat': ('tests/test_building_save_compat.gd', r'\[building-save-compat\] \d+ checks, 0 failures'),
    # 全模板玩家模拟：12 框架全部拼装、真实胶囊通行与上楼、10 摆件落新平台、整档存读（SEA-BUILDING-R23）。
    'building-simulate': ('tests/test_building_simulate.gd', r'\[building-simulate\] \d+ checks, 0 failures'),
    # 同一模拟的真实渲染版：给合成后的房子与摆件台各抓一张图。
    'visual-building-simulate': ('tests/test_building_simulate.gd', r'\[building-simulate\] \d+ checks, 0 failures'),
    # 维护边界：目录共享对象被改写可被发现、查询返回副本、不反向依赖单例/测试。
    'building-decoupling': ('tests/test_building_decoupling.gd', r'\[building-decoupling\] \d+ checks, 0 failures'),
    # 性能门禁：吸附求解保持近线性，且与参考实现逐项一致（SEA-BUILDING-R24）。
    'building-perf': ('tests/test_building_perf.gd', r'\[building-perf\] \d+ checks, 0 failures'),
    'building-kit': ('tests/test_building_kit.gd', r'\[building-kit\] \d+ checks, 0 failures'),
    'visual-building-kit': ('tests/test_building_kit.gd', r'\[building-kit\] \d+ checks, 0 failures'),
    'ocean-pickups': ('tests/test_ocean_pickups.gd', r'\[ocean-pickups\] \d+ checks, 0 failures'),
    'wood-density': ('tests/test_wood_density.gd', r'\[wood-density\] \d+ checks, 0 failures'),
    'wood-bundles': ('tests/test_wood_bundles.gd', r'\[wood-bundles\] \d+ checks, 0 failures'),
    'visual-wood-bundles': ('tests/test_wood_bundles.gd', r'\[wood-bundles\] \d+ checks, 0 failures'),
    'visual-ocean-pickups': ('tools/capture_ocean_pickups.gd', r'\[ocean-pickups-render\] \d+ checks, 0 failures'),
    'walk-on-planters': ('tests/test_walk_on_planters.gd', r'\[walk-on-planters\] \d+ checks, 0 failures'),
    'visual-walk-on-planters': ('tests/test_walk_on_planters.gd', r'\[walk-on-planters\] \d+ checks, 0 failures'),
    'character-motor': ('tests/test_character_motor.gd', r'\[character-motor\] \d+ checks, 0 failures'),
    'actor-presentation': ('tests/test_actor_presentation.gd', r'\[actor-presentation\] \d+ checks, 0 failures'),
    'harvest-receive': ('tests/test_harvest_receive.gd', r'\[harvest-receive\] \d+ checks, 0 failures'),
    'visual-harvest-receive': ('tests/test_harvest_receive.gd', r'\[harvest-receive\] \d+ checks, 0 failures'),
    'ground-space': ('tests/test_ground_space.gd', r'\[ground-space\] \d+ checks, 0 failures'),
    'character-space-save': ('tests/test_character_space_save.gd', r'\[character-space-save\] \d+ checks, 0 failures'),
    'walk-facing': ('tests/test_walk_facing.gd', r'\[walk-facing\] \d+ checks, 0 failures'),
    # 码头栈桥两处围栏缺口：矩形越界点必须拒绝、甲板自身必须仍可走（SEA-MOVE-R01）。
    'walk-deck-fit': ('tests/test_walk_deck_fit.gd', r'\[walk-deck-fit\] \d+ checks, 0 failures'),
    # 栈桥栏杆绳是行走的真正边界：矩形必须落在绳内沿以内。
    # 关键在"从模型几何现场量绳位"——绳挪了判据自动跟着改，脱节会被当场抓住。
    'rope-bounds': ('tests/test_rope_bounds.gd', r'\[rope-bounds\] \d+ checks, 0 failures'),
    'visual-walk-facing': ('tests/test_walk_facing.gd', r'\[walk-facing\] \d+ checks, 0 failures'),
    'visual-building-fit': ('tools/capture_building_fit.gd', r'\[building-fit\] \d+ checks, 0 failures'),
    'boat-water-contact': ('tests/test_boat_water_contact.gd', r'\[boat-water-contact\] \d+ checks, 0 failures'),
    'visual-boat-water-contact': ('tests/test_boat_water_contact.gd', r'\[boat-water-contact\] \d+ checks, 0 failures'),
    'building-seed': ('tests/test_building_restart.gd', r'\[building-restart\] \d+ checks, 0 failures'),
    'building-restart': ('tests/test_building_restart.gd', r'\[building-restart\] \d+ checks, 0 failures'),
    'building': ('tests/test_building.gd', r'\[building\] \d+ checks, 0 failures'),
    'building-integration': ('tests/test_building_integration.gd', r'\[building-integration\] \d+ checks, 0 failures'),
    # 建造要先走过去：点远处虚影只排队，站定了才扣材料开工。
    'building-approach': ('tests/test_building_approach.gd', r'\[building-approach\] \d+ checks, 0 failures'),
    'building-open-rules': ('tests/test_building_open_rules.gd', r'\[building-open-rules\] \d+ checks, 0 failures'),
    'building-space': ('tests/test_building_space.gd', r'\[building-space\] \d+ checks, 0 failures'),
    'building-ocean': ('tests/test_building_ocean.gd', r'\[building-ocean\] \d+ checks, 0 failures'),
    'landing-markers': ('tests/test_landing_markers.gd', r'\[landing-markers\] \d+ checks, 0 failures'),
    'visual-landing-markers': ('tests/test_landing_markers.gd', r'\[landing-markers\] \d+ checks, 0 failures'),
    # 海上地图：你自己的位置用真实世界坐标投影，太阳房在家园钉一个固定徽标。
    # 单独一项，因为 map 页只有打开时才构建，普通 UI 回归不会经过它。
    'island-atlas': ('tests/test_island_atlas.gd', r'\[island-atlas\] \d+ checks, 0 failures'),
    'visual-island-atlas': ('tools/capture_island_atlas.gd', r'\[island-atlas-render\] \d+ checks, 0 failures'),
    'visual-building-ocean': ('tests/test_building_ocean.gd', r'\[building-ocean\] \d+ checks, 0 failures'),
    'building-open-seed': ('tests/test_building_open_restart.gd', r'\[building-open-restart\] \d+ checks, 0 failures'),
    'building-open-restart': ('tests/test_building_open_restart.gd', r'\[building-open-restart\] \d+ checks, 0 failures'),
    'visual-building-diy': ('tests/test_building_diy_visual.gd', r'\[building-diy-visual\] \d+ checks, 0 failures'),
    # Diagnostic reproduction, not acceptance of the documented construction guarantees.
    'building-boundary-audit': ('tools/probe_building_boundary_audit.gd', r'\[building-boundary-audit\] \d+ checks, 0 failures'),
    'visual-building-boundary-audit': ('tools/probe_building_boundary_audit.gd', r'\[building-boundary-audit\] \d+ checks, 0 failures'),
    # 浮层进度条：拾取/建造共用一份自绘细条，且拾取条只在最后约 2 秒航程出现。
    # 这两点都不会报错，只会在画面上"看起来不对"，必须显式断言。
    'progress-bars': ('tools/check_progress_bars.gd', r'\[progress-bars\] \d+ checks, 0 failures'),
    # 右下角只剩一枚动物森友会式关闭键（SEA-UI-R47）：贴角、略歪、无键盘文案、点得动。
    'close-hint': ('tools/check_close_hint.gd', r'\[close-hint\] \d+ checks, 0 failures'),
    'visual-close-hint': ('tools/capture_close_hint.gd', r'\[close-hint-render\] \d+ checks, 0 failures'),
    # 拾取进度条的真实渲染证据：航行段不画条、贴近目标才画。
    'visual-pickup-progress': ('tools/capture_pickup_progress.gd', r'\[pickup-progress\] \d+ checks, 0 failures'),
    'visual-building': ('tests/test_building_visual.gd', r'\[visual-building\] \d+ checks, 0 failures'),
    'visual-build-approach': ('tools/capture_build_approach.gd', r'\[shot\] done'),
    'visual-submerged-water-light': ('tests/test_submerged_water_light.gd', r'\[submerged-water-light\] \d+ checks, 0 failures'),
    # 水层专项：水上必须有活动区域与水面阻挡，水下必须无阻挡无碰撞无交互且整体低于水面。
    # 规则出处 docs/standards/水层分类与空间职责.md；按节点自己声明的 water_layer 派生，
    # 不再依赖 test_submerged_neighborhood 里那份写死的六栋名字列表。
    'water-layer': ('tests/test_water_layer.gd', r'\[water-layer\] \d+ checks, 0 failures'),
    'submerged-neighborhood': ('tests/test_submerged_neighborhood.gd', r'\[submerged-neighborhood\] \d+ checks, 0 failures'),
    # 沉没街景十栋（SEA-ASSET-R42）：材质必须序列化在预制体里、逐 surface 角色对得上、
    # 全部低于水面、不与家园/横滨站/现有六栋穿模、不影响航线与岸线。
    'submerged-street': ('tests/test_submerged_street.gd', r'\[submerged-street\] \d+ checks, 0 failures'),
    'visual-submerged-street': ('tests/test_submerged_street.gd', r'\[submerged-street\] \d+ checks, 0 failures'),
    'visual-submerged-neighborhood': ('tests/test_submerged_neighborhood.gd', r'\[submerged-neighborhood\] \d+ checks, 0 failures'),
    'reference-skiff': ('tests/test_reference_skiff.gd', r'\[reference-skiff\] \d+ checks, 0 failures'),
    'visual-reference-skiff': ('tests/test_reference_skiff.gd', r'\[reference-skiff\] \d+ checks, 0 failures'),
    # 海上悬浮商铺：位置=阳光房主体正南 50 米、材质序列化在预制体里、只导 4 个运行网格。
    'sea-supply-probe': ('tools/probe_sea_supply.gd', r'\[sea-supply-probe\] '),
    'route-supply-probe': ('tools/probe_route_supply.gd', r'\[route-probe\] '),
    'sunroom-body-probe': ('tools/probe_sunroom_body.gd', r'\[sunroom-probe\] '),
    # 海上补给站：浮店作为最小区块，涵盖登记/甲板/泊位/上岸/柜台/存档校验。
    'sea-supply': ('tests/test_gift_kiosk.gd', r'\[sea-supply\] \d+ checks, 0 failures'),
    # 顶层牧场：原顶部梯段不挪位，整楼下沉至仅最后一段在水上，登陆可达屋顶。
    'rooftop-ranch': ('tests/test_rooftop_ranch.gd', r'\[rooftop-ranch\] \d+ checks, 0 failures'),
    'ranch-deck-probe': ('tools/probe_ranch_decks.gd', r'DOCKEDGE world='),
    'visual-rooftop-ranch': ('tools/capture_rooftop_ranch_v005.gd', r'\[ranch-shot\] complete'),
    'floating-shop': ('tests/test_gift_kiosk.gd', r'\[floating-shop\] \d+ checks, 0 failures'),
    'building-scale-reference': ('tools/probe_building_scale.gd', r'\[building-scale-reference\] \d+ rows, 0 failures'),
    'visual-floating-shop': ('tools/capture_gift_kiosk.gd', r'\[gift-kiosk-render\] \d+ checks, 0 failures'),
	'visual-corner-notebook': ('tests/test_corner_notebook.gd', r'\[corner-notebook\] \d+ checks, 0 failures'),
    'title-clock-seed': ('tests/seed_title_clock.gd', r'\[title-clock-seed\] ok=true'),
    'visual-title-screen-day': ('tests/test_title_saved_time.gd', r'\[title-saved\] \d+ checks, 0 failures'),
    'visual-title-screen-night': ('tests/test_title_saved_time.gd', r'\[title-saved\] \d+ checks, 0 failures'),
    'visual-title-screen-dawn': ('tests/test_title_saved_time.gd', r'\[title-saved\] \d+ checks, 0 failures'),
    'visual-boat-lamp': ('tests/test_boat_navigation_lamp.gd', r'\[boat-navigation-lamp\] \d+ checks, 0 failures'),
    'visual-atmosphere': ('tests/test_atmosphere.gd', r'\[atmosphere\] \d+ checks, 0 failures'),
    'water-params': ('tools/check_water_params.gd', r'\[water-params\] PASS 吸收式'),
    'visual-home-lighting': ('tests/test_home_lighting.gd', r'\[home-lighting\] \d+ checks, 0 failures'),
    'pocket-services': ('tests/test_pocket_services.gd', r'\[pocket-services\].*0 failures'),
    'visual-pocket-services': ('tests/test_pocket_services.gd', r'\[pocket-services\].*0 failures'),
    'visual-cabin-dayparts': ('tests/test_cabin_dayparts.gd', r'\[cabin-dayparts\] \d+ checks, 0 failures'),
    'pocket-bubbles': ('tests/test_pocket_bubbles.gd', r'\[pocket-bubbles\].*0 failures'),
    # 口袋拖拽整理 + 购买数量 +/−：顺序要持久化、买多份要原子。
    'pocket-drag-buy': ('tools/check_pocket_drag_buy.gd', r'\[pocket-drag-buy\] \d+ checks, 0 failures'),
    # 拖拽整理与购买数量的真实渲染：数量选择器长什么样、拖拽手感如何。
    'visual-pocket-drag-buy': ('tools/capture_pocket_drag_buy.gd', r'\[pocket-ui\] \d+ checks, 0 failures'),
    'visual-pocket-bubbles': ('tests/test_pocket_bubbles.gd', r'\[pocket-bubbles\].*0 failures'),
    # 作物按「天」结算：睡一觉就是一天，醒来那一帧就是新状态，07:00 不能长第二遍。
    # 现场反馈过一次「12:00 浇水、次日 06:00 醒来还是昨天的状态」，所以这条量时刻不量数值。
    'farm-day-change': ('tests/test_farm_day_change.gd', r'\[farm-day-change\] \d+ checks, 0 failures'),
    'sleep-cycle': ('tests/test_sleep_cycle.gd', r'\[sleep-cycle\].*0 failures'),
    # SEA-ROOM：从门口进屋的过场、剖切换面、室内行走、床上睡觉、床铺布置与存档往返。
    'room': ('tests/test_room.gd', r'\[room\] \d+ checks, 0 failures'),
    # 同一份专项的真实渲染版：门口 / 室内 / 床铺 / 前厅 / 换面剖切 / 夜景。
    'visual-room': ('tools/capture_room.gd', r'\[room-render\] 0 failures'),
    # 室内环绕机位的实拍：绕房间转一圈（四个方位）+ 最近/最远/最低/最高，
    # 专门盯「转过去会不会冒出暗板、白杆、缺墙」这类只有看渲染才抓得到的缺陷。
    'visual-room-orbit': ('tools/capture_room_orbit.gd', r'\[room-orbit\] done'),
    # 黑幕文字要停得够久：两段文字各自至少 2 秒、淡入淡出不少于 0.4 秒。
    # 只认常量不够，测试里还实测「全黑后 1.6 秒仍完整可见」。
    'visual-sleep-cycle': ('tests/test_sleep_cycle.gd', r'\[sleep-cycle\].*0 failures'),
    # 体力：行为扣费、疲劳提醒、见底强制休息、次日减半、右下角体力条与存档往返。
    'energy': ('tests/test_energy.gd', r'\[energy\] \d+ checks, 0 failures'),
    'visual-energy': ('tests/test_energy.gd', r'\[energy\] \d+ checks, 0 failures'),
    # 家园补给站升级为渔场：入口、成本（木板 100 / 鱼 50）、背包+仓库付款、存档。
    'fishery': ('tests/test_fishery.gd', r'\[fishery\] \d+ checks, 0 failures'),
    'fishery-production': ('tests/test_fishery_production.gd', r'\[fishery-production\] \d+ checks, 0 failures'),
    'visual-fishery-production': ('tests/test_fishery_production.gd', r'\[fishery-production\] \d+ checks, 0 failures'),
    'fishery-site': ('tools/probe_fishery_site.gd', r'\[fishery-site\] \d+ checks, 0 failures'),
    'fishery-environment': ('tests/test_fishery_environment.gd', r'\[fishery-environment\] \d+ checks, 0 failures'),
    'visual-fishery-environment': ('tests/test_fishery_environment.gd', r'\[fishery-environment\] \d+ checks, 0 failures'),
    'visual-fishery-site': ('tools/probe_fishery_site.gd', r'\[fishery-site\] \d+ checks, 0 failures'),
    'visual-fishery': ('tests/test_fishery.gd', r'\[fishery\] \d+ checks, 0 failures'),
    # 固定浮台自己的水下底座不能挡住扩建：四面接板、原平台仍受保护、泊位那侧原因要说清。
    'building-base-neighbors': ('tests/test_building_base_neighbors.gd', r'\[base-neighbors\] \d+ checks, 0 failures'),
    'visual-plot-shipping': ('tests/test_plot_shipping_loop.gd', r'\[plot-shipping\].*0 failures'),
    'initial-planters': ('tests/test_initial_planters.gd', r'\[initial-planters\] \d+ checks, 0 failures'),
    'visual-initial-planters': ('tests/test_initial_planters.gd', r'\[initial-planters\] \d+ checks, 0 failures'),
    'title-screen': ('tests/test_title_screen.gd', r'\[title-screen\].*0 failures'),
    'visual-title-screen': ('tests/test_title_screen.gd', r'\[title-screen\].*0 failures'),
    'minimum-loop': ('tests/test_minimum_loop.gd', r'\[minimum-loop\].*0 failures'),
    'minimum-loop-visual-baseline': ('tests/test_minimum_loop_without_seabed_fauna.gd', r'\[minimum-loop\].*0 failures'),
    'visual-minimum-loop': ('tests/test_minimum_loop.gd', r'\[minimum-loop\].*0 failures'),
    'decorations': ('tests/test_scene_decorations.gd', r'\[decorations\].*failures=0'),
    'visual-decorations': ('tests/test_scene_decorations.gd', r'\[decorations\].*failures=0'),
    'save-corrupt-seed': ('tests/test_save_corrupt_seed.gd', r'\[save-corrupt-seed\] complete'),
    'save-protection': ('tests/test_save_protection.gd', r'\[save-protection\] ok=true'),
    'visual-weather': ('tools/capture_world_weather.gd', r'\[visual-weather\] complete'),
    # 昼夜光照：真实光照替代屏幕蒙版。断言正午等于基准、夜里太阳落、
    # 水面的天空反射与太阳高光跟着走，且屏幕层不再出现全屏填充。
    'daylight': ('tests/test_daylight_rig.gd', r'\[daylight\] \d+ checks, 0 failures'),
    'framework-modules': ('tests/test_framework_modules.gd', r'\[framework-modules\].*0 failures'),
    'save-seed': ('tests/test_save_seed.gd', r'\[save-seed\] ok=true'),
    'framework-integration': ('tests/test_framework_integration.gd', r'\[framework-integration\].*0 failures'),
    'solar-components': ('tests/test_solar_components.gd', r'\[solar-components\].*failures=0'),
    'sunroom-repair': ('tests/test_sunroom_repair.gd', r'\[sunroom-repair\] \d+ checks, 0 failures'),
    'sunroom-runtime': ('tests/test_sunroom_runtime.gd', r'\[sunroom-runtime\] \d+ checks, 0 failures'),
    'visual-solar-cabin': ('tests/test_solar_cabin_asset.gd', r'\[solar-cabin\].*failures=0'),
    'visual-sea-style': ('tools/capture_sea_style.gd', r'\[sea-style\] complete'),
    # 鱼群专项：模型/动画/配色/单群散布 + 近景渲染证据。
    'visual-fish-schools': ('tools/capture_fish_schools.gd', r'\[fish-schools\] \d+ checks, failures=0'),
    'visual-birds': ('tools/capture_birds.gd', r'\[birds\] \d+ checks, failures=0'),
    'visual-farming': ('tools/capture_farm_cycle.gd', r'\[farm-ui\] failures=0'),
    'visual-management': ('tools/capture_management_loop.gd', r'\[management-ui\].*0 failed'),
    'visual-click': ('tools/capture_click_controls.gd', r'\[click-ui\] failures=0'),
    # 航线水纹：航路虚线已移除，落点改成贴浪面的扩散波纹。
    'visual-route-ripple': ('tools/capture_route_ripple.gd', r'\[route-ripple\] checks done, failures=0'),
    'visual-underwater-depth': ('tests/test_underwater_depth.gd', r'\[uw-depth\] double_sided_lighting.*PASS'),
    'visual-underwater-capture': ('tools/capture_underwater_suite.gd', r'\[uw-suite\] surface_environment_restored=true'),
    'visual-paper-fit': ('tools/check_paper_fit.gd', r'\[paper-fit\] \d+ checks, 0 failures'),
    'visual-world-text': ('tools/check_world_text.gd', r'\[world-text\] \d+ checks, 0 failures'),
    'visual-blockers': ('tools/verify_blockers.gd', r'\[blockers-check\] OK failures=0'),
    # SEA-MOVE-R01：可行走矩形必须落在真实甲板上。
    # 走路不走物理碰撞，站得住是因为 surface_y 把脚贴到那个高度 ——
    # 矩形越过甲板边缘时人物会站在水面上，不报错、不崩，只能靠量。
    'visual-walk-deck': ('tools/verify_walk_deck.gd', r'\[walk-deck\] \d+ checks, 0 failures'),
    # P 面板「光照」页：清单对账（属性名/范围）与端到端写入探针。
    # 两项都不进 core，跟其它参数工具一起按需跑。
    'lighting-params': ('tools/check_light_params.gd', r'\[lighting-params\] \d+ checks, 0 failures'),
    'lighting-panel': ('tools/probe_light_panel.gd', r'\[light-probe\] \d+ checks, 0 failures'),
    'visual-plot-menu': ('tools/capture_plot_menu.gd', r'\[visual-plot-menu\] complete'),
    'visual-salvage': ('tools/capture_salvage.gd', r'\[visual-salvage\] complete'),
    'dock-seed': ('tests/test_dock_and_seed.gd', r'\[dock-seed\] \d+ checks, 0 failures'),
    # 出货箱与码头缆绳的间距：箱子落点在场景，缆绳在组件 GLB 里，改任一边都可能重新穿模。
    'dock-rope-clearance': ('tools/verify_box_rope.gd', r'\[dock-rope\] complete'),
    # SEA-NAV-R11：150m 可航区横跨可航区常量、几何硬界、相机范围、存档回位四处，
    # 单独改任一处都不会报错，只会让「船能开多远」在雷达图和实际上不一致。
    'sail-bounds': ('tests/test_sail_bounds.gd', r'\[sail-bounds\] \d+ checks, 0 failures'),
    # SEA-TOOL：P 面板「测试」页。加资源 / 跳时间 / 换天气 / 回体力必须真的是
    # 落到各自所有者上；「测试页不锁昼夜预览」也在这一支里量 —— 锁着预览改时刻，
    # 状态变了但画面不动，看起来就像工具坏了。
    'test-tools': ('tests/test_test_tools.gd', r'\[test-tools\] \d+ checks, 0 failures'),
    # SEA-SAVE-R14：重置存档。三件事必须同时成立 —— 内存回开局、磁盘也是开局、
    # 旧进度仍可读回。只看前两条的话，把旧档删掉也能全绿。
    'avatar-customization': ('tests/test_avatar_customization.gd', r'\[avatar-customization\] \d+ checks, 0 failures'),
    'avatar-graphic': ('tests/test_avatar_graphic.gd', r'\[avatar-graphic\] \d+ checks, 0 failures'),
    'visual-avatar-graphic': ('tests/test_avatar_graphic.gd', r'\[avatar-graphic\] \d+ checks, 0 failures'),
    'visual-avatar-shoulders': ('tools/capture_avatar_shoulders.gd', r'\[avatar-shoulders\] \d+ checks, 0 failures'),
    'visual-avatar-customization': ('tools/capture_avatar_customization.gd', r'\[avatar-customization-render\] \d+ checks, 0 failures'),
    'avatar-skinning': ('tests/test_avatar_skinning.gd', r'\[avatar-skinning\] \d+ checks, 0 failures'),
    'visual-avatar-skinning': ('tests/test_avatar_skinning.gd', r'\[avatar-skinning\] \d+ checks, 0 failures'),
    'avatar-proportions': ('tests/test_avatar_proportions.gd', r'\[avatar-proportions\] \d+ checks, 0 failures'),
    'visual-avatar-proportions': ('tests/test_avatar_proportions.gd', r'\[avatar-proportions\] \d+ checks, 0 failures'),
    'avatar': ('tests/test_avatar.gd', r'\[avatar\] \d+ checks, 0 failures'),
    'avatar-restart': ('tests/test_avatar_restart.gd', r'\[avatar-restart\] \d+ checks, 0 failures'),
    'onboarding': ('tests/test_onboarding.gd', r'\[onboarding\] \d+ checks, 0 failures'),
    'visual-avatar': ('tools/capture_avatar.gd', r'\[avatar-render\] \d+ checks, 0 failures'),
    'save-reset': ('tests/test_save_reset.gd', r'\[save-reset\] \d+ checks, 0 failures'),
    # 重置存档的两屏：暂停菜单入口 + 确认页。只抓图，确认那一下归 save-reset。
    'visual-save-reset': ('tools/capture_save_reset.gd', r'\[save-reset-render\] 0 failures'),
})
EXPECTED_JSON_ERROR = 'ERROR: Parse JSON failed. Error at line 0: Expected key'


def inspect_log(name, code, text, marker):
    expected = []
    errors = []
    for line in text.splitlines():
        if name == 'selftest' and line.strip() == EXPECTED_JSON_ERROR:
            expected.append(line)
        elif re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:|\bFAIL\b', line):
            errors.append(line)
    completion = re.search(r'\[minimum-loop\]\s+(\d+)\s+checks,\s+(\d+)\s+failures', text)
    removed_nodes = [line.split('] ', 1)[1] for line in text.splitlines()
                     if line.startswith('[visual-baseline-removed] ')]
    failure_labels = [line.split('FAIL ', 1)[1] for line in errors if 'FAIL ' in line]
    ok = code == 0 and not errors and len(expected) <= 1 and re.search(marker, text) is not None
    result = {'exit_code': code, 'passed': ok, 'expected_errors': expected,
              'unexpected_errors': errors, 'completion_marker': bool(re.search(marker, text))}
    if completion:
        result['checks'] = int(completion.group(1))
        result['failures'] = int(completion.group(2))
    result['failure_labels'] = failure_labels
    result['removed_nodes'] = removed_nodes
    return result


def run_minimum_loop_baseline(exe, project, full_config, run_dir, user_name, args):
    cases = [
        ('minimum-loop', 'tests/test_minimum_loop.gd'),
        ('minimum-loop-visual-baseline', 'tests/test_minimum_loop_without_seabed_fauna.gd'),
    ]
    results = {}
    for name, script in cases:
        config = re.sub(r'^config/custom_user_dir_name=.*$',
                        'config/custom_user_dir_name="' + user_name + '/' + name + '"',
                        full_config, flags=re.M)
        (project / 'project.godot').write_text(config)
        cmd = [exe, '--path', str(project), '--headless', '--script', 'res://' + script,
               '--', '--skip-title']
        log = run_dir / (name + '.log')
        with log.open('w') as output:
            try:
                code = subprocess.run(cmd, stdout=output, stderr=subprocess.STDOUT,
                                      timeout=args.timeout).returncode
            except subprocess.TimeoutExpired:
                code = 124
        text = log.read_text(errors='replace')
        result = inspect_log(name, code, text, TESTS[name][1])
        result['log'] = str(log)
        result['command'] = cmd
        results[name] = result
        print(name, 'PASS' if result['passed'] else 'FAIL', 'exit=' + str(code), flush=True)
        if not result['passed']:
            print('\n'.join(text.splitlines()[-18:]), flush=True)
    current = results['minimum-loop']
    baseline = results['minimum-loop-visual-baseline']
    farm_plot = GODOT_ROOT / 'src/farming/farm_plot.gd'
    report = {
        'passed': (current['unexpected_errors'] == baseline['unexpected_errors']
                   and current.get('checks') == baseline.get('checks') == 141
                   and current.get('failures') == baseline.get('failures') == 10
                   and current.get('failure_labels') == baseline.get('failure_labels')
                   and baseline.get('removed_nodes') == [
                       'World/SunkenSeabed',
                       'World/Environment/Animals/SolarCabinFishSchools',
                       'World/Zones/Zone1HomeHarbor/Models/太阳能木屋/SolarCabinGulls',
                       'World/SeaStructures/rooftop_ranch/RooftopRanchGulls',
                   ]),
        'current_result_passed': current['passed'],
        'baseline_result_passed': baseline['passed'],
        'labels_equal': current.get('failure_labels') == baseline.get('failure_labels'),
        'checks_equal': current.get('checks') == baseline.get('checks'),
        'failures_current': current.get('failures'),
        'failures_baseline': baseline.get('failures'),
        'reportpath': str(run_dir / 'report.json'),
        'removednodes': baseline.get('removed_nodes', []),
        'farm_plot_current_sha256': hashlib.sha256(farm_plot.read_bytes()).hexdigest(),
        'head_diff_evidence': subprocess.check_output(
            ['git', 'diff', '--no-ext-diff', '--unified=20', 'HEAD', '--',
             'godot/src/farming/farm_plot.gd'], cwd=ROOT, text=True),
    }
    (run_dir / 'minimum_loop_baseline.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2))
    return results, report


def mount_readonly(target, source):
    """把只读输入挂进隔离工程，尽量不复制。

    Windows 上 `Path.symlink_to` 在没权限时**不抛异常**，而是留下一个空目录 /
    空文件。测试于是读不到 `res://assets/...`，全线报错却看着像代码回归
    （2026-10-24 踩到：ocean 测试挂在 `Cannot call method
    'get_shader_parameter' on a null value`，其实是 water.tres 根本没加载）。
    所以目录优先用目录联接（junction，不需要管理员权限），挂上后必须验一下
    里面有东西，否则退回老实复制。
    """
    if not source.is_dir():
        shutil.copy2(source, target)
        return
    if os.name == 'nt':
        done = subprocess.run(['cmd', '/c', 'mklink', '/J', str(target), str(source)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if done.returncode == 0 and any(target.iterdir()):
            return
        shutil.rmtree(target, ignore_errors=True)
    else:
        target.symlink_to(source, target_is_directory=True)
        if target.is_dir() and any(target.iterdir()):
            return
        target.unlink(missing_ok=True)
    shutil.copytree(source, target)


def isolated_project(run_dir):
    project = run_dir / 'project'
    project.mkdir()
    for name in ['src', 'scripts', 'scenes', 'tests', 'tools', 'shaders', 'data', 'addons']:
        source = GODOT_ROOT / name
        if source.exists():
            shutil.copytree(source, project / name, ignore=shutil.ignore_patterns('__pycache__'))
    # Assets and imported binary cache are read-only inputs to test scripts.
    mount_readonly(project / 'assets', GODOT_ROOT / 'assets')
    mount_readonly(project / 'terrain', GODOT_ROOT / 'terrain')
    mount_readonly(project / 'icon.svg', GODOT_ROOT / 'icon.svg')
    cache = project / '.godot'
    cache.mkdir()
    (cache / '.gdignore').touch()
    if (GODOT_ROOT / '.godot/imported').exists():
        mount_readonly(cache / 'imported', GODOT_ROOT / '.godot/imported')
    classes = GODOT_ROOT / '.godot/global_script_class_cache.cfg'
    if classes.exists():
        shutil.copy2(classes, cache / classes.name)
    uid_cache = GODOT_ROOT / '.godot/uid_cache.bin'
    if uid_cache.exists():
        shutil.copy2(uid_cache, cache / uid_cache.name)
    extension_list = GODOT_ROOT / '.godot/extension_list.cfg'
    if extension_list.exists():
        shutil.copy2(extension_list, cache / extension_list.name)
    text = (GODOT_ROOT / 'project.godot').read_text()
    # Applied BEFORE Godot starts and before any Autoload is constructed.
    user_name = 'sea-verification/' + run_dir.name
    text = re.sub(r'^config/name=.*$', 'config/name="' + user_name + '"', text, flags=re.M)
    text = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n?', '', text, flags=re.M)
    text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\n'
                        + 'config/custom_user_dir_name="' + user_name + '"')
    (project / 'project.godot').write_text(text)
    (project / 'outputs').mkdir()
    camera_baseline = GODOT_ROOT / 'outputs/uw-standard-web-cameras.json'
    if camera_baseline.is_file():
        shutil.copy2(camera_baseline, project / 'outputs' / camera_baseline.name)
    return project, user_name


def user_data_root(user_name):
    """`custom_user_dir_name` 落在哪个真实目录下（Godot 的系统数据目录）。

    Godot 把 `custom_user_dir_name` 拼在**系统数据目录**后面，而不是工程目录：
    Windows 是 `%APPDATA%`，macOS 是 `~/Library/Application Support`，
    Linux 是 `~/.local/share`。这里只是把它算出来，用于**跑完清理**。
    """
    if os.name == 'nt':
        base = Path(os.environ.get('APPDATA') or (Path.home() / 'AppData/Roaming'))
    elif sys.platform == 'darwin':
        base = Path.home() / 'Library/Application Support'
    else:
        base = Path(os.environ.get('XDG_DATA_HOME') or (Path.home() / '.local/share'))
    return base / user_name


def release_user_data(user_name, run_dir):
    """把这一轮 Godot 的用户目录收掉，只留日志。

    2026-11-07：C 盘被写满的根因就在这里。每跑一次验证，Godot 都会在
    `%APPDATA%/sea-verification/<run>` 下重铺一遍 shader_cache（十几到二十几
    MB），而脚本跑完什么都不删 —— 从 10 月 26 日累积到 **1921 个目录 / 20.5 GB**，
    最后 C 盘 0 字节可用，连 Bash 工具都写不出临时文件。

    shader_cache 是纯缓存，删掉只会让下一轮重新编译；`logs/` 里的
    godot.log 才是有用的证据，先复制到 run_dir 再删。
    """
    root = user_data_root(user_name)
    if not root.exists():
        return None
    if os.environ.get('SEA_KEEP_USER_DATA'):
        # 排查渲染/存档问题时需要保留原始 user:// 目录，显式要才留。
        return root
    logs = root / 'logs'
    if logs.is_dir():
        saved = run_dir / 'godot-user-logs'
        saved.mkdir(parents=True, exist_ok=True)
        for item in logs.glob('*.log'):
            try:
                shutil.copy2(item, saved / item.name)
            except OSError:
                pass
    shutil.rmtree(root, ignore_errors=True)
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checks', nargs='*', default=['core'])
    parser.add_argument('--label', default='verification')
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--visual', action='store_true')
    parser.add_argument('--engine-verbose', action='store_true', help='Include Godot resource lifetime diagnostics in captured logs')
    parser.add_argument('--lighting-profile', type=Path, help='Stage only lighting cfg fixtures for visual atmosphere captures')
    parser.add_argument('--import-assets', action='store_true', help='Import new art in the isolated project before checks')
    parser.add_argument('--full-world', action='store_true', help='Explicit legacy/development scope; default is the minimum playable loop')
    args = parser.parse_args()
    checks = CORE if args.checks == ['core'] else args.checks
    title_cases = ['visual-title-screen-day', 'visual-title-screen-night', 'visual-title-screen-dawn']
    if any(name in checks for name in title_cases) and 'title-clock-seed' not in checks:
        checks = list(checks)
        checks.insert(next(i for i, name in enumerate(checks) if name in title_cases), 'title-clock-seed')
    if 'framework-integration' in checks and 'save-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('framework-integration'), 'save-seed')
    if 'save-protection' in checks and 'save-corrupt-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('save-protection'), 'save-corrupt-seed')
    if 'building-restart' in checks and 'building-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('building-restart'), 'building-seed')
    if 'building-open-restart' in checks and 'building-open-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('building-open-restart'), 'building-open-seed')
    if 'npc-save-restart' in checks and 'npc-save-seed' not in checks:
        checks = list(checks)
        checks.insert(checks.index('npc-save-restart'), 'npc-save-seed')
    unknown = set(checks) - set(TESTS)
    if unknown:
        parser.error('unknown checks: ' + ', '.join(sorted(unknown)))
    exe = os.environ.get('GODOT') or shutil.which('godot') or str(Path.home() / 'Applications/Godot.app/Contents/MacOS/Godot')
    if not Path(exe).is_file():
        parser.error('Godot executable unavailable; set GODOT')
    work = Path(os.environ.get('SEA_WORK_ROOT', str(ROOT.parent / 'sea-work'))).resolve()
    if work == ROOT or ROOT in work.parents:
        parser.error('SEA_WORK_ROOT must be outside the repository')
    label = re.sub(r'[^A-Za-z0-9_-]', '_', args.label)
    run_dir = work / 'verification' / (dt.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + label + '-' + uuid.uuid4().hex[:6])
    run_dir.mkdir(parents=True)
    project, user_name = isolated_project(run_dir)
    if any(n in checks for n in ['avatar-proportions','visual-avatar-proportions']):
        reference = ROOT / 'art_source/characters/avatar/v006'
        shutil.copy2(reference / 'shoulder_reference.png', project / 'outputs/avatar-reference.png')
        shutil.copy2(reference / 'shoulder_contract.json', project / 'outputs/avatar-reference-contract.json')
    full_config = (project / 'project.godot').read_text()
    report = {'label': label, 'run_dir': str(run_dir), 'user_data_name': user_name,
              'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'working_tree': subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True),
              'renderer': 'per check; visual-* always use real renderer', 'results': {}}
    print('Evidence:', run_dir, flush=True)
    if checks == ['minimum-loop', 'minimum-loop-visual-baseline']:
        results, baseline_report = run_minimum_loop_baseline(
            exe, project, full_config, run_dir, user_name, args)
        report['results'].update(results)
        report['minimum_loop_baseline'] = baseline_report
        (run_dir / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
        evidence_path = ROOT.parent / 'sea-work' / 'sunken_city' / 'v005' / 'import' / 'minimum_loop_baseline.json'
        evidence_path.parent.mkdir(parents=True, exist_ok=True)
        evidence_path.write_text(json.dumps(baseline_report, ensure_ascii=False, indent=2))
        release_user_data(user_name, run_dir)
        return 0 if all(x['passed'] for x in report['results'].values()) else 1
    if args.import_assets:
        import_log = run_dir / 'asset-import.log'
        import_cmd = [exe, '--headless', '--editor', '--path', str(project), '--import']
        with import_log.open('w', encoding='utf-8') as output:
            try:
                import_code = subprocess.run(import_cmd, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout).returncode
            except subprocess.TimeoutExpired:
                import_code = 124
        import_text = import_log.read_text(encoding='utf-8', errors='replace')
        import_errors = [line for line in import_text.splitlines() if re.search(r'SCRIPT ERROR|SHADER ERROR|ERROR:', line)]
        report['asset_import'] = {'exit_code': import_code, 'log': str(import_log), 'unexpected_errors': import_errors}
        print('asset-import', 'PASS' if import_code == 0 and not import_errors else 'FAIL', 'exit=' + str(import_code), flush=True)
        if import_code != 0 or import_errors:
            (run_dir / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
            print('\n'.join(import_text.splitlines()[-20:]), flush=True)
            release_user_data(user_name, run_dir)
            return 1
    for name in checks:
        config = re.sub(r'\[autoload\].*?(?=\n\[|\Z)', '', full_config, flags=re.S) if name in ['modules','framework-modules','building','kit-safety','npc-shop','npc-people','npc-profile-ui','npc-shop-site','npc-rules','shop-rules','npc-performance','npc-world','visual-npc-world','npc-appearance','visual-npc-appearance','residence','visual-residence','flower-crops','npc-careers'] else full_config
        # Only intentional cross-process cases share a slot. Every other check starts fresh.
        group = ('npc-save-restart' if name in ['npc-save-seed','npc-save-restart'] else
                 'avatar-restart' if name in ['avatar','avatar-restart'] else
                 'building-open-restart' if name in ['building-open-seed','building-open-restart'] else
                 'building-restart' if name in ['building-seed','building-restart'] else
                 'title-clock' if name == 'title-clock-seed' or name in title_cases else
                 'restart' if name in ['save-seed', 'framework-integration'] else
                 'protection' if name in ['save-corrupt-seed', 'save-protection'] else name)
        check_user_name = user_name + '/' + group
        config = re.sub(r'^config/custom_user_dir_name=.*$',
                        'config/custom_user_dir_name="' + check_user_name + '"', config, flags=re.M)
        (project / 'project.godot').write_text(config)
        script, marker = TESTS[name]
        cmd = [exe, '--path', str(project)]
        if args.engine_verbose:
            cmd.append('--verbose')
        is_visual = args.visual or name.startswith('visual-')
        if not is_visual:
            cmd.append('--headless')
        else:
            cmd += ['--resolution', '1280x800', '--fixed-fps', '60']
        if script:
            cmd += ['--script', 'res://' + script]
        else:
            cmd += ['--', '--selftest', '--nosave']
        if 'title-screen' not in name:
            if '--' not in cmd: cmd.append('--')
            cmd.append('--skip-title')
        if name in title_cases:
            if '--' not in cmd: cmd.append('--')
            cmd.append('--title-fixture=' + name.rsplit('-', 1)[-1])
        if name == 'building-seed':
            if '--' not in cmd: cmd.append('--')
            cmd.append('--building-seed')
        if name == 'building-open-seed':
            if '--' not in cmd: cmd.append('--')
            cmd.append('--building-open-seed')
        if name in ['npc-integration','npc-relocation','npc-save','npc-save-seed','npc-save-restart','visual-npc-release','visual-npc-people']:
            if '--' not in cmd: cmd.append('--')
            cmd.append('--nosave')
            if name in ['npc-save-seed','npc-save-restart']:
                cmd.append('--npc-save-phase=' + ('seed' if name == 'npc-save-seed' else 'restart'))
        if args.full_world:
            if '--' not in cmd: cmd.append('--')
            cmd.append('--full-world')
        log = run_dir / (name + '.log')
        with log.open('w') as output:
            try:
                check_env = os.environ.copy()
                if args.lighting_profile:
                    check_env['SEA_CAPTURE_LIGHTING_PROFILE'] = str(args.lighting_profile.resolve())
                code = subprocess.run(cmd, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout, env=check_env).returncode
            except subprocess.TimeoutExpired:
                code = 124
        text = log.read_text(errors='replace')
        result = inspect_log(name, code, text, marker)
        result['log'] = str(log)
        result['user_data_name'] = check_user_name
        result['renderer'] = 'real' if is_visual else 'headless'
        result['command'] = cmd
        report['results'][name] = result
        print(name, 'PASS' if result['passed'] else 'FAIL', 'exit=' + str(code), flush=True)
        if not result['passed']:
            print('\n'.join(text.splitlines()[-18:]), flush=True)
        (run_dir / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    release_user_data(user_name, run_dir)
    return 0 if all(x['passed'] for x in report['results'].values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
