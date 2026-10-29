@tool
extends StaticBody3D
## Optional component proxy. A visual mesh never becomes solid automatically.
## Components may opt a simple shape in/out without changing inventory, crops
## or layout ownership. Navigation declarations remain a separate ground input.
const GROUND_LAYER := 256
const ACTOR_LAYER := 512
@export var blocks_actor := true:
	set(value):
		blocks_actor = value
		_apply_layers()

func _ready() -> void:
	disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	_apply_layers()

func _apply_layers() -> void:
	collision_layer = GROUND_LAYER if blocks_actor else 0
	collision_mask = ACTOR_LAYER if blocks_actor else 0
