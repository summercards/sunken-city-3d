"""Run the installed prop validator with sea's 8x8 grid and the recorded print exception.

The installed skill itself is not edited. Only its ShellStorm grid and material-input
policy are adapted; transform, origin, actual poster masks and area are additionally
audited by package_verify.py. Every package is reopened by both validators.
"""
import bpy,json,sys,os,io,contextlib,inspect
from pathlib import Path
version=os.environ.get('NGQ_VERSION','v001')
R=Path(__file__).resolve().parents[3];D=R/'art_source/scenes/neon_garden_quarter'/version;W=Path(os.environ.get('SEA_WORK_ROOT',R.parent/'sea-work'))/'neon_garden_quarter'/version
plan=json.loads((D/'component_plan.json').read_text(encoding='utf8'))
skill=Path('C:/Users/zhuangmenghong/.agents/skills/blender-game-prop-standard/scripts/validate_game_prop.py')
code=skill.read_text(encoding='utf8').replace('min(9,','min(7,').replace('* 10.0','* 8.0').replace('/ 10.0','/ 8.0')
ns={'__name__':'sea_adapted_validator','__file__':str(skill)};exec(compile(code,str(skill),'exec'),ns)
orig=ns['material_audit'];palette=(R/plan['palette']).resolve();atlas=(R/plan['poster_source'] if 'poster_source' in plan else D/'textures/poster_atlas.png').resolve()
def adapted(meshes,shared_palette=None):
 r=orig(meshes,shared_palette);r['bad_uv_map_nodes']=[];r['bad_image_interpolation']=[];r['non_shared_palette_images']=[]
 for m in {m for o in meshes for m in o.data.materials}:
  for n in m.node_tree.nodes:
   if n.type=='UVMAP' and n.uv_map!='PaletteUV' and not(m.name=='SEA_Matte' and n.uv_map=='PosterUV'):r['bad_uv_map_nodes'].append(m.name)
   if n.type=='TEX_IMAGE' and n.image:
    p=Path(bpy.path.abspath(n.image.filepath)).resolve()
    if p==palette and n.interpolation!='Closest':r['bad_image_interpolation'].append(m.name)
    if p==atlas:
     if m.name!='SEA_Matte' or n.interpolation!='Linear' or not n.inputs['Vector'].is_linked or n.inputs['Vector'].links[0].from_node.uv_map!='PosterUV':r['bad_image_interpolation'].append(m.name)
    elif p!=palette:r['non_shared_palette_images'].append(str(p))
 return r
ns['material_audit']=adapted
C=json.loads((D/'component_catalog.json').read_text(encoding='utf8'))['components'];out=W/'skill_reports';out.mkdir(exist_ok=True)
rows=[]
for key,path in [('master',D/'neon_garden_quarter.blend')]+[(c['key'],R/c['source']) for c in C]:
 bpy.ops.wm.open_mainfile(filepath=str(path))
 if key=='master':bpy.context.window.scene=bpy.data.scenes['组件母版_独立编辑']
 report=out/(key+'.json');sys.argv=['validator','--','--all-meshes','--allow-extra-uv','--max-materials','4','--shared-palette',str(palette),'--json',str(report)]
 try:
  with contextlib.redirect_stdout(io.StringIO()):ns['main']()
 except SystemExit as e:exitcode=e.code
 data=json.loads(report.read_text(encoding='utf8'));rows.append(dict(key=key,passed=data['passed'],exit_code=exitcode,faces=data['polygon_count'],failed_checks=[k for k,v in data['checks'].items() if not v]))
 print('SKILL_CHECK',key,exitcode,flush=True)
summary=dict(passed=all(r['passed'] for r in rows),validator=str(skill),adaptations=['sea shared 8x8 grid','documented PosterUV / image-2 external atlas on SEA_Matte'],reports=rows)
(W/'skill_verification.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
if not summary['passed']:raise RuntimeError(str([r for r in rows if not r['passed']]))
