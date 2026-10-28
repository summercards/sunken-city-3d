"""Record fresh runtime results and real global gate exits for the cross ripple."""
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parents[2];D=R/'art_source/vfx/water_cross_ripple/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'cartoon_cross_ripple_v001'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--verification',type=Path,required=True);a=ap.parse_args()
    report=json.loads(a.verification.read_text(encoding='utf-8'))
    for name in ['visual-submerged-water-light','visual-atmosphere','ocean','water-params']:
        assert report['results'][name]['passed'], name
    manifest=D/'asset_manifest.json';m=json.loads(manifest.read_text(encoding='utf-8'))
    assert sha(R/m['source'])==m['source_sha256'] and sha(R/m['runtime_path'])==m['runtime_sha256']
    assert sha(R/m['raster_source'])==m['raster_source_sha256']
    m['verification']=[str(a.verification.resolve())];write(manifest,m)
    idx=json.loads((R/'assets/registry/ledger_index.json').read_text(encoding='utf-8'));route=idx['domains']['vfx']
    ledger=R/route['ledger'];book=json.loads(ledger.read_text(encoding='utf-8'))
    for row in book[route['asset_key']]:
        if row['asset_id']==m['asset_id']: row['verification']=m['verification']
    write(ledger,book)
    # Source bytes and paths remain identical; derived source index need not change.
    frames=json.loads((a.verification.parent/'project/outputs/submerged-water-light.json').read_text(encoding='utf-8'))
    evidence=dict(asset_id=m['asset_id'],feature_ids=['SEA-OCEAN','SEA-ASSET'],requirement='SEA-OCEAN-R21',
        final_verification=str(a.verification.resolve()),runtime_results=report['results'],
        geometry_change=False,layout_change=False,source=m['source'],source_sha256=m['source_sha256'],
        raster_source=m['raster_source'],raster_source_sha256=m['raster_source_sha256'],
        runtime_texture=m['runtime_path'],runtime_sha256=m['runtime_sha256'],signal_coverage=m['signal_coverage'],
        import_settings=m['import_settings'],license=m['license'],time_slots=frames,
        max_changed_fraction=max(f['signal']['positive_fraction'] for f in frames),
        max_luminance_delta=max(f['signal']['peak'] for f in frames),
        schemes=sorted({f['scheme'] for f in frames}),slot_count=len({f['slot'] for f in frames}),
        review_images=[str(a.verification.parent/'project/outputs'/('submerged-light-cross-close-'+str(h)+'.png')) for h in [9,17,19]],
        global_contracts={},not_executed=['mobile/Web device validation','user final art approval'])
    for label,args in [('sync',['--sync']),('check',[])]:
        cmd=[sys.executable,'-X','utf8',str(R/'scripts/check_feature_contracts.py'),*args]
        p=subprocess.run(cmd,cwd=R,capture_output=True,text=True,encoding='utf-8')
        log=W/('final-feature-contracts-'+label+'.log');log.write_text(p.stdout+p.stderr,encoding='utf-8')
        evidence['global_contracts'][label]={'command':cmd,'exit_code':p.returncode,'log':str(log),'output':p.stdout+p.stderr}
    target=R/'docs/development/2026-10-28_cartoon_cross_ripple.json';write(target,evidence)
    print('EVIDENCE',target,'slot_count',evidence['slot_count'],'schemes',evidence['schemes'],
        'gates',{k:v['exit_code'] for k,v in evidence['global_contracts'].items()})
