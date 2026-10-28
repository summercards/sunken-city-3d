// Sparse cartoon four-point cross mask. Linear data, never a colored/noisy
// painted overlay. Dominant-face projection keeps crosses upright on walls and
// undistorted on roofs, rather than stretching one projection down the facade.
uniform sampler2D cross_ripple_mask : repeat_enable, filter_linear_mipmap;

float submerged_cross_ripple(vec3 bed_world, float clock, float density, float detail) {
	vec3 face = abs(normalize(cross(dFdx(bed_world), dFdy(bed_world)) + vec3(0.000001)));
	vec2 plane = bed_world.xz;
	if (face.x > face.y && face.x > face.z) {
		plane = bed_world.zy;
	} else if (face.z > face.y) {
		plane = bed_world.xy;
	}
	vec2 uv = plane * (max(density, 0.01) / 8.0) + vec2(clock * 0.003, -clock * 0.002);
	float mask = texture(cross_ripple_mask, uv).r;
	float resolved = 1.0 - smoothstep(0.12, 0.45, length(fwidth(uv)));
	return pow(max(mask, 0.0), mix(1.2, 0.85, clamp(detail, 0.0, 1.0))) * resolved;
}

// The requested pale ripple is less than a quarter of the old highlight gain.
// Zero mask leaves the base exactly alone; no glow haze and no dark lobes.
vec3 submerged_caustic_light(vec3 base, vec3 light_color, float coverage) {
	float amount = clamp(coverage, 0.0, 1.0) * 0.065;
	return base + max(vec3(0.0), light_color) * amount * max(vec3(0.0), vec3(1.0) - base);
}
