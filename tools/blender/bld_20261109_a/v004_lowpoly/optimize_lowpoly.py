import bpy, json, hashlib, math, os
from pathlib import Path
from collections import Counter

R = Path('D:/projects/sea')
V3 = R / 'art_source/scenes/bld_20261109_a/v003'
D = R / 'art_source/scenes/bld_20261109_a/v004_lowpoly'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent / 'sea-work')) / 'bld_20261109_a/v004_lowpoly'
D.mkdir(parents=True, exist_ok=True)
W.mkdir(parents=True, exist_ok=True)
S3 = V3 / 'bld_20261109_a_v003.blend'
assert S3.is_file()
sha3 = hashlib.sha256(S3.read_bytes()).hexdigest()

bpy.ops.wm.open_mainfile(filepath=str(S3), load_ui=False)
sc = bpy.context.scene
assert sc.name == 'BLDA_编号海上建筑_v003'
# Safety copy before any destructive mesh optimization.
bpy.ops.wm.save_as_mainfile(filepath=str(W / 'before_lowpoly.blend'), copy=True)

cat3 = json.loads((V3 / 'catalog.json').read_text(encoding='utf-8'))['components']
inst3 = json.loads((V3 / 'component_instances.json').read_text(encoding='utf-8'))['instances']
counts = Counter(x['key'] for x in inst3)
by_key = {x['key']: x for x in cat3}

# Per-instance triangle budget. These values prioritize silhouette and the elevated storefront,
# while aggressively collapsing first-floor lettering and small circular details.
target = {
    'deck': 260, 'shell': 700, 'slab': 24, 'coping': 70, 'post': 36,
    'roof_hut': 300, 'roof_sheet': 560, 'side_eave': 420,
    'awning': 820, 'shop_lintel': 100, 'main_sign': 620, 'fascia': 360, 'blade_sign': 120,
    'barred_window': 190, 'transom': 130, 'backdoor': 90,
    'ac_unit': 220, 'antenna': 90, 'clothesline': 60,
    'pipe_set': 90, 'vent_duct': 110, 'stair_ladder': 220,
    'poster_panel': 260, 'shelf': 180, 'jar': 16, 'carton': 36,
    'basket': 120, 'stool_stack': 180, 'bin': 70, 'handtruck': 120,
    'jerrycan': 70, 'mailbox': 65, 'shrine': 90,
    'planter_round': 70, 'planter_trough': 60,
    'citrus': 150, 'leaf_cluster': 75, 'succulent': 45, 'vine': 65,
    'shirt': 110, 'jacket': 80, 'trousers': 60,
    'washer': 110, 'table': 110, 'display_fan': 110,
    'thermos': 55, 'cup': 55, 'menu': 55, 'notice': 28,
}
# Keep a documented exception for the two prominent upper signs.
assert all(k in target for k in by_key), sorted(set(by_key) - set(target))

# Component collections are not linked directly to the scene; temporarily link them for
# modifier application, then unlink again. Collection instances remain the only render copies.
component_cols = []
for e in cat3:
    c = bpy.data.collections.get(e['collection'])
    if c is None:
        raise RuntimeError('missing component collection ' + e['collection'])
    component_cols.append(c)
    c.hide_render = True
    if sc.collection.children.get(c.name) is None:
        sc.collection.children.link(c)

removed = []
kept_text = []

def delete_obj(o, reason):
    removed.append({'object': o.name, 'collection': o.users_collection[0].name if o.users_collection else '', 'reason': reason})
    bpy.data.objects.remove(o, do_unlink=True)

def obj_names(c):
    return [o.name for o in c.all_objects if o.type == 'MESH']

def remove_by(c, pred, reason):
    for o in list(c.all_objects):
        if o.type == 'MESH' and pred(o):
            delete_obj(o, reason)

