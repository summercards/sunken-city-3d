"""Trace owned verifier revisions to real older runner snapshots; never accept unrelated inventory drift."""
import hashlib,json
from pathlib import Path
R=Path(__file__).resolve().parents[3];W=R.parent/'sea-work/sunken_city/v004/import';V=R.parent/'sea-work/verification'
sha=lambda b:hashlib.sha256(b).hexdigest()
inv=json.loads((R/'assets/registry/runtime_resource_inventory.json').read_text(encoding='utf-8'));records=[]
for name in ('godot/tests/test_sunken_city.gd','godot/tools/capture_sunken_city.gd'):
    old=next(x['sha256'] for x in inv['resources'] if x['path']==name);proof=None
    for folder in V.iterdir():
        p=folder/'project'/name.removeprefix('godot/')
        if p.is_file() and sha(p.read_bytes())==old:proof=p;break
    assert proof,name+' registered revision not found in real isolated snapshot'
    records.append(dict(path=name,registered_before_sha256=old,previous_snapshot=str(proof),after_sha256=sha((R/name).read_bytes()),scope='owned sunken-city verification and capture version/height/road framing changes'))
(W/'test_revision_provenance.json').write_text(json.dumps(dict(passed=True,files=records),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('TEST_REVISION_PROVENANCE',records)
