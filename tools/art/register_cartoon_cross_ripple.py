"""Register the original cross texture, preserving unrelated/previous hash drift."""
import argparse,hashlib,json,os
from pathlib import Path
R=Path(__file__).resolve().parents[2];D=R/'art_source/vfx/water_cross_ripple/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'cartoon_cross_ripple_v001'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--verification',type=Path,required=True);args=ap.parse_args()
    report=json.loads(args.verification.read_text(encoding='utf-8'))
    for name in ['visual-submerged-water-light','water-params']:assert report['results'][name]['passed'],name
    mpath=D/'asset_manifest.json';m=json.loads(mpath.read_text(encoding='utf-8'));aid=m['asset_id']
    assert sha(R/m['source'])==m['source_sha256'] and sha(R/m['runtime_path'])==m['runtime_sha256']
    assert sha(R/m['raster_source'])==m['raster_source_sha256']
    idx=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'));route=idx['domains']['vfx'];book=R/route['ledger']
    ledger=json.loads(book.read_text(encoding='utf-8'));stage='source_runtime_verified_original_authored'
    evidence=[str(args.verification.resolve())];m.update(stage=stage,verification=evidence,shader='godot/shaders/submerged_caustic_light.gdshaderinc',
        material_consumers=['godot/assets/materials/water.tres','godot/assets/materials/water_absorption.tres'],
        import_settings=dict(path=m['runtime_path']+'.import',sha256=sha(R/(m['runtime_path']+'.import')),compression='lossless',mipmaps=True,color_space='linear data'))
    row=dict(asset_id=aid,name='水下卡通十字波纹灰度贴图',domain='vfx',stage=stage,version='v001',
        source=m['source'],source_sha256=m['source_sha256'],manifest=mpath.relative_to(R).as_posix(),runtime_path=m['runtime_path'],runtime_sha256=m['runtime_sha256'],
        category='water_surface_texture',classification={'category':'vfx','subcategory':'water_light_mask'},license=m['license'],
        consumer_features=['SEA-OCEAN','SEA-ASSET'],verification=evidence,note='12 sparse vector-authored four-point crosses. 2048px master, 512px linear R8 runtime mask, repeat in both axes, no haze. Replaces broad noise caustics; all dayparts and two water schemes verified.')
    for domain,r in idx['domains'].items():
        for old in json.loads((R/r['ledger']).read_text(encoding='utf-8'))[r['asset_key']]:
            if old['asset_id']==aid:assert old['source']==row['source'], 'AssetID owned by another source'
    ledger[route['asset_key']]=[x for x in ledger[route['asset_key']] if x['asset_id']!=aid]+[row];write(book,ledger)
    source_rows=[]
    for domain,r in idx['domains'].items():
        source_rows.extend({k:x[k] for k in ['asset_id','source','source_sha256','manifest']} for x in json.loads((R/r['ledger']).read_text(encoding='utf-8'))[r['asset_key']])
    path=R/'assets/registry/current_source_index.json';sources=json.loads(path.read_text(encoding='utf-8'));sources['sources']=source_rows;write(path,sources)
    path=R/idx['runtime_inventory'];inv=json.loads(path.read_text(encoding='utf-8'));before=json.loads((W/'before-resource-hashes.json').read_text(encoding='utf-8'))
    changes=[]
    for resource in inv['resources']:
        p=resource['path']
        if p not in m['material_consumers']:continue
        accepted=resource['sha256']==before[p]
        changes.append(dict(path=p,before_sha256=before[p],after_sha256=sha(R/p),preexisting_baseline_matched=accepted,
            action='accepted own sampler binding change' if accepted else 'existing baseline drift preserved; only sampler addition reviewed'))
        if accepted:resource.update(bytes=(R/p).stat().st_size,sha256=sha(R/p))
    inv['resources']=[x for x in inv['resources'] if x['path']!=m['runtime_path']]
    inv['resources'].append(dict(path=m['runtime_path'],bytes=(R/m['runtime_path']).stat().st_size,sha256=m['runtime_sha256'],asset_id=aid,status=stage))
    inv['resources'].sort(key=lambda x:x['path']);write(path,inv)
    m['material_binding_changes']=changes;write(mpath,m)
    print('REGISTERED',aid,'and reviewed material bindings; preexisting drift retained')
