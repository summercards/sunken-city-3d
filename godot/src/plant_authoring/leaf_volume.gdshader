shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/plant_authoring/game_wind.gdshaderinc"

// 色板单格在构建时读取；体块不携带纹理采样或透明裁剪路径。
uniform vec4 palette_color : source_color = vec4(0.4, 0.6, 0.3, 1.0);
uniform float local_time = 0.0;
uniform bool preview_wind = false;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wind_speed : hint_range(0.0, 3.0) = 1.0;
uniform float wind_weight : hint_range(0.0, 1.0) = 1.0;
uniform float world_wind_strength = 1.1;
uniform vec2 world_wind_direction = vec2(0.864507, 0.50262);
uniform bool wind_vertex_weights = true;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.86;
uniform float palette_saturation : hint_range(0.0, 1.0) = 1.0;
uniform float palette_value : hint_range(0.0, 1.0) = 1.0;
varying float canopy_light;
varying float foliage_shade;

void vertex() {
	if (preview_wind && wind_vertex_weights && wind_weight > 0.0 && wind_strength > 0.0) {
		vec3 offset = plant_game_wind(MODEL_MATRIX[3].xyz, local_time * wind_speed,
			world_wind_strength, world_wind_direction, 0.055 * wind_strength,
			COLOR.r * wind_weight, 0.0, COLOR.g);
		VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
	}
	canopy_light = 0.88 + 0.12 * clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	foliage_shade = COLOR.b;
}

void fragment() {
	float gray = dot(palette_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 tint = mix(vec3(gray), palette_color.rgb, palette_saturation) * palette_value;
	ALBEDO = tint * canopy_light * foliage_shade;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.20;
}