def keep_every_other(c, token, keep_first_last=True):
    arr = sorted([o for o in c.all_objects if o.type == 'MESH' and token in o.name], key=lambda o: o.name)
    keep = set()
    for i, o in enumerate(arr):
        if i % 2 == 0 or (keep_first_last and i in {0, len(arr)-1}):
            keep.add(o.name)
    for o in arr:
        if o.name not in keep:
            delete_obj(o, 'lowpoly_sparse_' + token)

for e in cat3:
    key = e['key']
    c = bpy.data.collections.get(e['collection'])
    # User-requested removal: first-floor and inventory lettering is not gameplay-critical.
    if key in {'jar', 'notice', 'menu', 'poster_panel', 'blade_sign', 'shop_lintel', 'fascia'}:
        remove_by(c, lambda o: '字' in o.name, 'remove_unnecessary_first_floor_3d_lettering')
    # Keep only the large upper-facing identity lettering. It will receive a light decimate,
    # not be removed.
    if key in {'main_sign', 'fascia'}:
        kept_text.extend(o.name for o in c.all_objects if o.type == 'MESH' and '字' in o.name)
    # Broad first-floor simplification.
    if key == 'deck':
        remove_by(c, lambda o: '浅色砖缝' in o.name, 'remove_first_floor_deck_micro_seams')
    if key == 'barred_window':
        keep_every_other(c, '密竖栅')
    if key == 'transom':
        keep_every_other(c, '亮窗竖隔')
    if key == 'basket':
        remove_by(c, lambda o: ('筐格条' in o.name or '筐横条' in o.name), 'remove_basket_micro_lattice')
    if key == 'shirt':
        remove_by(c, lambda o: ('衣服花纹' in o.name or '衣扣' in o.name), 'remove_clothing_micro_pattern')
    if key == 'menu':
        remove_by(c, lambda o: '目录小图' in o.name, 'remove_menu_micro_icons')
    if key == 'poster_panel':
        remove_by(c, lambda o: any(t in o.name for t in ('肖像', '花纹', '中央罐身', '罐身红条')), 'remove_first_floor_poster_micro_art')
    if key == 'antenna':
        remove_by(c, lambda o: '天线抱箍' in o.name, 'remove_antenna_micro_clamps')
        keep_every_other(c, '天线振子')
    if key == 'pipe_set':
        keep_every_other(c, '管道固定卡')
    if key == 'stair_ladder':
        keep_every_other(c, '检修梯横档')
    if key == 'citrus':
        keep_every_other(c, '柑橘枝')
        keep_every_other(c, '柑橘叶')
    # The HVAC fan is intentionally square/rectangular now: retain the outer shell and
    # rectangular louver panel, remove circular rings, mesh and blades.
    if key == 'ac_unit':
        remove_by(c, lambda o: any(t in o.name for t in ('风机深色背孔', '扇叶', '风机保护圈', '风机网栅', '风机中心')), 'square_hvac_vent_replace_round_detail')
        c['lowpoly_square_hvac'] = True
        c['round_detail_policy'] = 'removed; rectangular_louver_retained'
    if key == 'display_fan':
        remove_by(c, lambda o: any(t in o.name for t in ('风扇罩', '风扇护网')), 'square_lowpoly_fan_remove_round_guard')
        c['lowpoly_square_fan'] = True
    # Keep the visual presence of the upper awning/roof; decimation below handles the dense
    # strip subdivisions rather than deleting the silhouette.

