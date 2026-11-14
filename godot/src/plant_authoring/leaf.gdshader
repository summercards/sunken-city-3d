shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D grass_mask : filter_linear, repeat_disable;
uniform float local_time = 0.0;
uniform bool preview_wind = false;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wind_speed : hint_range(0.0, 3.0) = 1.0;
uniform float wind_weight : hint_range(0.0, 1.0) = 1.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.86;
varying float canopy_light;

void vertex() {
	// 默认静态；只有独立预览实例的本地时间可驱动风，不读取 TIME 或全局参数。
	float clock = local_time * wind_speed;
	float phase = dot(VERTEX.xz, vec2(1.73, 2.41)) + VERTEX.y * 0.57;
	float wave = sin(clock * 1.8 + phase) - sin(phase);
	float flutter = sin(clock * 3.1 + phase * 2.3) - sin(phase * 2.3);
	float amplitude = preview_wind ? wind_strength * wind_weight : 0.0;
	VERTEX.xz += vec2(wave, flutter * 0.45) * amplitude * 0.075;
	canopy_light = 0.88 + 0.12 * clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	// 只有复用草卡UV2>=0；其他树干、叶片是实体几何，不使用透明贴图。
	if (UV2.x >= 0.0 && texture(grass_mask, UV2).a < 0.38) { discard; }
	ALBEDO = texture(palette_texture, UV).rgb * canopy_light;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.20;
}
