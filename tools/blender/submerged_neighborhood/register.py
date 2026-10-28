"""Register only this kit after fresh imported geometry and real-render checks pass."""
import argparse,hashlib,json
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/submerged_neighborhood/v001'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--verification',type=Path,required=True);a=ap.parse_args()
    report=json.loads(a.verification.read_text(encoding='utf-8'));assert report['results']['visual-submerged-neighborhood']['passed']
    E=json.loads((D/'export_manifest.json').read_text(encoding='utf-8'));P=json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
    idx=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'));route=idx['domains']['scenes'];book=R/route['ledger']
    ledger=json.loads(book.read_text(encoding='utf-8'));stage='source_runtime_verified_provenance_pending'
    assert sha(R/E['source'])==E['source_sha256'] and sha(R/E['optimized_source'])==E['optimized_sha256']
    new=[];evidence=[str(a.verification.resolve())]
    for e in E['components']:
        k=e['key'];pkg=D/'component_packages'/k;mf=pkg/'asset_manifest.json';m=json.loads(mf.read_text(encoding='utf-8'))
        prefab='godot/scenes/decorations/underwater/buildings/'+k+'.tscn'
        assert sha(R/m['source'])==m['source_sha256'] and sha(R/e['runtime_path'])==e['runtime_sha256']
        m.update(asset_ledger=route['ledger']+'#'+e['asset_id'],stage=stage,prefab=prefab,prefab_sha256=sha(R/prefab),
            runtime_path=e['runtime_path'],runtime_sha256=e['runtime_sha256'],export_manifest=(D/'export_manifest.json').relative_to(R).as_posix(),
            optimized_source=E['optimized_source'],optimized_sha256=E['optimized_sha256'],verification=evidence,
            classification={'category':'decoration','subcategory':'underwater_buildings'},collision=False,interactive=False)
        write(mf,m)
        new.append(dict(asset_id=e['asset_id'],name=e['name'],domain='scenes',suite='submerged_neighborhood',scope='scene_local',stage=stage,
            source=m['source'],source_sha256=m['source_sha256'],manifest=mf.relative_to(R).as_posix(),version='v001',
            runtime_path=e['runtime_path'],runtime_sha256=e['runtime_sha256'],prefab=prefab,prefab_sha256=sha(R/prefab),
            category='underwater_scenic_building',classification=m['classification'],license=P['reference_license'],geometry_fingerprint=e['geometry_fingerprint'],
            consumer_features=['SEA-ASSET','SEA-WORLD'],verification=evidence,triangles=e['exported_triangles'],polygons=e['polygons'],triangle_budget=1000,
            source_optimization_manifest=m['export_manifest'],collision=False,interactive=False,
            runtime_instances=['World/UnderwaterScenery/'+k],
            note='Independent purely decorative submerged building. Original master + standalone source + independently saved optimized derivative. No resources, navigation, walk areas or interaction. Hidden elevations inferred; reference commercial rights pending.'))
    aid='SEA-SCENE-SUBMERGED-ASSEMBLY';prefab='godot/scenes/decorations/underwater/neighborhood.tscn';mf=D/'asset_manifest.json'
    assembly=dict(asset_id=aid,name='阳光房水下景观街区-六栋独立装配',domain='scenes',suite='submerged_neighborhood',scope='scene_local',stage=stage,
        source=E['source'],source_sha256=E['source_sha256'],manifest=mf.relative_to(R).as_posix(),version='v001',
        runtime_path=prefab,runtime_sha256=sha(R/prefab),prefab=prefab,license=P['reference_license'],
        category='underwater_scenery_assembly',classification={'category':'decoration','subcategory':'underwater_buildings'},consumer_features=['SEA-ASSET','SEA-WORLD'],verification=evidence)
    write(mf,dict(assembly,asset_ledger=route['ledger']+'#'+aid,dependencies=[e['asset_id'] for e in new],
        optimized_source=E['optimized_source'],optimized_sha256=E['optimized_sha256'],
        component_plan=(D/'component_plan.json').relative_to(R).as_posix(),export_manifest=(D/'export_manifest.json').relative_to(R).as_posix(),
        runtime_placement_owner='godot/scenes/main.tscn#World/UnderwaterScenery',reference_sha256=P['reference_sha256'],collision=False,interactive=False))
    new.append(assembly);ids={e['asset_id'] for e in new}
    for domain,r in idx['domains'].items():
        for e in json.loads((R/r['ledger']).read_text(encoding='utf-8'))[r['asset_key']]:
            if e['asset_id'] in ids:assert e.get('suite')=='submerged_neighborhood', 'AssetID already owned'
    ledger[route['asset_key']]=[e for e in ledger[route['asset_key']] if e['asset_id'] not in ids]+new;write(book,ledger)
    sources=[]
    for domain,r in idx['domains'].items():
        sources.extend({k:e[k] for k in ['asset_id','source','source_sha256','manifest']} for e in json.loads((R/r['ledger']).read_text(encoding='utf-8'))[r['asset_key']])
    path=R/'assets/registry/current_source_index.json';src=json.loads(path.read_text(encoding='utf-8'));src['sources']=sources;write(path,src)
    path=R/idx['runtime_inventory'];inventory=json.loads(path.read_text(encoding='utf-8'));own={e['runtime_path']:e['asset_id'] for e in new}
    inventory['resources']=[e for e in inventory['resources'] if e['path'] not in own]
    inventory['resources']+= [dict(path=p,bytes=(R/p).stat().st_size,sha256=sha(R/p),asset_id=aid,status=stage) for p,aid in own.items()]
    inventory['resources'].sort(key=lambda e:e['path']);write(path,inventory)
    print('REGISTERED',len(new),'records (6 buildings + assembly); unrelated hashes unchanged')
