import bpy, json
out=[]
for s in bpy.data.scenes:
 out.append({'scene':s.name,'n':len(s.objects),'children':[c.name for c in s.collection.children]})
print(json.dumps(out,ensure_ascii=False))
