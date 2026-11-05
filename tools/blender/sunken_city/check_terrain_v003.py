"""Independent slope/rail acceptance. Samples real triangle surfaces; does not trust authored height fields."""
import bpy,hashlib,json,math,os
from pathlib import Path
from array import array
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/sunken_city/v003';W=R.parent/'sea-work/sunken_city/v003'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components'];C={c['key']:c for c in CAT}
S=bpy.data.scenes['沉没旧城_完整参考布局_v003'];bpy.context.view_layer.update();errors=[];checks=0

def ck(ok,msg):
    global checks
    checks+=1
    if not ok:errors.append(msg)

def mesh(o):return next(q for q in o.instance_collection.objects if q.type=='MESH')
# Build one BVH per floor master, cast rays in actual local coordinates and return highest face.
BV={}
for c in CAT:
    if c['category']=='ground':
        ob=next(q for q in bpy.data.collections[c['collection']].objects if q.type=='MESH');m=ob.data
        BV[c['key']]=BVHTree.FromPolygons([v.co for v in m.vertices],[list(f.vertices) for f in m.polygons],all_triangles=False)

def top(o,key,x,y):
    inv=o.matrix_world.inverted();origin=inv@Vector((x,y,100));direction=(inv.to_3x3()@Vector((0,0,-1))).normalized()
    loc,n,index,dist=BV[key].ray_cast(origin,direction,300)
    return (o.matrix_world@loc).z if loc is not None else None
floorkeys={'street_intact','street_split','junction','plaza_tile','canal_segment','terrain_ramp'}
tiles={}
for a in P['instances']:
    if a['key'] not in floorkeys:continue
    o=bpy.data.objects[a['instance_id']];x,y=o.location.x,o.location.y
    # Published logical cell centre has no geometry-specific world shift.
    if abs((x+108)/24-round((x+108)/24))<1e-3 and abs((y+108)/24-round((y+108)/24))<1e-3:
        xy=(round(x),round(y));ck(xy not in tiles,'duplicate floor '+str(xy));tiles[xy]=(o,a['key'])
ck(len(tiles)==100,'expected full 100 floor tiles')
maxgap=0;badseams=[];seamcount=0
for (x,y),(o,key) in tiles.items():
    for dx,dy in ((24,0),(0,24)):
        q=tiles.get((x+dx,y+dy))
        if not q:continue
        oo,kk=q;seamcount+=1
        for t in (-.42,-.23,0,.23,.42):
            # Avoid the exact closed solid's end-face numerical ambiguity with 0.02m inset.
            if dx:
                ax,ay=x+12-.02,y+t*24;bx,by=x+12+.02,ay
            else:
                ax,ay=x+t*24,y+12-.02;bx,by=ax,y+12+.02
            za=top(o,key,ax,ay);zb=top(oo,kk,bx,by)
            if za is None or zb is None:
                ck(False,'floor ray miss '+str((x,y,dx,dy,t)));continue
            gap=abs(za-zb);maxgap=max(maxgap,gap)
            # Canal beds terminate at a designed retaining-bank step. Only its pedestrian side bands
            # must meet full plaza/road at <=0.22m curb. The channel itself is explicitly open, not a missing tile.
            canal=(key=='canal_segment' or kk=='canal_segment')
            canal_channel=canal and dy and abs(t)<.15
            allow=2.3 if canal_channel else .225
            ck(gap<=allow,'floor seam step %.3f at %s'%(gap,(x,y,dx,dy,t)))
            if gap>allow:badseams.append([x,y,dx,dy,t,za,zb])
ck(seamcount==180,'ground shared-edge count')
# Height is visible and measured from the actual surfaces, not merely different instance roots.
heights=[]
for (x,y),(o,key) in tiles.items():
    z=top(o,key,x,y+.3)
    if z is not None:heights.append(z)
