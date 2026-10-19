import bpy,json,math
from pathlib import Path
from mathutils import Matrix
LIB=Path('/Users/summercards/WorkBuddy/sea/art_source/environments/tower_zones/tower_district/source/common_components/v008');path=LIB/'component_instances.json';doc=json.loads(path.read_text());s=bpy.context.scene;s.frame_set(1);s.view_layers[0].update();ROOM=bpy.data.objects['ROOM_FRAME'].matrix_world.copy()
for rec in doc['instances']:
 ob=bpy.data.objects[rec['instance_id']];local=ROOM.inverted()@ob.matrix_world;pos,q,scale=local.decompose();e=q.to_euler('XYZ')
 rec['matrix_parent_local']=[list(row) for row in ob.matrix_basis];rec['matrix_room_local']=[list(row) for row in local];rec['position_m']=list(pos);rec['rotation_y_deg']=math.degrees(e.z);rec['rotation_euler_xyz_deg']=[math.degrees(x) for x in e];rec['scale']=list(scale)
for rig in doc['animation_rigs']:
 ob=bpy.data.objects[rig['name']];rig['matrix_parent_local']=[list(row) for row in ob.matrix_basis]
path.write_text(json.dumps(doc,ensure_ascii=False,indent=2));print('ALL_LOCAL_MATRICES_FROZEN_AFTER_VIEW_LAYER_UPDATE')
