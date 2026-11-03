extends RefCounted
## Transient presentation only. No profile fields, global services or save writes.
const MODES := ["neutral","happy","focused","surprised","concerned","calm"]
var _eyes: Array[ShaderMaterial]=[]
var _groups: Dictionary={}
var _tiles: Array[Vector2]=[]
var _forced := ""
var _remaining := 0.0
var _mode := "neutral"
var _blink := 1.0
var _mouth: ShaderMaterial
var _mouth_tile := 0

func bind(root: Node3D) -> void:
	_eyes.clear(); _tiles.clear(); _groups.clear()
	_mouth=null
	for child in root.get_children():
		if child.has_meta("avatar_expression"): _groups[str(child.get_meta("avatar_expression"))]=weakref(child)
	for mesh in root.find_children("*","MeshInstance3D",true,false):
		if mesh.material_override is ShaderMaterial and mesh.has_meta("mouth_tile"):
			_mouth=mesh.material_override; _mouth_tile=int(mesh.get_meta("mouth_tile"))
		if mesh.material_override is ShaderMaterial and mesh.has_meta("eye_tile"):
			_eyes.append(mesh.material_override)
			var tile: int=mesh.get_meta("eye_tile")
			_tiles.append(Vector2((tile%4)*0.25,(tile/4)*(1.0/3.0)))

func preview(id: String, duration:=2.8) -> void:
	if id=="auto": _forced=""; _remaining=0.0
	elif id in MODES: _forced=id; _remaining=maxf(0.01,duration)

func sample(clock: float, action: String, progress: float, delta: float) -> void:
	_remaining=maxf(0.0,_remaining-delta)
	_mode="neutral"
	if action=="harvesting": _mode="happy" if progress>.35 and progress<.67 else "focused"
	elif action in ["planting","watering","rowing"]: _mode="focused"
	elif action=="swimming": _mode="calm"
	if _remaining>0.0: _mode=_forced
	for id in _groups:
		var node: Node3D=_groups[id].get_ref()
		if node!=null: node.visible=id==_mode
	if _mouth!=null:
		var tile:=_mouth_tile
		if _mode=="happy": tile=_mouth_tile if _mouth_tile in [5,9,10,12,13] else 4
		elif _mode=="surprised": tile=3
		elif _mode=="focused": tile=2
		elif _mode=="concerned": tile=6
		elif _mode=="calm": tile=0
		_mouth.set_shader_parameter("tile_origin",Vector2((tile%4)*0.25,(tile/4)*0.25))
		_mouth.set_shader_parameter("glyph_scale",0.74 if tile in [3,14] else (0.86 if tile==9 else 1.0))
		_mouth.set_shader_parameter("openness",0.93+0.07*sin(clock*5.0) if _mode in ["happy","surprised"] else 1.0)
	var phase:=fposmod(clock+0.57,3.9)
	_blink=1.0
	if phase<0.10: _blink=1.0-smoothstep(0.0,0.10,phase)
	elif phase<0.16: _blink=0.0
	elif phase<0.28: _blink=smoothstep(0.16,0.28,phase)
	for i in _eyes.size():
		var eye: ShaderMaterial=_eyes[i]
		eye.set_shader_parameter("openness",_blink*(0.78 if _mode in ["focused","concerned"] else 1.0))
		var origin: Vector2=_tiles[i]
		if _mode=="happy": origin=Vector2(0.75,0)
		elif _mode=="surprised": origin=Vector2(0.25,1.0/3.0)
		eye.set_shader_parameter("tile_origin",origin)
		eye.set_shader_parameter("gaze",Vector2(sin(clock*.43)*.018,sin(clock*.29)*.008))

func query() -> Dictionary:
	return {"mode":_mode,"blink":_blink,"forced_remaining":_remaining,"eyes":_eyes.size()}
