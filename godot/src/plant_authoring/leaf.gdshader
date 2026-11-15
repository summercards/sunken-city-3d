shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/plant_authoring/game_wind.gdshaderinc"

uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D grass_mask : filter_linear, repeat_disable;
uniform float local_time = 0.0;
uniform bool preview_wind = false;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wind_speed : hint_range(0.0, 3.0) = 1.0;
uniform float wind_weight : hint_range(0.0, 1.0) = 1.0;
uniform float world_wind_strength = 1.1;
uniform vec2 world_wind_direction = vec2(0.864507, 0.50262);
uniform bool wind_vertex_weights = false;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.86;
varying float canopy_light;

void vertex() {
	// 未准备连接端权重的静态模型不能整片平移；UV2 仍只承载草遮罩。
	if (preview_wind && wind_vertex_weights && wind_weight > 0.0 && wind_strength > 0.0) {
		vec3 offset = plant_game_wind(MODEL_MATRIX[3].xyz, local_time * wind_speed,
			world_wind_strength, world_wind_direction, 0.055 * wind_strength,
			COLOR.r * wind_weight, 0.0, COLOR.g);
		// 用完整逆矩阵而非转置：旋转、非均匀缩放及父级变换均保持世界风向。
		VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
	}
	canopy_light = 0.88 + 0.12 * clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	// 只有复用草卡UV2>=0；其他树干、叶片是实体几何，不使用透明贴图。
	if (UV2.x >= 0.0 && texture(grass_mask, UV2).a < 0.38) { discard; }
	ALBEDO = texture(palette_texture, UV).rgb * canopy_light;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.20;
}
