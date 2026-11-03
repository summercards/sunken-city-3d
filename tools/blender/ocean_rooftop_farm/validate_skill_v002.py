import bpy,importlib.util,json,sys,math
from pathlib import Path
D=Path('D:/projects/sea/art_source/scenes/ocean_rooftop_farm/v002');W=Path('D:/projects/sea-work/ocean_rooftop_farm/v002')
path=Path.home()/'.workbuddy/skills/blender-game-prop-standard/scripts/validate_game_prop.py';sp=importlib.util.spec_from_file_location('prop_validator',path);mod=importlib.util.module_from_spec(sp);sp.loader.exec_module(mod)
def audit8(obj):
 layer=obj.data.uv_layers.get('PaletteUV');r={'object':obj.name,'polygon_count':len(obj.data.polygons),'valid_island_polygon_count':0,'missing_palette_uv':layer is None,'active_uv':obj.data.uv_layers.active.name if obj.data.uv_layers.active else '', 'active_render_uv':next((u.name for u in obj.data.uv_layers if u.active_render),''),'extra_uv_layers':[u.name for u in obj.data.uv_layers if u.name!='PaletteUV'],'bad_polygon_examples':[]}
 if layer:
  for p in obj.data.polygons:
   us=[layer.data[i].uv for i in p.loop_indices];cells={(math.floor(u.x*8),math.floor(u.y*8)) for u in us};ok=len(cells)==1 and all(.125<=((u.x*8)%1)<=.875 and .125<=((u.y*8)%1)<=.875 for u in us) and mod.uv_polygon_area(us)>=mod.MIN_UV_AREA
   if ok:r['valid_island_polygon_count']+=1
   elif len(r['bad_polygon_examples'])<8:r['bad_polygon_examples'].append(p.index)
 return r
mod.audit_palette_uv=audit8
rows=[]
for e in json.loads((D/'component_catalog.json').read_text(encoding='utf-8'))['components']:
 bpy.ops.wm.open_mainfile(filepath=str(D/'component_packages'/e['key']/(e['key']+'.blend')));sys.argv=['validate_game_prop.py','--','--max-materials','4','--shared-palette','D:/projects/sea/art_source/shared/palettes/sea_cabin_timber_8x8_512.png','--json',str(W/('skill_'+e['key']+'.json'))]
 try:mod.main();code=0
 except SystemExit as ex:code=ex.code
 rows.append({'key':e['key'],'passed':code==0})
(W/'skill_verification.json').write_text(json.dumps({'passed':all(x['passed'] for x in rows),'adapter':'sea 8x8 grid only; all other installed validator checks unchanged','components':rows},ensure_ascii=False,indent=2),encoding='utf-8');print('ORF2_SKILL_VERIFY',all(x['passed'] for x in rows),len(rows))
