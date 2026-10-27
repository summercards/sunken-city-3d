extends RefCounted
func execute(c, position: Vector3) -> void:
	if c.actor.get_parent()!=c.world: c.actor.reparent(c.world,true)
	c.actor.global_position = position
	c.notify("走上岸边")
