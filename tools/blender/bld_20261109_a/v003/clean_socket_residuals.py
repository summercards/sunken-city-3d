"""Remove independently measured microscopic cutter residues, then refresh signatures."""
import bpy,bmesh,json,hashlib,math
from pathlib import Path
from mathutils import Vector,Matrix
R=Path('D:/projects/sea');D=R/'art_source/scenes/bld_20261109_a/v003';W=Path('D:/projects/sea-work/bld_20261109_a/v003');S=D/'bld_20261109_a_v003.blend'
assert Path(bpy.data.filepath).resolve()==S.resolve()
w=json.loads((W/'geometry_witness.json').read_text(encoding='utf-8'));report=json.loads((W/'slot_probe_report.json').read_text(encoding='utf-8'));assert w['source_sha256']==report['source_sha256']==hashlib.sha256(S.read_bytes()).hexdigest()
cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];byobj={a['object']:a for a in w['objects']};sc=bpy.context.scene
scratch=bpy.data.collections.new('V003_RESIDUE_SCRATCH');sc.collection.children.link(scratch)
def volume(o):
 bm=bmesh.new();bm.from_mesh(o.data);v=abs(bm.calc_volume(signed=True));bm.free();return v
for r in report['cuts']:
 if r.get('exact_intersection_volume_m3',0)<1e-8:continue
 old=w['cuts'][r['cut_index']];host=bpy.data.objects[old['host_object']];shift=Vector(byobj[host.name]['rebase']);pad=Vector((.001,.001,.001));lo=Vector(old['bounds_min'])-shift-pad;hi=Vector(old['bounds_max'])-shift+pad
 scratch.objects.link(host);bpy.context.view_layer.update();x,y,z=(hi+lo)/2;dx,dy,dz=(hi-lo)/2;vs=[(x+a*dx,y+b*dy,z+c*dz) for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 me=bpy.data.meshes.new('residue_cutter');me.from_pydata(vs,[],[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]);me.update();cutter=bpy.data.objects.new('residue_cutter',me);scratch.objects.link(cutter)
 before=volume(host);mod=host.modifiers.new('ClearMeasuredResidual','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
 with bpy.context.temp_override(scene=sc,view_layer=sc.view_layers[0],object=host,active_object=host,selected_objects=[host],selected_editable_objects=[host]):bpy.ops.object.modifier_apply(modifier=mod.name)
 after=volume(host);scratch.objects.unlink(host);bpy.data.objects.remove(cutter,do_unlink=True)
 w['cuts'].append({'label':'cleanup_measured_residual_'+str(r['cut_index']),'host_object':host.name,'bounds_min':list(lo+shift),'bounds_max':list(hi+shift),'volume_before':before,'volume_after':after,'removed_volume':max(0,before-after),'topology_changed':True,'expanded_clearance_m':.001})
 # All revised faces get a nonzero UV island in the original per-object swatch.
 color=host.get('palette_color','plaster');plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));cells=json.loads((R/plan['palette']).with_suffix('.json').read_text(encoding='utf-8'))['cells'];cell=next(a for a in cells if a['name']==color);cx=(cell['column']+.5)/8;cy=1-(cell['row']+.5)/8
 for olduv in list(host.data.uv_layers):host.data.uv_layers.remove(olduv)
 uv=host.data.uv_layers.new(name='PaletteUV');uv.active_render=True
 for f in host.data.polygons:
  for j,li in enumerate(f.loop_indices):uv.data[li].uv=(cx+.027*math.cos(math.tau*j/f.loop_total),cy+.027*math.sin(math.tau*j/f.loop_total))
bpy.data.collections.remove(scratch)
for e in cat:
 c=bpy.data.collections[e['collection']];pts=[v.co for o in c.objects for v in o.data.vertices];lo=Vector([min(v[j] for v in pts) for j in range(3)]);hi=Vector([max(v[j] for v in pts) for j in range(3)]);e['bounds_size']=list(hi-lo);e['triangles']=e['polygons']=0;h=hashlib.sha256()
 for o in c.objects:
  o.data.calc_loop_triangles();e['triangles']+=len(o.data.loop_triangles);e['polygons']+=len(o.data.polygons)
  for v in o.data.vertices:h.update((','.join(format(float(q),'.6f') for q in v.co)+';').encode())
 e['geometry_fingerprint']=h.hexdigest()
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(S),compress=True);w['source_sha256']=hashlib.sha256(S.read_bytes()).hexdigest()
(D/'catalog.json').write_text(json.dumps({'schema':'sea.component_catalog','components':cat},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(W/'geometry_witness.json').write_text(json.dumps(w,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('MEASURED_RESIDUES_REMOVED',len(w['cuts']),w['source_sha256'])
