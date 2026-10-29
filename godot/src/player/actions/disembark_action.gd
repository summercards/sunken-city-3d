extends RefCounted
func execute(c, position: Vector3) -> void:
	if c.actor.get_parent()!=c.world: c.actor.reparent(c.world,true)
	c.actor.global_position = position
	if c.actor.has_method("set_grounded_motion"): c.actor.set_grounded_motion(true)
	c.notify("走上岸边")
