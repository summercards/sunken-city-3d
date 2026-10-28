// Focused light belongs to submerged geometry. It must never remove the base
// illumination: broad multiplicative darkening looked like dirty reflections on
// the large cyan roofs. Screen blending keeps both dark windows and pale walls
// readable, with headroom for a soft colored highlight instead of black patches.
vec3 submerged_caustic_light(vec3 base, vec3 light_color, float coverage) {
	float amount = clamp(coverage, 0.0, 1.0) * 0.28;
	return base + max(vec3(0.0), light_color) * amount * max(vec3(0.0), vec3(1.0) - base);
}
