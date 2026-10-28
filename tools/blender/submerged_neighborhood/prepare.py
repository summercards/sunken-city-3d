"""Freeze the six reference silhouettes before authoring any new geometry."""
import hashlib, json, os, shutil
from pathlib import Path
R = Path(__file__).resolve().parents[3]
D = R/'art_source/scenes/submerged_neighborhood/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent/'sea-work'))/'submerged_neighborhood_v001'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(v, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
if __name__ == '__main__':
    import sys
    assert not (D/'submerged_neighborhood.blend').exists(), 'Use a new version for geometry changes'
    D.mkdir(parents=True, exist_ok=True); W.mkdir(parents=True, exist_ok=True)
    shutil.copy2(sys.argv[1], D/'reference.jpg')
    items = [
        ('terraced_tower','水下景观·错层檐线楼',[8.8,7.2,17.6],5,'tiered', [13.6,-18.8,11.5],0),
        ('rounded_tower','水下景观·弧角窗廊楼',[8.2,7.0,19.4],6,'curved',[-7.8,-20.4,3.0],0),
        ('slender_tower','水下景观·窄身竖窗楼',[4.2,5.0,14.2],5,'slender',[-4.0,-16.2,-5.9],0),
        ('stepped_lowrise','水下景观·L形矮楼',[7.0,5.6,9.0],3,'L',[4.3,-12.0,23.0],0),
        ('flat_annex','水下景观·窄顶附楼',[3.6,4.6,10.4],4,'annex',[-4.2,-14.6,17.3],0),
        ('rear_slab','水下景观·后排板楼',[6.8,4.4,16.0],5,'slab',[8.0,-20.5,-6.5],0),
    ]
    components = [dict(key=k,name=n,asset_id='SEA-SCENE-SUBMERGED-'+k.upper().replace('_','-'),
        semantic_family=style,category='underwater_scenic_building',scope='scene_local',
        size_blender_xyz=size,floors=floors,style=style,triangle_budget=1000,
        origin='bottom_center',front_axis='+Y',allowed_rotation='Euler XYZ',
        placement_godot=pos,rotation_y_degrees=rot,collision='none',interactive=False)
        for k,n,size,floors,style,pos,rot in items]
    write(D/'component_plan.json',dict(schema='sea.scene_component_plan',version='v001',status='frozen_before_geometry',
        reference='reference.jpg',reference_sha256=sha(D/'reference.jpg'),
        reference_license='user_supplied_reference_commercial_rights_pending',
        palette='art_source/shared/palettes/sea_cozy_8x8_512.png',
        palette_sha256=sha(R/'art_source/shared/palettes/sea_cozy_8x8_512.png'),
        unique_component_count=6,components=components,
        budget_basis='User single building <=1000 faces; enforce evaluated/exported triangles <=1000, all attached geometry included',
        camera_interpretation='High oblique view: rounded tall block left, slender block in rear water channel, terraced block beside existing sunroom base right, two lower flat roofs in front. Hidden elevations inferred.',
        ownership='Six individually loadable decorative buildings. Existing sunroom, its seven-floor base, salvage, navigation and water materials protected; TSCN owns final placement.',
        coordinate_mapping='Blender (x,y,z) -> Godot (x,z,-y)',
        art_direction='Teal concrete, broad turquoise roof plates and layered cornices, dark blue recessed window bands, vertical piers, occasional coral paint scars. Real single-segment bevel on silhouette edges. No emissive materials.'))
    print('FROZEN',len(components),'independent buildings; max 1000 exported triangles each')
