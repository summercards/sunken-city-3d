extends RefCounted
## Opt-in visual verification fixture. Copies lighting settings only, before Main
## or any panel is created; never reads or writes a player's game save.
static func prepare() -> void:
	var source := OS.get_environment("SEA_CAPTURE_LIGHTING_PROFILE")
	if source.is_empty(): return
	for filename in ["filter.cfg","light_slots.cfg","water.cfg","water_presets.cfg"]:
		var path := source.path_join(filename)
		if FileAccess.file_exists(path):
			var err := DirAccess.copy_absolute(path,ProjectSettings.globalize_path("user://"+filename))
			assert(err == OK,"Cannot stage lighting fixture " + filename)
