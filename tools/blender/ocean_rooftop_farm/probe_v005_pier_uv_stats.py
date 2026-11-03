import bpy, json, math
p=bpy.data.objects.get('ORF3_厚实混凝土结构柱_0'); assert p and p.type=='MESH'
me=p.data; pal=me.uv_layers.get('PaletteUV'); print('layers',[u.name for u in me.uv_layers],'active',me.uv_layers.active.name if me.uv_layers.active else None,'faces',len(me.polygons),'loops',len(pal.data) if pal else 0)
if pal:
 vals=[(d.uv.x,d.uv.y) for d in pal.data]
 print('minmax',min(x for x,y in vals),max(x for x,y in vals),min(y for x,y in vals),max(y for x,y in vals))
 # count by 8x8 palette cells
 cells={}
 for poly in me.polygons:
  u=sum(pal.data[li].uv.x for li in poly.loop_indices)/len(poly.loop_indices);v=sum(pal.data[li].uv.y for li in poly.loop_indices)/len(poly.loop_indices)
  k=(math.floor(u*8),math.floor(v*8));cells[k]=cells.get(k,0)+1
 print('cells',cells)
 print('bad',sum(1 for x,y in vals if not (0.01<x<0.99 and 0.01<y<0.99)))
