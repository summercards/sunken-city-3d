#!/usr/bin/env python3
"""Retire exact web fish/ring triangles in a generation candidate, preserving GLB slots.
No bounds-based deletion: all three world-space vertices must match source bake.
"""
import argparse
from collections import defaultdict
import hashlib
from itertools import permutations, product
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'godot/tools'))
from authored_guard import require_candidate
FISH_GEOMS = set(range(749, 759))
SOURCE_SHA256 = {'scene.json': '2dcffe77d58e961694330db2fca6115fb0de048347696fe451fe1bdc45e9362f', 'geoms.bin': '1e16209b34f6d761c32fa66dad038b941f9895265388fec75272d472e734756a', 'geoms_idx.bin': 'c193c5f0469d6eaf082aa3370cd78c2b520349ba8fced3d5487c78acb16daddb', 'instances.bin': '2a249c7acc0506915ce89c8bbf15d4ad146513ddea8eabf64c68df5d7325998a'}


def floats(path):
    raw = path.read_bytes()
    return struct.unpack('<%df' % (len(raw)//4), raw)


def run(project):
    require_candidate(project / 'tools/retire_baked_surface_visuals.py')
    source = project/'assets/baked'
    for name, expected in SOURCE_SHA256.items():
        if hashlib.sha256((source/name).read_bytes()).hexdigest() != expected:
            raise ValueError('Source bake changed; re-audit geometry IDs before retiring: ' + name)
    scene = json.loads((source/'scene.json').read_text())
    verts, instances = floats(source/'geoms.bin'), floats(source/'instances.bin')
    raw = (source/'geoms_idx.bin').read_bytes()
    idx = struct.unpack('<%di' % (len(raw)//4), raw)
    targets = defaultdict(list)
    def cell(p): return tuple(round(v * 100) for v in p)
    def centroid(tri): return tuple(sum(v[k] for v in tri)/3 for k in range(3))
    for batch in scene['batches']:
        gi = batch['geom']
        if gi not in FISH_GEOMS and not (gi == 747 and batch['alpha']): continue
        g = scene['geoms'][gi]
        indices = idx[g['iOff']:g['iOff']+g['icount']] if g['icount'] else range(g['vcount'])
        for i in range(batch['count']):
            off = (batch['instOff']+i)*16
            m = instances[off:off+16]
            points = []
            for j in range(g['vcount']):
                p = verts[g['pOff']+j*3:g['pOff']+(j+1)*3]
                points.append(tuple(sum(m[k*4+l]*p[l] for l in range(3))+m[k*4+3] for k in range(3)))
            for k in range(0,len(indices),3):
                tri = tuple(points[indices[k+l]] for l in range(3))
                targets[cell(centroid(tri))].append((gi,tri))
    def matches(tri):
        c = cell(centroid(tri))
        for offset in product([-1,0,1],repeat=3):
            for gi,target in targets.get(tuple(c[k]+offset[k] for k in range(3)),[]):
                for perm in permutations(target):
                    if all(max(abs(a[k]-b[k]) for k in range(3)) < .0012 for a,b in zip(tri,perm)):
                        return gi
        return None
    report=[]
    for manifest in sorted((project/'assets/models/zones').glob('*/manifest.json')):
        data=json.loads(manifest.read_text())
        groups=[(data['name'],data['origin'],manifest.parent/(data['name']+'.glb'))]
        groups += [(u['id'],u['origin'],manifest.parent/'units'/(u['id']+'.glb')) for u in data['units']]
        for name,origin,path in groups:
            blob=bytearray(path.read_bytes()); original=hashlib.sha256(blob).hexdigest()
            json_length,tag=struct.unpack_from('<II',blob,12)
            assert tag==0x4e4f534a
            doc=json.loads(blob[20:20+json_length]); bin_start=20+json_length+8
            def read_accessor(n):
                acc=doc['accessors'][n]; view=doc['bufferViews'][acc['bufferView']]
                at=bin_start+view.get('byteOffset',0)+acc.get('byteOffset',0)
                typ={5126:'f',5125:'I',5123:'H',5121:'B'}[acc['componentType']]
                width={'VEC3':3,'SCALAR':1}[acc['type']]
                stride=view.get('byteStride',struct.calcsize(typ)*width)
                return [struct.unpack_from('<'+typ*width,blob,at+i*stride) for i in range(acc['count'])],at,typ,stride
            removed=defaultdict(int)
            for mesh in doc['meshes']:
                for primitive in mesh['primitives']:
                    positions,_,_,_=read_accessor(primitive['attributes']['POSITION'])
                    world=[tuple(p[k]+origin[k] for k in range(3)) for p in positions]
                    indices,at,typ,stride=read_accessor(primitive['indices'])
                    for i in range(0,len(indices),3):
                        tri=tuple(world[indices[i+j][0]] for j in range(3))
                        gi=matches(tri)
                        if gi is not None:
                            # Degenerate only retired faces. Material slots, vertex buffers,
                            # normals, scene transforms, and all unrelated index bytes stay intact.
                            value=indices[i][0]
                            for j in range(3):struct.pack_into('<'+typ,blob,at+(i+j)*stride,value)
                            removed[gi]+=1
            if removed:
                path.write_bytes(blob)
                report.append({'path':path.relative_to(project).as_posix(),'retired_triangles':dict(removed),'before_sha256':original,'after_sha256':hashlib.sha256(blob).hexdigest()})
    return report


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('candidate',type=Path);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    report=run(a.candidate.resolve());a.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,indent=2))
