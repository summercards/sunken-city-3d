"""Freeze the reference skiff contract before Blender creates geometry."""
import hashlib, json, os, shutil, struct
from pathlib import Path
R = Path(__file__).resolve().parents[3]
D = R / 'art_source/scenes/reference_skiff/v001'
W = Path(os.environ.get('SEA_WORK_ROOT', R.parent/'sea-work'))/'reference_skiff_v001'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p, value):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def measure():
    d=R/'godot/assets/baked'; meta=json.loads((d/'boat.json').read_text())
    def floats(p): return struct.unpack('<'+'f'*(p.stat().st_size//4),p.read_bytes())
    vertices=floats(d/'boat_geoms.bin'); instances=floats(d/'boat_instances.bin'); parts=[]
    for b in meta['batches']:
        if b['geom'] not in (0,1): continue
        g=meta['geoms'][b['geom']]; points=[]
        for k in range(b['count']):
            xf=instances[(b['instOff']+k)*16:(b['instOff']+k+1)*16]
            for j in range(g['vcount']):
                v=vertices[g['pOff']+j*3:g['pOff']+j*3+3]
                points.append([sum(xf[a*4+i]*v[i] for i in range(3))+xf[a*4+3] for a in range(3)])
        parts.extend(points)
    return {'min':[min(p[i] for p in parts) for i in range(3)],'max':[max(p[i] for p in parts) for i in range(3)]}
if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(); parser.add_argument('reference',type=Path); args=parser.parse_args()
    D.mkdir(parents=True,exist_ok=True); W.mkdir(parents=True,exist_ok=True)
    if (D/'reference_skiff.blend').exists(): raise RuntimeError('Preserve finished source; create a new version instead')
    shutil.copy2(args.reference,D/'reference.png')
    items=[('hull','黄白敞口船壳','structure'),('gunwale','奶白舷边与金黄内沿','structure'),
           ('floor_board','暖木底板','structure'),('bench','横向木座板','structure'),
           ('rib','内舷木肋','structure'),('outboard','白盖灰紫船外机','fitting'),
           ('luggage','绿色帆布行李包','fitting'),('fender','橄榄绿防撞浮球','fitting'),
           ('oar','圆杆宽叶木船桨','fitting'),('oarlock','金属桨架','fitting'),
           ('cleat','系缆羊角','fitting'),('rope_coil','盘绕缆绳','fitting')]
    components=[dict(key=k,name=n,asset_id='SEA-SCENE-SKIFF-'+k.upper().replace('_','-'),
        semantic_family=k,category=c,scope='scene_local',origin='bottom_center',front_axis='+Y',
        allowed_rotation='full Euler XYZ; oar runtime pivot is a wrapper',triangle_budget=6000)
        for k,n,c in items]
    bounds=measure()
    plan=dict(schema='sea.scene_component_plan',version='v001',status='frozen_before_geometry',
        reference='reference.png',reference_sha256=sha(D/'reference.png'),
        reference_license='user_supplied_reference_commercial_rights_pending',
        palette='art_source/shared/palettes/sea_cozy_8x8_512.png',
        palette_sha256=sha(R/'art_source/shared/palettes/sea_cozy_8x8_512.png'),
        dimensions=dict(legacy_hull_godot=bounds,size=[bounds['max'][i]-bounds['min'][i] for i in range(3)],
            rule='Match hull+gunwale envelope exactly; accessories and oar sweep excluded; no gameplay scale changes',
            godot_waterline_y=0,blender_front='+Y',godot_front='-Z',mapping='(x,y,z)->(x,z,-y)',
            character_anchor_godot=[0,.62,-.30],collision='Existing WaterNavigation/Boat owns collision; pure visual components'),
        legacy_sha256={p.relative_to(R).as_posix():sha(p) for p in (R/'godot/assets/baked').glob('boat*') if p.is_file()},
        components=components,unique_component_count=len(components),
        art_direction='Pointed raised bow, broad flat transom, yellow hull/cream rim, individual honey planks, three benches, lavender-white outboard, green bag, two fenders and two wooden oars. Retain existing navigation lantern as separate reused runtime asset.',
        budget='No user triangle cap; modest rounded hard edges, no texture detail geometry')
    write(D/'component_plan.json',plan); print(json.dumps(plan['dimensions'],ensure_ascii=False,indent=2))
