"""Recover package output from the already saved mother after a Blender library-write crash."""
import bpy, json, hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/reference_skiff/v001'
P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'));CAT=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components']
bpy.context.preferences.filepaths.save_version=0
for e in CAT:
    key=e['key'];pkg=D/'component_packages'/key;pkg.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(D/'reference_skiff.blend'))
    sc=bpy.data.scenes.new('独立组件_'+key);sc.collection.children.link(bpy.data.collections[e['collection']]);sc.world=bpy.data.worlds['奶蓝摄影棚'];bpy.context.window.scene=sc
    for other in list(bpy.data.scenes):
        if other!=sc:bpy.data.scenes.remove(other)
    bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
    path=pkg/(key+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
    m=dict(asset_id=e['asset_id'],asset_ledger='assets/registry/ledgers/scenes.json#'+e['asset_id'],version='v001',source=path.relative_to(R).as_posix(),source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),component=e,reference_sha256=P['reference_sha256'],license=P['reference_license'],stage='source_created_pending_reopen_validation')
    (pkg/'asset_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('PACKAGES_SAVED',len(CAT),flush=True)