ck(max(heights)-min(heights)>4.5,'no visible terrain relief')
# Existing bridge connection must begin at the real end of original intact span, not a freestanding duplicate.
segs=[a for a in P['rail_extension']['actual_segments'] if a['key'] in ('viaduct_curve','viaduct_intact','viaduct_broken')]
ck(bool(segs),'no rail segments')
first=Vector(segs[0]['start']);old=bpy.data.objects.get('viaduct_intact_instance_002')
ck(old is not None,'missing original second span before new curve')
if old:
    # Deck end 10m along source X at exact original deck top. Pier extension shifts local deck to 15.3.
    expected=old.matrix_world@Vector((10,0,15.3));ck((expected-first).length<.02,'old bridge connection offset '+str(list(expected-first)))
gap=P['rail_extension']['actual_gap'];gs=Vector(gap['start']);ge=Vector(gap['end']);ck((ge-gs).length>=14.99,'short bridge gap')
connections=[]
for a,b in zip(segs,segs[1:]):
    dist=(Vector(a['end'])-Vector(b['start'])).length
    break_pair=a['key']=='viaduct_broken'
    ck(abs(dist-(gap['length_m'] if break_pair else 0))<.02,'bridge connector gap '+str((a['name'],b['name'],dist)))
    connections.append(dict(a=a['name'],b=b['name'],distance_m=dist,intentional_break=break_pair))
# Inspect actual triangles at bridge height in the central 70% of missing span: no solid/rail secretly bridges gap.
bridgekeys={'viaduct_intact','viaduct_broken','viaduct_curve'}
gap_hits=[]
for a in P['instances']:
    if a['key'] not in bridgekeys:continue
    o=bpy.data.objects[a['instance_id']]
    for t in (.2,.4,.6,.8):
        p=gs.lerp(ge,t)
        z=top(o,a['key'],p.x,p.y)
        if z is not None and z>-52:gap_hits.append((o.name,t,z))
ck(not gap_hits,'solid geometry spans intentional gap '+str(gap_hits))
# Tram centres are aligned to published segment tangent and sit just over rail top.
trams=[]
for a in P['rail_extension']['actual_segments']:
    if a['key']!='tram_wreck':continue
    o=bpy.data.objects[a['name']];ck(abs(math.degrees(o.rotation_euler.z)-a['heading_deg'])<.01,'tram orientation '+o.name)
    ck(abs(o.location.z-(-50.55))<.02,'tram wheel contact '+o.name)
    trams.append(o.name)
ck(len(trams)==2,'extra tram count')
# Unchanged v002 source plus static architecture mesh signatures.
lock=json.loads((W/'terrain_scope_lock.json').read_text(encoding='utf-8'))
def sig(me):
    h=hashlib.sha256()
    for data,field,typ,n in [(me.vertices,'co','f',3),(me.loops,'vertex_index','i',1),(me.polygons,'material_index','i',1),(me.uv_layers['PaletteUV'].data,'uv','f',2)]:
        buf=array(typ,[0])*(len(data)*n);data.foreach_get(field,buf);h.update(buf.tobytes())
    return h.hexdigest()
locked=0
for c in CAT:
    if c['category']=='ground':continue
    if c['key'] in lock['geometry']:
        ck(sig(next(q for q in bpy.data.collections[c['collection']].objects if q.type=='MESH').data)==lock['geometry'][c['key']],'rigid source geometry changed '+c['key']);locked+=1
ck(hashlib.sha256((R/P['previous_source']).read_bytes()).hexdigest()==P['previous_source_sha256'],'v002 source changed')
report=dict(passed=not errors,checks=checks,errors=errors,terrain_tiles=len(tiles),shared_edges=seamcount,maximum_step_including_canal_channel_m=maxgap,
    invalid_seams=badseams,actual_surface_height_range_m=[min(heights),max(heights)],relief_m=max(heights)-min(heights),bridge_connectors=connections,
    gap=gap,gap_solid_hits=gap_hits,additional_trams=trams,unchanged_rigid_components=locked)
(W/'terrain_bridge_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('TERRAIN_BRIDGE_CHECK',checks,'checks',len(errors),'errors',errors)
assert not errors,errors
