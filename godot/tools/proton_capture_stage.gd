extends Node3D
## A focused render stage using the formal roof, sea material and camera rig.
## Other concurrently edited city assets are not loaded by this vegetation trial.
var cam
var _autosave_on:=false
var _zone_nodes: Dictionary
func _ready() -> void:
	cam=$Camera3D;cam.pose_lock=true;cam.set_process(false)
	_zone_nodes={"rooftop_ranch":$RooftopRanch}
