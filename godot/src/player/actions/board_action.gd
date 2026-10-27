extends RefCounted
func execute(c) -> void:
	if c.actor.get_parent()!=c.vessel: c.actor.reparent(c.vessel,true)
	c.actor.position = Vector3(0,0.62,-0.30)
	c.actor.rotation = Vector3.ZERO
	c.walk_path.clear()
	c.after_walk = Callable()
	c.clear_interaction()
	c.notify("回到船上")
