import bpy, json
s=bpy.data.scenes.get('海上巨型楼顶农场_重制_v002')
print(json.dumps({'scene':None if not s else s.name,'objects':None if not s else len(s.objects),'collections':None if not s else [(c.name,len(c.objects)) for c in bpy.data.collections if 'v002' in c.name or '02_' in c.name],'sample':[] if not s else [o.name for o in s.objects if '菜畦' in o.name or '温室' in o.name or '工具棚' in o.name][:20]},ensure_ascii=False))
