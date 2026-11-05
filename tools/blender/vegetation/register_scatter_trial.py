"""Register the real third-party preview assets without marking them production-approved."""
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[3];D=R/'art_source/vegetation/proton_scatter_trial/v001'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def write(p,v):p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
report=Path(sys.argv[1]).resolve();run=read(report)
for name in ['visual-proton-scatter','visual-proton-preview']:assert run['results'][name]['passed'],name
index=read(R/'assets/registry/ledger_index.json');route=index['domains']['vegetation']['ledger'];p=R/route;before=p.read_bytes();book=read(p);by_id={r['asset_id']:r for r in book['assets']};updates={}
pin=read(R/'godot/addons/proton_scatter/sea_vendor_pin.json')
for key,label in [('grass','原版草A'),('grass_2','原版草B'),('bush','原版灌木')]:
 aid='SEA-VEG-PROTON-DEMO-'+key.upper().replace('_','-');source=f'godot/addons/proton_scatter/demos/assets/models/{key}.glb';manifest=f'art_source/vegetation/proton_scatter_trial/v001/{key}_manifest.json'
 row=dict(asset_id=aid,name='ProtonScatter '+label,domain='vegetation',suite='proton_native_trial',version='upstream_7198cc0',scope='preview',category='third_party_vegetation',source=source,source_sha256=sha(R/source),manifest=manifest,runtime_path=source,runtime_sha256=sha(R/source),material_binding='ScatterItem.override_material',material='godot/addons/proton_scatter/demos/assets/materials/'+('m_bush' if key=='bush' else 'm_grass')+'.tres',stage='trial_verified_production_pending',license='upstream_MIT_models_demo_texture_terms_pending',provenance=pin,consumers=['proton_rooftop_preview'],consumer_features=['SEA-AMBIENT','SEA-ASSET'],water_layer='surface',water_layer_role='none',collision=False,verification=dict(native_scatter='passed',real_render='passed',saved_preview_reopen='passed',production_clock_integration='pending',user_art_acceptance='pending',evidence=[str(report),'docs/development/2026-11-05_proton_scatter_trial.md']))
 updates[aid]=row;write(R/manifest,dict(row,asset_ledger=route+'#'+aid))
aid='SEA-VEG-PROTON-ROOFTOP-TRIAL';source='art_source/vegetation/proton_scatter_trial/v001/rooftop_scatter_authoring.tscn';runtime='godot/scenes/vegetation_authoring/proton_rooftop_preview.tscn';manifest='art_source/vegetation/proton_scatter_trial/v001/asset_manifest.json'
row=dict(asset_id=aid,name='ProtonScatter天台可编辑试刷场景',domain='vegetation',suite='proton_native_trial',version='v001',scope='preview',category='scatter_authoring_preset',source=source,source_sha256=sha(R/source),manifest=manifest,runtime_path=runtime,runtime_sha256=sha(R/runtime),stage='trial_verified_production_pending',license='MIT_addon_and_models_demo_texture_terms_pending',dependencies=list(updates),consumers=['proton_rooftop_preview'],consumer_features=['SEA-AMBIENT','SEA-ASSET'],verification=dict(actual_generators=2,instances=11542,render_batches=60,native_shader='upstream grass.gdshader unchanged',saved_preview_reopen='passed',production_default='v003 unchanged',evidence=[str(report),'docs/development/2026-11-05_proton_scatter_trial.md']))
updates[aid]=row;write(R/manifest,dict(row,asset_ledger=route+'#'+aid))
other={r['asset_id'] for domain,t in index['domains'].items() if domain!='vegetation' for r in read(R/t['ledger'])[t['asset_key']]};assert not other.intersection(updates)
book['assets']=[updates.get(r['asset_id'],r) for r in book['assets']]+[r for aid,r in updates.items() if aid not in by_id];assert p.read_bytes()==before;write(p,book)
p=R/'assets/registry/current_source_index.json';src=read(p);src['sources']=[{k:r[k] for k in ['asset_id','source','source_sha256','manifest']} for t in index['domains'].values() for r in read(R/t['ledger'])[t['asset_key']]];write(p,src)
p=R/index['runtime_inventory'];before=p.read_bytes();inv=read(p);saved={r['path']:r for r in inv['resources']}
for row in updates.values():
 path=row['runtime_path'];entry=dict(path=path,sha256=sha(R/path),bytes=(R/path).stat().st_size,asset_id=row['asset_id'],status='trial_verified_excluded_from_release')
 if path in saved:saved[path].update(entry)
 else:inv['resources'].append(entry)
inv['resources'].sort(key=lambda r:r['path']);assert p.read_bytes()==before;write(p,inv)
print('Registered 3 native demo assets and 1 editable trial preset; no production approval inferred.')
