"""One-time initialization of NEW boat scenes from reviewed component instances."""
import argparse, json
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/reference_skiff/v001'
def vec(v):return 'Vector3('+', '.join(f'{x:.9f}' for x in v)+')'
def matmul(a,b):return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def xf(i):
    # All currently authored rotations are single-axis, but use full XYZ composition.
    import math
    x,y,z=i['rotation_euler_xyz'];cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
    rx=[[1,0,0],[0,cx,-sx],[0,sx,cx]];ry=[[cy,0,sy],[0,1,0],[-sy,0,cy]];rz=[[cz,-sz,0],[sz,cz,0],[0,0,1]]
    a=matmul(matmul(rz,ry),rx);a=[[a[r][c]*i['scale'][c] for c in range(3)] for r in range(3)]
    C=[[1,0,0],[0,0,1],[0,-1,0]];CT=list(map(list,zip(*C)));a=matmul(matmul(C,a),CT)
    p=i['position'];return a,[p[0],p[2],-p[1]]
def transform(a,p):return 'Transform3D('+', '.join(f'{a[r][c]:.9f}' for c in range(3) for r in range(3))+', '+', '.join(f'{v:.9f}' for v in p)+')'
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--initialize-runtime',action='store_true');args=parser.parse_args()
    if not args.initialize_runtime:raise SystemExit('Requires explicit --initialize-runtime; formal TSCN owns placement')
    cat=json.loads((D/'catalog.json').read_text(encoding='utf-8'))['components'];ins=json.loads((D/'component_instances.json').read_text(encoding='utf-8'))['instances']
    out=R/'godot/scenes/props/reference_skiff.tscn'
    if out.exists():raise SystemExit('Formal scene already exists. Edit its TSCN in place; do not regenerate.')
    comp=R/'godot/scenes/components/reference_skiff';comp.mkdir(parents=True,exist_ok=True)
    for e in cat:
        k=e['key'];p=comp/(k+'.tscn')
        p.write_text('[gd_scene load_steps=3 format=3]\n'
            '[ext_resource type="Script" path="res://src/world/skiff_palette_binding.gd" id="bind"]\n'
            f'[ext_resource type="PackedScene" path="res://assets/models/boats/reference_skiff/components/{k}/{k}.glb" id="visual"]\n'
            f'[node name="{k}" type="Node3D"]\nscript = ExtResource("bind")\nasset_id = "{e["asset_id"]}"\n'
            'component_kind = "building"\nsubcategory = "vessel_part"\nfacility_id = "player_boat"\n'
            f'metadata/asset_id = "{e["asset_id"]}"\n'
            '[node name="Visual" parent="." instance=ExtResource("visual")]\n',encoding='utf-8')
    lines=[f'[gd_scene load_steps={len(cat)+1} format=3]']
    for e in cat:lines.append(f'[ext_resource type="PackedScene" path="res://scenes/components/reference_skiff/{e["key"]}.tscn" id="{e["key"]}"]')
    lines+=['[node name="ReferenceSkiff" type="Node3D"]','metadata/asset_id = "SEA-SCENE-SKIFF-ASSEMBLY"',
        '[node name="Parts" type="Node3D" parent="."]',
        '[node name="OarL" type="Node3D" parent="."]','position = Vector3(-1.10, 0.68, 0.10)',
        '[node name="OarR" type="Node3D" parent="."]','position = Vector3(1.10, 0.68, 0.10)']
    for i in ins:
        a,p=xf(i);parent='Parts';name=i['instance_id'].split('/')[-1]
        if i['key']=='oar':
            parent='OarL' if 'OarL' in name else 'OarR';pivot=[-1.10 if parent=='OarL' else 1.10,.68,.10];p=[p[j]-pivot[j] for j in range(3)]
        lines.extend([f'[node name="{name}" parent="{parent}" instance=ExtResource("{i["key"]}")]',
            'transform = '+transform(a,p),f'instance_id = "{i["instance_id"]}"'])
    out.parent.mkdir(parents=True,exist_ok=True);out.write_text('\n\n'.join(lines)+'\n',encoding='utf-8')
    print('INITIALIZED_NEW_RUNTIME',len(cat),'components',len(ins),'instances')
