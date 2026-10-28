"""Register only this reviewed kit; never accept hashes of unrelated assets."""
import argparse, hashlib, json
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/reference_skiff/v001'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--verification',type=Path,action='append',required=True);args=parser.parse_args()
    exp=json.loads((D/'export_manifest.json').read_text(encoding='utf-8'));plan=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
    assert sha(R/'godot/assets/textures/shared/sea_cozy_8x8_512.png')==plan['palette_sha256'],'runtime public palette must equal the source palette'
    evidence=[str(p.resolve()) for p in args.verification]
    observed={}
    for p in args.verification:
        report=json.loads(p.read_text(encoding='utf-8'));observed.update(report.get('results',{}))
    for name in ['reference-skiff','visual-reference-skiff','visual-boat-lamp']:
        assert name in observed and observed[name]['passed'],name+' must pass before runtime registration'
    stage='source_runtime_verified_provenance_pending';source=D/'reference_skiff.blend'
    assembly_id='SEA-SCENE-SKIFF-ASSEMBLY';manifest=D/'asset_manifest.json'
    write(manifest,dict(asset_id=assembly_id,asset_ledger='assets/registry/ledgers/scenes.json#'+assembly_id,
        source=source.relative_to(R).as_posix(),source_sha256=sha(source),version='v001',stage=stage,
        component_plan=(D/'component_plan.json').relative_to(R).as_posix(),component_catalog=(D/'catalog.json').relative_to(R).as_posix(),
        reference_sha256=plan['reference_sha256'],license=plan['reference_license'],
        optimized_source=exp['optimized_source'],optimized_sha256=exp['optimized_sha256'],
        runtime_path='godot/scenes/props/reference_skiff.tscn',
        dependencies=[e['asset_id'] for e in exp['components']]+['SEA-SCENE-SBR-LANTERN'],
        runtime_placement_owner='formal TSCN; JSON is trace/initialization only',verification=evidence,
        caveat='Only base skiff appearance replaced; ship upgrade visual tiers remain unimplemented. Old bake preserved. Navigation integration limitations are recorded in development evidence.'))
    route=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'))['domains']['scenes']
    path=R/route['ledger'];ledger=json.loads(path.read_text(encoding='utf-8'));ids={e['asset_id'] for e in exp['components']}|{assembly_id}
    # No ID is allowed to silently take over an existing unrelated asset.
    for row in ledger['assets']:
        if row['asset_id'] in ids:assert row.get('suite')=='reference_skiff',row['asset_id']+' already owned'
    new=[]
    for e in exp['components']:
        pkg=D/'component_packages'/e['key'];p=pkg/(e['key']+'.blend');mp=pkg/'asset_manifest.json';m=json.loads(mp.read_text(encoding='utf-8'))
        assert sha(p)==m['source_sha256'];assert sha(R/e['runtime_path'])==e['runtime_sha256']
        prefab='godot/scenes/components/reference_skiff/'+e['key']+'.tscn'
        importer=R/(e['runtime_path']+'.import')
        import_settings={'path':importer.relative_to(R).as_posix(),'sha256':sha(importer),
            'generate_lods':False,'create_shadow_meshes':False,'force_disable_compression':True}
        m.update(stage=stage,verification=evidence,prefab=prefab,prefab_sha256=sha(R/prefab),godot_import=import_settings);write(mp,m)
        new.append(dict(asset_id=e['asset_id'],name=e['name'],domain='scenes',suite='reference_skiff',scope='scene_local',
            stage=stage,source=p.relative_to(R).as_posix(),source_sha256=sha(p),manifest=mp.relative_to(R).as_posix(),version='v001',
            runtime_path=e['runtime_path'],runtime_sha256=e['runtime_sha256'],prefab=prefab,prefab_sha256=sha(R/prefab),license=plan['reference_license'],
            geometry_fingerprint=e['geometry_fingerprint'],category=e['category'],classification={'category':'vessel','subcategory':e['category']},
            consumer_features=['SEA-ASSET','SEA-NAV'],verification=evidence,note='Newly authored reference skiff component. Public palette and PaletteUV; no gameplay collision. Commercial reference rights pending.'))
    new.append(dict(asset_id=assembly_id,name='黄白木船-正式组件装配',domain='scenes',suite='reference_skiff',scope='scene_local',stage=stage,
        source=source.relative_to(R).as_posix(),source_sha256=sha(source),manifest=manifest.relative_to(R).as_posix(),version='v001',
        runtime_path='godot/scenes/props/reference_skiff.tscn',runtime_sha256=sha(R/'godot/scenes/props/reference_skiff.tscn'),
        prefab='godot/scenes/props/reference_skiff.tscn',license=plan['reference_license'],consumer_features=['SEA-ASSET','SEA-NAV'],verification=evidence,
        classification={'category':'vessel','subcategory':'assembly'},note='12 components/44 source instances; base boat replacement, existing lantern reused; hull envelope exactly matches legacy.'))
    ledger['assets']=[row for row in ledger['assets'] if row['asset_id'] not in ids]+new;write(path,ledger)
    idx=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'));sources=[]
    for domain,r in idx['domains'].items():
        for row in json.loads((R/r['ledger']).read_text(encoding='utf-8'))[r['asset_key']]:sources.append({k:row[k] for k in ['asset_id','source','source_sha256','manifest']})
    old=json.loads((R/'assets/registry/current_source_index.json').read_text(encoding='utf-8'));old['sources']=sources;write(R/'assets/registry/current_source_index.json',old)
    p=R/idx['runtime_inventory'];inventory=json.loads(p.read_text(encoding='utf-8'));runtime_ids={row['runtime_path']:row['asset_id'] for row in new}
    own=[row for row in inventory['resources'] if row['path'] not in runtime_ids]
    for row in own:
        if row['path'] in plan['legacy_sha256']:row['status']='retired_boat_bake_preserved_for_reference'
    own.extend(dict(path=k,bytes=(R/k).stat().st_size,sha256=sha(R/k),asset_id=aid,status=stage) for k,aid in runtime_ids.items())
    inventory['resources']=sorted(own,key=lambda x:x['path']);write(p,inventory)
    source_report=Path(exp['validation_report']);sr=json.loads(source_report.read_text(encoding='utf-8'))
    sr['godot_validation']={'asset_specialties':'passed','reports':evidence,'integration':'Baseline failures and current workspace hash drift documented separately'}
    write(source_report,sr)
    print('REGISTERED',len(new),'reviewed assets; unrelated hashes retained')
