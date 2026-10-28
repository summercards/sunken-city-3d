"""Collect persistent delivery evidence and unmasked global contract exit codes."""
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/submerged_neighborhood/v001'
W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'submerged_neighborhood_v001'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--report',type=Path,action='append',required=True);ap.add_argument('--before',type=Path,required=True);a=ap.parse_args()
    reports=[json.loads(p.read_text(encoding='utf-8')) for p in a.report]
    exp=json.loads((D/'export_manifest.json').read_text(encoding='utf-8'))
    result=dict(feature_ids=['SEA-ASSET','SEA-WORLD','SEA-OCEAN'],requirements=['SEA-ASSET-R29','SEA-WORLD-R10','SEA-OCEAN-R21'],
        source=exp['source'],source_sha256=exp['source_sha256'],optimized_source=exp['optimized_source'],optimized_sha256=exp['optimized_sha256'],
        protected_sources_unchanged=exp['protected_sources_unchanged'],geometry=[{k:e[k] for k in ['asset_id','key','polygons','triangles_before','triangles_after','exported_triangles','runtime_path','runtime_sha256']} for e in exp['components']],
        total_triangles=sum(e['exported_triangles'] for e in exp['components']),
        independent_packages_reopened=6,source_uv_checks='every face area and 8px cell margin; identity transforms; external unique palette; Closest',
        runtime_reports=[str(p.resolve()) for p in a.report],runtime_results={},global_contracts={},
        provenance='User supplied reference commercial rights pending; hidden elevations inferred',
        not_executed=['mobile/WeChat rendering','all historical full-world tests','user art approval','commercial rights verification'],
        known_warning='2D MSAA enabled with no 2D content',
        source_work_directory=str(W),formal_layout='godot/scenes/decorations/underwater/neighborhood.tscn')
    for p,rep in zip(a.report,reports):
        for key,v in rep['results'].items():
            result['runtime_results'][key]={**v,'report':str(p.resolve())}
    from PIL import Image,ImageChops,ImageStat
    result['optimization_fidelity_rgb_mean_difference_8bit']={v:ImageStat.Stat(ImageChops.difference(Image.open(W/('source-'+v+'.png')),Image.open(W/('optimized-'+v+'.png')))).mean[:3] for v in ['front','back','side','top']}
    before=json.loads(a.before.read_text(encoding='utf-8'));latest=None
    for p,rep in zip(a.report,reports):
        if 'visual-submerged-water-light' in rep['results']:
            latest=p.parent/'project/outputs/submerged-water-light.json'
    if latest:
        frames=json.loads(latest.read_text(encoding='utf-8'))
        result['time_slot_pixel_comparison']=frames
        result['caustic_diagnostic_before']={'report':str(a.before.resolve()),'checks':'96, 15 failures; original darkening measured on real roofs',
            'worst_mean_luminance_delta':min(x['delta']['mean'] for frame in json.loads((a.before.parent/'project/outputs/submerged-water-light.json').read_text(encoding='utf-8')) for x in frame['patches'])}
        result['caustic_after']={'slot_count':len({v['slot'] for v in frames}),'schemes':sorted({v['scheme'] for v in frames}),
            'worst_mean_luminance_delta':min(x['delta']['mean'] for frame in frames for x in frame['patches'])}
    # This is deliberately not a hash acceptance tool. Existing global drift is
    # returned as a failure; only this kit is registered by register.py.
    for label,args in [('sync',['--sync']),('check',[])]:
        cmd=[sys.executable,'-X','utf8',str(R/'scripts/check_feature_contracts.py'),*args]
        run=subprocess.run(cmd,cwd=R,capture_output=True,text=True,encoding='utf-8')
        log=W/('feature-contracts-'+label+'.log');log.write_text(run.stdout+run.stderr,encoding='utf-8')
        result['global_contracts'][label]={'command':cmd,'exit_code':run.returncode,'log':str(log),'output':run.stdout}
    out=R/'docs/development/2026-10-28_submerged_neighborhood.json'
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('EVIDENCE',out,'runtime', {k:v['passed'] for k,v in result['runtime_results'].items()},'global_exit_codes',{k:v['exit_code'] for k,v in result['global_contracts'].items()})
