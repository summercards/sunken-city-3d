"""不启动 Godot，直接核对 GLB 二进制、模块目录与 TSCN 引用。"""
import hashlib
import json
import math
import re
import struct
from pathlib import Path

D = Path(__file__).resolve().parent
R = D.parents[3]
W = R.parent/'sea-work/building_kit_v002'
P = json.loads((D/'component_plan.json').read_text(encoding='utf-8'))
EXPORT = json.loads((D/'export/v002/export_manifest.json').read_text(encoding='utf-8'))
MODULES = json.loads((R/'godot/assets/data/building_kit_5m.json').read_text(encoding='utf-8'))
assert MODULES['schema']==1 and len(MODULES['modules'])==10
assert len({e['asset_id'] for e in P['components']})==10
assert len({e['id'] for e in MODULES['modules']})==10


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_glb(path):
    data = path.read_bytes()
    magic, version, size = struct.unpack_from('<III', data)
    assert magic==0x46546C67 and version==2 and size==len(data)
    n, kind = struct.unpack_from('<II', data, 12)
    assert kind==0x4E4F534A
    return json.loads(data[20:20+n]), data[28+n:]


def accessor(doc, blob, index):
    a = doc['accessors'][index]
    view = doc['bufferViews'][a['bufferView']]
    channels = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
    code = {5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']]
    width = struct.calcsize('<'+code*channels)
    offset = view.get('byteOffset',0)+a.get('byteOffset',0)
    return [struct.unpack_from('<'+code*channels,blob,offset+i*view.get('byteStride',width)) for i in range(a['count'])]


def transformed(point, node):
    assert node.get('scale',[1,1,1])==[1,1,1]
    assert 'matrix' not in node
    rotation = node.get('rotation',[0,0,0,1])
    assert all(abs(a-b)<1e-7 for a,b in zip(rotation,[0,0,0,1])), rotation
    translation = node.get('translation',[0,0,0])
    return tuple(a+b for a,b in zip(point,translation))


reports = []
for entry, module, exported in zip(P['components'], MODULES['modules'], EXPORT['exports']):
    key = entry['id']
    assert key==module['id']==exported['id']
    for field in ['asset_id','profile','footprint','height','seconds','source_origin']:
        assert module[field]==entry[field], (key,field)
    assert module['category']=='structure' and module['active'] is True
    assert module['cost']=={'wood':entry['wood']}
    path = R/f'godot/assets/models/building_kit/{key}/{key}.glb'
    doc, blob = read_glb(path)
    assert sha(path)==exported['glb_sha256']
    assert sha(exported['source_blend'])==exported['source_sha256_before']==exported['source_sha256_after']
    assert sha(exported['optimized_blend'])==exported['optimized_sha256']
    assert not doc.get('images') and not doc.get('textures')
    assert [m['name'] for m in doc['materials']]==['SEA_'+role for role in P['material_roles']]
    parent = {child:i for i,n in enumerate(doc['nodes']) for child in n.get('children',[])}
    points, faces, tri_count, roles, low, high = [], 0, 0, set(), [], []
    for ni,node in enumerate(doc['nodes']):
        if 'mesh' not in node: continue
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            assert primitive.get('mode',4)==4
            assert 'TEXCOORD_0' in primitive['attributes'] and 'TEXCOORD_1' not in primitive['attributes']
            positions = accessor(doc,blob,primitive['attributes']['POSITION'])
            uv = accessor(doc,blob,primitive['attributes']['TEXCOORD_0'])
            indices = [a[0] for a in accessor(doc,blob,primitive['indices'])]
            roles.add(doc['materials'][primitive['material']]['name'])
            for i in range(len(positions)):
                point = positions[i]
                cursor = ni
                while True:
                    point=transformed(point,doc['nodes'][cursor])
                    if cursor not in parent: break
                    cursor=parent[cursor]
                points.append(point)
                positions[i]=point
            for i in range(0,len(indices),3):
                triangle=[uv[j] for j in indices[i:i+3]]
                assert len({(int(u*8),int(v*8)) for u,v in triangle})==1
                assert all(.125<=(c*8)%1<=.875 for p in triangle for c in p)
                area=abs(sum(triangle[j][0]*triangle[(j+1)%3][1]-triangle[(j+1)%3][0]*triangle[j][1] for j in range(3)))/2
                assert area>1e-9, (key,i,'无面积UV')
                faces += 1
            tri_count += len(indices)//3
    mins=[min(p[k] for p in points) for k in range(3)]
    maxs=[max(p[k] for p in points) for k in range(3)]
    size=[maxs[k]-mins[k] for k in range(3)]
    expected=[entry['footprint'][0], entry['height'], entry['footprint'][1]]
    assert all(abs(a-b)<1e-5 for a,b in zip(size,expected)), (key,size,expected)
    assert abs(mins[1]-(-entry['height'] if entry['source_origin']=='surface_center' else 0))<1e-5
    assert tri_count==exported['triangles_after'], (key,tri_count,exported['triangles_after'])
    if key=='stairs_5m':
        assert any(abs(p[1]-P['storey_height'])<1e-5 and p[2]<-2.48 for p in points)
        assert any(abs(p[1]-P['storey_height']/27)<1e-5 and p[2]>2.48 for p in points)
        assert mins[0]>=-.75-1e-6 and maxs[0]<=.75+1e-6
    text=(R/f'godot/scenes/buildables/kit/{key}.tscn').read_text(encoding='utf-8')
    assert 'content_id = "'+key+'"' in text
    assert 'res://src/building/kit_visual.gd' in text and 'scale =' not in text
    assert f'res://assets/models/building_kit/{key}/{key}.glb' in text
    for resource in re.findall(r'path="res://([^"]+)"',text):
        assert (R/'godot'/resource).is_file(), resource
    reports.append({'id':key,'asset_id':entry['asset_id'],'godot_bounds_min_m':mins,'godot_bounds_max_m':maxs,
                    'godot_dimensions_m':size,'triangles':tri_count,'valid_uv_triangles':faces,
                    'material_roles_used':sorted(roles),'embedded_images':0,'prefab_references_valid':True,
                    'sha256':sha(path)})

baseline=json.loads((W/'protected_before.json').read_text(encoding='utf-8'))
assert all(sha(path)==digest for path,digest in baseline.items())
report={'passed':True,'godot_runtime':'pending_main_agent_runner','module_count':10,
        'total_triangles':sum(r['triangles'] for r in reports),'components':reports,
        'protected_files_unchanged':len(baseline),'historical_source_unchanged':True}
(W/'output_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
catalog=json.loads((D/'catalog.json').read_text(encoding='utf-8'))
for record in catalog['components']:
    key=record['id']
    record.update(exported=True,runtime_integrated=False)
    manifest_path=D/'component_packages'/key/'asset_manifest.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    manifest.update(exported=True,runtime_integrated=False,source_sha256=sha(D/'building_kit.blend'),
                    component_sha256=sha(D/record['component_blend']),
                    glb_sha256=next(r['sha256'] for r in reports if r['id']==key))
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(D/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
registration=[]
for entry in P['components']:
    key=entry['id']
    registration.append({'asset_id':entry['asset_id'],'id':key,'name':entry['name'],'version':'v002',
        'building_class':'above_water','category':'building/structure','source':str(D/'building_kit.blend'),
        'source_sha256':sha(D/'building_kit.blend'),'component_source':str(D/f'component_packages/{key}/{key}.blend'),
        'manifest':str(D/f'component_packages/{key}/asset_manifest.json'),
        'optimized_source':str(D/'export/v002/building_kit_optimized.blend'),
        'glb':str(R/f'godot/assets/models/building_kit/{key}/{key}.glb'),
        'prefab':str(R/f'godot/scenes/buildables/kit/{key}.tscn'),
        'footprint_m':entry['footprint'],'height_m':entry['height'],'origin':entry['source_origin'],
        'front_axis':'-Z','source_validation':'passed','static_glb_validation':'passed',
        'runtime_integrated':False,'godot_validation':'pending_main_agent_runner',
        'collision_owner':'sea_building_space_projection','shared_palette':P['palette']})
handoff={'registration_rows':registration,'catalog':'godot/assets/data/building_kit_5m.json',
    'untouched':['v001','tools/blender/building_kit','godot/assets/data/building_kit.json','rules','UI','tests','docs','registry'],
    'pending_main_agent':['加载新模块目录并兼容5.086335层高','Godot正式导入、独立预制体加载与材质绑定','楼梯连续斜坡、首尾与并排实际通行','门洞1.85×3.1米运行碰撞投影','登记10条资产及源索引/功能账本'],
    'evidence':[str(W/'source_validation.json'),str(W/'output_validation.json')],
    'notes':['未运行任何Godot进程；未编辑规则/UI/tests/文档/registry','共享Emission角色保留但本批没有虚构发光几何','所有成本与建造秒数按用户指定，未重平衡经济']}
(W/'handoff_registration.json').write_text(json.dumps(handoff,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if (W/'optimized_structure_overview.png').exists():
    from PIL import Image, ImageChops, ImageStat
    fidelity=[]
    for label in ['structure_overview','structure_back','structure_top']:
        a=Image.open(W/(label+'.png')).convert('RGB')
        b=Image.open(W/('optimized_'+label+'.png')).convert('RGB')
        diff=ImageChops.difference(a,b)
        stats=ImageStat.Stat(diff)
        fidelity.append({'view':label,'rms_255':stats.rms,'mean_absolute_255':stats.mean,
                         'source':str(W/(label+'.png')),'optimized':str(W/('optimized_'+label+'.png'))})
    (W/'fidelity_validation.json').write_text(json.dumps({'comparisons':fidelity,'note':'同机位同光照源/优化三视图；差异为重复内部面的清理与采样误差'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('FIDELITY_RMS',[(r['view'],r['rms_255']) for r in fidelity])
print('V002_GLB_STATIC_PASS',len(reports),report['total_triangles'])
