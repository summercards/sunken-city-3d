"""v003 freezes slope modules and curved, genuinely disconnected rail route before geometry."""
import copy,hashlib,json,math
from pathlib import Path
R=Path(__file__).resolve().parents[3];OLD=R/'art_source/scenes/sunken_city/v002';D=OLD.parent/'v003'
assert D.is_dir() and not (D/'sunken_city_v003.blend').exists()
P=copy.deepcopy(json.loads((OLD/'component_plan.json').read_text(encoding='utf-8')))
P.update(version='v003',status='frozen_before_geometry',revision='terrain_relief_curved_broken_tram',previous_source='art_source/scenes/sunken_city/v002/sunken_city_v002.blend',previous_source_sha256=hashlib.sha256((OLD/'sunken_city_v002.blend').read_bytes()).hexdigest())
P['added_references']=[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [Path.home()/'.workbuddy/clipboard-images/clipboard-2026-11-05T06-54-35-432Z-bf769b76.jpg',Path.home()/'.workbuddy/clipboard-images/clipboard-2026-11-05T06-54-36-144Z-98d50e8b.jpg']]
# Production budget: unused T junction and decorative-crack-only roadway are superseded, not deleted.
# The latter is replaced by the same flat street on flat zones; broad original damage still exists in buildings/rubble.
retired={'t_junction':'unused definition, not instantiated in either saved version','canal_end':'two cap modules superseded by continuous canal_segment ends in the authorized terrain/rail overhaul; old source kept v002, no runtime deletion'}
P['retired_components']=[dict(c,retirement_reason=retired[c['key']],retained_source='v002',not_in_current_layout=True) for c in P['components'] if c['key'] in retired]
P['components']=[c for c in P['components'] if c['key'] not in retired]
for key,name,family,category,size in [('terrain_ramp','街区缓坡_24米高差4.8米','terrain_ramp','ground',[24,24,5.4]),('viaduct_curve','电车高架_26米半径45度弯道','viaduct','ground',[26,26,16.5])]:
    P['components'].append(dict(key=key,slug=key,name=name,component_family=family,category=category,component_id='SEA-SCENE-SCITY-'+key.replace('_','-').upper(),building_class='underwater',scope='scene_local',origin='bottom_center',front_axis='-Y',allowed_rotations_y_deg=[0,45,90,135,180,225,270,315],size_design_m=size,collision=False,interactive=False,emission=False,instance_count=0))
assert len(P['components'])==50
P['component_budget']={'limit':50,'planned':50,'remaining':0}
P['terrain_contract']={'type':'continuous stepped-slope city court; flat terrace pads and broad ramps, no random vertex noise','base_paving_z_m':-61.3,'relief_m':4.8,'ramp_run_m':24,'ramp_angle_deg':math.degrees(math.atan(4.8/24)),
    'profile_xz':[[-120,0],[-72,0],[-48,-4.8],[24,-4.8],[48,0],[120,0]],
    'plateau_world_z_m':[-61.3,-66.1],'buildings':'rigid geometry, lowest foundation vertices match local height; partially buried lower storey on ramps is intentional sediment settlement, never free floating',
    'terrain_seams':'100 logical 24m cells; ramp edges share exact world height, pavement curbs may have their authored 0.2m step',
    'canal':'the four shared canal modules and two ends are warped on the same linear ramp, not removed',
    'protected_scope':'all non-terrain/bridge component geometry locked; XY of existing buildings preserved; source v002 unchanged'}
# Route commands at deck top -50.8. A right arc is the same reusable undirected arc traversed backwards.
P['rail_extension']={'start_xy':[-78,-48],'heading_deg':0,'deck_top_z_m':-50.8,'radius_m':26,'curve_sweep_deg':45,'gap_m':15,
    'commands':[{'kind':'curve','turn':'left'},{'kind':'straight','length_m':12},{'kind':'curve','turn':'right'},
                {'kind':'broken'},{'kind':'gap','length_m':15},{'kind':'straight','length_m':20},
                {'kind':'curve','turn':'right'},{'kind':'curve','turn':'right'},{'kind':'straight','length_m':20}],
    'tram_additions':'one on 12m tangent before the fracture and one on the 20m straight after it',
    'break_policy':'fractured deck and rails terminate before the gap; no invisible beam or connected rail crosses it; debris lies below on terrain'}
P['floor_contract']['paving_top_z_m']=-61.3
P['floor_contract']['revision']='v003 height profile overrides v001/v002 all-flat rule; full XY coverage unchanged'
for c in P['components']:c['version']='v003'
(D/'component_plan.json').write_text(json.dumps(P,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('FROZEN_V003',len(P['components']),'components, relief',P['terrain_contract']['relief_m'],'slope',P['terrain_contract']['ramp_angle_deg'])
