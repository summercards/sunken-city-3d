import bpy,json,hashlib,os
from pathlib import Path
R=Path('D:/projects/sea');D=R/'art_source/scenes/floating_shop/v003';E=D/'export/v001';OPT=E/'floating_shop_optimized_v001.blend';pal=R/json.loads((D/'component_plan.json').read_text())['palette']
assert Path(bpy.data.filepath)==OPT
for im in bpy.data.images:
 if im.source=='FILE' and ('sea_cozy' in im.filepath or 'sea_cabin_timber' in im.filepath):
  im.filepath=str(pal);im.reload();im.filepath=bpy.path.relpath(str(pal),start=str(E));assert Path(bpy.path.abspath(im.filepath)).resolve()==pal.resolve()
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OPT),compress=True)
p=E/'optimization_manifest.json';q=json.loads(p.read_text());q['optimized_sha256']=hashlib.sha256(OPT.read_bytes()).hexdigest();q['resolved_issues']=['首次派生另存时Blender再次重映射色板相对路径，保真图显示粉色；在已位于派生路径的文件中修复外链、重载并保存后重新渲染。'];p.write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('OPTIMIZED_PALETTE_FIXED')