# Convert round micro-props toward square/low-sided forms via aggressive collapse. The main
# planters remain recognizable and are only reduced to low-sided rings.
round_keys = {'jar', 'cup', 'thermos', 'washer', 'planter_round', 'jerrycan', 'ac_unit', 'display_fan'}
for e in cat3:
    c = bpy.data.collections.get(e['collection'])
    current = sum(len(o.data.loop_triangles) if (o.data.calc_loop_triangles() is None) else len(o.data.loop_triangles) for o in c.all_objects if o.type == 'MESH')
    # Collection target is per master component, not weighted by instance count.
    goal = target[e['key']]
    if current <= 0:
        continue
    ratio = min(0.92, max(0.012, float(goal) / float(current)))
    if e['key'] in round_keys:
        ratio = min(ratio, 0.28)
    if e['key'] in {'roof_sheet', 'side_eave', 'awning', 'poster_panel'}:
        ratio = min(ratio, 0.12)
    for o in list(c.all_objects):
        if o.type != 'MESH' or len(o.data.polygons) < 4:
            continue
        # Upper text is retained but gets a gentler reduction so it remains legible.
        local_ratio = ratio
        if e['key'] in {'main_sign', 'fascia'} and '字' in o.name:
            local_ratio = min(0.12, max(0.045, ratio * 1.5))
        mod = o.modifiers.new('LOWPOLY_COLLAPSE', 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = local_ratio
        mod.use_collapse_triangulate = True
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except Exception as ex:
            # Do not fail the whole derivative because one tiny mesh cannot accept collapse.
            o.modifiers.remove(mod)
            o['lowpoly_decimate_error'] = str(ex)
        o['lowpoly_ratio'] = float(local_ratio)
    c['lowpoly_target_master_triangles'] = int(goal)
    c['lowpoly_source_master_triangles'] = int(current)

# Unlink temporary component collections and restore render visibility state.
for c in component_cols:
    c.hide_render = False
    if sc.collection.children.get(c.name) is not None:
        try:
            sc.collection.children.unlink(c)
        except RuntimeError:
            pass

# Mark derivative metadata on scene and collections.
sc.name = 'BLDA_编号海上建筑_v004_lowpoly'
sc['source_parent'] = 'v003/bld_20261109_a_v003.blend'
sc['source_parent_sha256'] = sha3
sc['optimization_goal'] = 'approximately_10000_scene_triangles'
sc['user_directives'] = 'remove_lower_3d_lettering; square_hvac; simplify_first_floor; preserve_upper_silhouette'
sc['registered_source_replaced'] = False

# Update plan as a derivative, preserving the v003 design records and stable component IDs.
plan3 = json.loads((V3 / 'component_plan.json').read_text(encoding='utf-8'))
plan3['version'] = 'v004_lowpoly'
plan3['status'] = 'optimization_candidate'
plan3['source_parent'] = 'art_source/scenes/bld_20261109_a/v003/bld_20261109_a_v003.blend'
plan3['source_parent_sha256'] = sha3
plan3['optimization'] = {
    'target_scene_triangles': 10000,
    'acceptance_range': [8500, 11000],
    'budget_basis': 'visible_collection_instances_after_depsgraph_evaluation',
    'removed_3d_lettering': sorted(set(x['object'] for x in removed if 'lettering' in x['reason'])),
    'upper_lettering_kept': kept_text,
    'hvac': 'rectangular_louver_only; round_fan_details_removed',
    'first_floor': 'micro_seams_grilles_inventory_labels_reduced',
    'bevel_policy': 'decimate_or_remove_dense_roundover; silhouette retained',
    'target_by_component_instance_triangles': target,
}
(D / 'component_plan.json').write_text(json.dumps(plan3, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(D / 'optimization_log.json').write_text(json.dumps({
    'source_parent': str(S3), 'source_parent_sha256': sha3,
    'removed_count': len(removed), 'removed': removed,
    'kept_upper_text': kept_text, 'target': target,
    'notes': ['v003 remains untouched', 'same 92 instances and stable component IDs', 'lowpoly is derivative/candidate until final visual review'],
}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(D / 'component_instances.json').write_text(json.dumps({
    'schema': 'sea.component_instances',
    'coordinate_contract': json.loads((V3 / 'component_instances.json').read_text(encoding='utf-8'))['coordinate_contract'],
    'instances': inst3,
}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

# Save the derivative, never overwrite v003.
bpy.context.preferences.filepaths.save_version = 0
out = D / 'bld_20261109_a_v004_lowpoly.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(out), compress=True)
print(json.dumps({'saved': str(out), 'removed': len(removed), 'kept_upper_text': len(kept_text), 'source_parent_sha256': sha3}, ensure_ascii=False), flush=True)
