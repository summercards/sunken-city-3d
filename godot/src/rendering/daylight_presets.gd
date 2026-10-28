extends RefCounted
## Morning holds the authored 09:00 settings from 07:00 through 11:00.
## Short transitions separate noon, clear afternoon, sunset and readable blue night.
const KEYS := ["sun_energy", "ambient_energy", "sky_energy", "fog_energy", "warm", "night", "elevation", "azimuth"]
const PRESETS := [
	{"hour":0.0,"label":"深夜","values":[0.0,0.26,0.16,0.20,0.0,1.0,0.08,130.0]},
	{"hour":5.5,"label":"黎明前","values":[0.0,0.26,0.16,0.20,0.0,1.0,0.08,-50.0]},
	{"hour":6.0,"label":"清晨","values":[0.85,0.50,0.62,0.65,1.0,0.06,0.13,-39.0]},
	{"hour":7.0,"label":"上午","values":[1.0,1.0,1.0,1.0,0.0,0.0,1.0,0.0]},
	{"hour":11.0,"label":"上午","values":[1.0,1.0,1.0,1.0,0.0,0.0,1.0,0.0]},
	{"hour":12.0,"label":"正午","values":[1.30,1.08,1.18,1.06,0.0,0.0,1.60,42.0]},
	{"hour":14.0,"label":"正午","values":[1.30,1.08,1.18,1.06,0.0,0.0,1.60,42.0]},
	{"hour":14.2,"label":"下午","values":[1.0,1.0,1.0,1.0,0.05,0.0,1.05,60.0]},
	{"hour":16.0,"label":"下午","values":[1.0,1.0,1.0,1.0,0.05,0.0,1.05,60.0]},
	{"hour":17.0,"label":"夕阳","values":[0.56,0.48,0.55,0.52,1.0,0.0,0.21,115.0]},
	{"hour":18.3,"label":"夕阳","values":[0.40,0.32,0.38,0.36,1.0,0.0,0.10,122.0]},
	{"hour":19.0,"label":"黑夜","values":[0.0,0.26,0.16,0.20,0.0,1.0,0.08,130.0]},
	{"hour":24.0,"label":"深夜","values":[0.0,0.26,0.16,0.20,0.0,1.0,0.08,130.0]},
]

static func sample(hour: float) -> Dictionary:
	var h := fposmod(hour,24.0)
	for i in range(PRESETS.size()-1):
		var a: Dictionary = PRESETS[i]
		var b: Dictionary = PRESETS[i+1]
		if h > float(b.hour): continue
		var t := smoothstep(float(a.hour),float(b.hour),h)
		var result := {}
		for k in KEYS.size(): result[KEYS[k]] = lerpf(float(a.values[k]),float(b.values[k]),t)
		result.day = result.elevation
		result.angular = 1.0+1.4*float(result.warm)
		result.shadow_opacity = 1.0-0.22*float(result.warm)
		return result
	return {}
