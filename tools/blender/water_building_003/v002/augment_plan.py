import json, math
from pathlib import Path
P=Path('D:/projects/sea/art_source/scenes/water_building_003/v002/component_plan.json')
C=Path('D:/projects/sea/art_source/scenes/water_building_003/v002/catalog.json')
plan=json.loads(P.read_text(encoding='utf8'))
catalog={x['key']:x for x in json.loads(C.read_text(encoding='utf8'))}
form=plan['stylized_form']
items=[]
for c in plan['components']:
    key=c['key']; kind=c['kind']; item={'id':c['id'],'kind':kind}
    if kind=='plant':
        items.append(item); continue
    if kind=='no_volume':
        item.update(no_volume=True,thickness=c.get('thickness',.01),bevel=c.get('bevel',.012));items.append(item);continue
    if kind=='linear':
        item.update(d_bottom=c.get('d_bottom',.20),d_top=c.get('d_top',.18));items.append(item);continue
    ext=catalog.get(key,{}).get('bounds_size') or [1,1,1]
    ext=[max(float(x),.03) for x in ext]
    axis='xyz'[max(range(3),key=lambda i:ext[i])]
    r=float(c.get('rho',.02))
    if kind=='freestanding':
        bottom=1.0; top=1.0-r # negative rho -> top larger
    else:
        bottom=1.0; top=1.0-r
    item.update(extent=ext,taper_along=axis,bottom=bottom,top=top)
    if key=='awning': item.update(tilt_deg=7.0,tilt_kind='canopy')
    if key=='sign': item.update(tilt_deg=5.0,tilt_kind='sign_board')
    items.append(item)
form['components']=items
form['wall_thickness']=.2
form['relief'].update(layers=2,quoin_protrusion=.12)
plan['status']='source_built_visual_revision_pending'
P.write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('added stylized components',len(items))
