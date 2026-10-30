@tool
extends "res://src/interaction/interactable.gd"
## Asset adapter only. Functional commands arrive through a signal to composition.
signal action_requested(action: String)
@export var content_id: String=""
var instance_id: String=""
var ghost:=false
var _rotor: Node3D
var _flag: Node3D
var _phase:=0.0
const Catalog=preload("res://src/building/building_catalog.gd")
func _on_ready() -> void:
	var definition: Dictionary=Catalog.RECIPES.get(content_id,{})
	label=str(definition.get("name",content_id));id=instance_id
	verb="打开仓库" if definition.get("profile")=="storage" else "补满水壶"
	focus_anchor="node";focus_offset=Vector3(0,0.5,0)
	if ghost or definition.get("profile","") not in ["storage","water"]: remove_from_group("interactable")
	for mesh: MeshInstance3D in find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var source: Material=mesh.mesh.surface_get_material(i)
			var role:=""
			if source!=null:
				for key in ["Matte","Metal","Gloss","Emission"]:
					if source.resource_name=="SEA_"+key: role=key
			if role.is_empty():
				push_error("Kit material role missing: "+content_id+"/"+str(mesh.name))
				continue
			var mat: Material=load("res://assets/materials/building_kit/"+role.to_lower()+".tres")
			if ghost:
				var preview:=StandardMaterial3D.new();preview.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;preview.render_priority=10
				preview.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;preview.albedo_color=Color(.52,.95,.78,.4)
				mesh.material_override=preview;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else: mesh.set_surface_override_material(i,mat)
	if ghost: return
	if definition.get("profile")=="lamp":
		var lamp:=OmniLight3D.new();lamp.name="WarmLamp";lamp.light_color=Color("#ffd19a");lamp.light_energy=.65;lamp.omni_range=4.0;lamp.shadow_enabled=false
		lamp.position.y=1.83 if content_id=="lamp_post" else .29;add_child(lamp)
	if definition.get("profile")=="windmill":
		_rotor=Node3D.new();_rotor.name="Rotor";_rotor.position=Vector3(0,1.28,-.18);add_child(_rotor)
		for mesh in find_children("rotor_*","MeshInstance3D",true,false): mesh.reparent(_rotor,true)
	if definition.get("profile") in ["chime","flag"]: _flag=get_node("Model")
func _on_tick(delta: float) -> void:
	_phase+=delta
	if is_instance_valid(_rotor): _rotor.rotation.z+=delta*.85
	if is_instance_valid(_flag): _flag.rotation.z=sin(_phase*1.8)*.025
func can_interact() -> bool:
	return not ghost and Catalog.RECIPES.get(content_id,{}).get("profile","") in ["storage","water"]
func interact(_actor: Node3D) -> Dictionary:
	if not can_interact(): return {}
	action_requested.emit(str(Catalog.RECIPES[content_id].profile));return {"event":"used"}
