extends RefCounted
## 施工时间来自 Service；这里只投影通用细条，不复制进度组件。
const Catalog = preload("res://src/building/building_catalog.gd")
const ThinBar = preload("res://src/ui/thin_progress_bar.gd")
var progress: Dictionary = {}

func sync(ids: Array[String],service: RefCounted,world: Node3D,camera: Camera3D,parent: Control) -> void:
	var live: Dictionary={}
	for id in ids:
		var item: Dictionary=service.row(id)
		if item.is_empty() or float(item.left)<=0.0: continue
		live[id]=true
		if not progress.has(id):
			var bar:=ThinBar.new()
			bar.configure(ThinBar.BUILD_WIDTH,ThinBar.BUILD_HEIGHT,ThinBar.BUILD_FILL,ThinBar.BUILD_TRACK)
			parent.add_child(bar);progress[id]=bar
		var point: Vector3=world.position_for(item)+Vector3.UP*0.8
		var bar: ThinBar=progress[id];bar.visible=not camera.is_position_behind(point)
		bar.place_at(camera.unproject_position(point),12.0)
		bar.set_ratio(1.0-float(item.left)/float(Catalog.RECIPES[item.kind].seconds))
	for id in progress.keys():
		if not live.has(id): progress[id].queue_free();progress.erase(id)
