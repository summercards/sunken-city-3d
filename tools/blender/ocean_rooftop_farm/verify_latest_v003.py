from pathlib import Path
code=Path('D:/projects/sea/tools/blender/ocean_rooftop_farm/verify_v002.py').read_text(encoding='utf-8').replace('/v002','/v003').replace('farm_v002.blend','farm_v003.blend').replace("startswith('ORF2_屋顶')","startswith('ORF3_屋顶')").replace('len(cat)==39 and len(src.children)==39','len(cat)==48 and len(src.children)==48').replace("'component_count':39","'component_count':48").replace('ORF2_VERIFY','ORF3_VERIFY')
extra='''
# latest user request: upper three floors only, six flights and one broken hanging fragment.
flights=[o for o in inst if o.get('component_id')=='SEA-SCENE-ORF2-STAIR_FLIGHT']
check('only_upper_three_floors_six_flights',len(flights)==6 and all(o.location.z>44 for o in flights),[o.location.z for o in flights])
check('one_broken_hanging_fragment',sum(o.get('component_id')=='SEA-SCENE-ORF2-BROKEN_FLIGHT' for o in inst)==1)
check('48_distinct_component_collections',len({e['collection'] for e in cat})==48)
# all walkable mesh surfaces sampled independently through BVH, not comments/route nodes.
from mathutils.bvhtree import BVHTree
bvhs=[]
for ob in inst:
 if ob.get('component_id','') not in ['SEA-SCENE-ORF2-STAIR_FLIGHT','SEA-SCENE-ORF2-STAIR_LANDING','SEA-SCENE-ORF2-STAIR_LANDING_OPEN','SEA-SCENE-ORF2-ROOF_ENTRY','SEA-SCENE-ORF2-ROOF']:continue
 for meshob in ob.instance_collection.objects:
  pts=[ob.matrix_world@meshob.matrix_world@v.co for v in meshob.data.vertices]
  bvhs.append(BVHTree.FromPolygons(pts,[list(p.vertices) for p in meshob.data.polygons]))
def support(x,y,z):
 return any(bvh.ray_cast(Vector((x,y,z+.28)),Vector((0,0,-1)),.55)[0] is not None for bvh in bvhs)
fail=[]
for f in range(9,12):
 for j in range(14):
  if not support(25,-3+(j+.5)*.3,f*5+(j+1)*2.5/14):fail.append(['a',f,j])
  if not support(27,1.2-(j+.5)*.3,f*5+2.5+(j+1)*2.5/14):fail.append(['b',f,j])
check('all_84_remaining_steps_have_real_support',not fail,fail)
entryfail=[]
for x in [22.5,23,23.5,24,24.5,24.8,25,25.5,26,26.5,27]:
 if not support(x,-3.8,60):entryfail.append(x)
check('roof_entry_supported_without_duplicate_bridge_deck',not entryfail,entryfail)
check('roof_entry_has_no_coplanar_deck',all(abs(p.normal.z)<.99 or p.area<.8 for o in bpy.data.collections[next(e['collection'] for e in cat if e['key']=='roof_entry')].objects for p in o.data.polygons))
# actual axis-aligned top deck boundary: roof maxX and landing minX touch, no coplanar overlap.
roof=next(o for o in inst if o.get('component_id')=='SEA-SCENE-ORF2-ROOF');land=next(o for o in inst if o.get('component_id')=='SEA-SCENE-ORF2-STAIR_LANDING_OPEN')
rpts=[roof.matrix_world@v.co for ob in roof.instance_collection.objects for v in ob.data.vertices];lpts=[land.matrix_world@v.co for ob in land.instance_collection.objects for v in ob.data.vertices]
rx=max(v.x for v in rpts);lx=min(v.x for v in lpts);check('roof_landing_edge_joint_no_coplanar_overlap',abs(rx-lx)<.005,{'roof_max_x':rx,'landing_min_x':lx})
# dark matte role truly has low metal and high roughness.
metal=next(m for c in src.children for ob in c.objects for m in ob.data.materials if m.name=='ORF2_FINAL_SEA_Metal');bs=next(n for n in metal.node_tree.nodes if n.type=='BSDF_PRINCIPLED');check('all_metal_is_matte',bs.inputs['Metallic'].default_value<=.2 and bs.inputs['Roughness'].default_value>=.8)
# locked original crop beds / furniture unaffected, frame/edge plants explicitly amended by latest request.
lock=json.loads((W/'locked_scope.json').read_text(encoding='utf-8'));bad=[];checked=0
for r in lock:
 o=s.objects.get(r['name'])
 if not o:bad.append(r['name']);continue
 key=o.get('component_id','').split('-')[-1].lower()
 if key in ['greenhouse','tank','wind','solar','grass','tuft']:continue
 fp=hashlib.sha256(repr([[tuple(v.co) for v in x.data.vertices] for x in o.instance_collection.objects if x.type=='MESH']).encode()).hexdigest()
 mm=[list(v) for v in o.matrix_world]
 if fp!=r['geometry'] or max(abs(mm[i][j]-r['matrix'][i][j]) for i in range(4) for j in range(4))>.0001:bad.append(r['name'])
 checked+=1
check('protected_crops_furniture_paths_preserved',not bad,{'checked':checked,'failures':bad[:10]})
'''
code=code.replace('# independent component files actually reopened.',extra+'\n# independent component files actually reopened.')
exec(compile(code,'verify_latest_v003','exec'))
