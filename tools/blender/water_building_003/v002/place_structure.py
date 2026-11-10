exec(open('D:/projects/sea/tools/blender/water_building_003/v002/lib.py',encoding='utf8').read())
# structural components are placed explicitly; geometry stays in source collections.
for k,p in [
 ('foundation',(-.2,0,0)),('lower_shell',(.2,0,.3)),('lower_slab',(.2,0,5.2)),
 ('middle_shell',(-.25,0,5.4)),('middle_slab',(-.25,0,10.1)),
 ('upper_shell',(.25,0,10.3)),('upper_slab',(.25,0,13.4)),
 ('roof_lower',(.2,0,5.45)),('roof_middle',(-.25,0,10.35)),('roof_upper',(.25,0,13.6)),('roof_ridge',(.25,0,13.95)),
 ('lower_quoin',(.2,0,.3)),('middle_quoin',(-.25,0,5.4)),('upper_quoin',(.25,0,10.3))]:
    put(k,p)
print('placed structure',len(instances))
