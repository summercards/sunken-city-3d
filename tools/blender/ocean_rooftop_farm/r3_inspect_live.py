import bpy,json
s=bpy.context.scene
print(json.dumps({'active':s.name,'objects':len(s.objects),'children':[(c.name,[(cc.name,len(cc.objects)) for cc in c.children]) for c in s.collection.children],'roof_sample':[(o.name,list(o.location),list(o.dimensions)) for o in s.objects if any(k in o.name for k in ['温室','水罐','水塔','太阳能','野生草皮','工具棚','鸡舍'])][:90]},ensure_ascii=False))
