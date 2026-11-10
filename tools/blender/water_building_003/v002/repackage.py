exec(open('D:/projects/sea/tools/blender/water_building_003/v002/lib.py',encoding='utf8').read())
from pathlib import Path
# Export each package through a temporary dedicated scene with the collection renamed to AssetID.
PK=D/'component_packages'
for k,c in cols.items():
    aid=by[k]['asset_id']
    old=c.name
    c.name=aid
    p=PK/k; p.mkdir(parents=True,exist_ok=True)
    bpy.data.libraries.write(str(p/(k+'.blend')),{c},path_remap='ABSOLUTE',compress=True)
    c.name=old
print('repackaged',len(cols))
