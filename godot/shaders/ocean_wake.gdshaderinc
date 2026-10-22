// History sampled in vertex stage only. A wake is part of the water surface,
// with identical reflection/refraction and no independently coloured ribbon.
uniform vec4 wake_points[32]; // world x/z, birth time, discontinuity before point
uniform vec2 wake_strengths[32];
uniform int wake_count = 0;
vec3 wake_profile(vec2 p) {
	float nearest = 1e10;
	float age = 0.0;
	float strength = 0.0;
	float end_fade = 0.0;
	for (int i = 1; i < 32; i++) {
		if (i >= wake_count) break;
		if (wake_points[i].w > 0.5) continue;
		vec2 a = wake_points[i - 1].xy;
		vec2 b = wake_points[i].xy;
		vec2 ab = b - a;
		float fraction = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
		float distance_sq = dot(p - a - ab * fraction, p - a - ab * fraction);
		if (distance_sq < nearest) {
			nearest = distance_sq;
			age = max(0.0, u_time - mix(wake_points[i - 1].z, wake_points[i].z, fraction));
			strength = mix(wake_strengths[i - 1].x, wake_strengths[i].x, fraction);
			end_fade = smoothstep(0.0, 0.22, age) * (1.0 - smoothstep(5.5, 9.0, age));
		}
	}
	if (nearest > 64.0 || age > 9.0) return vec3(100.0, 9.0, 0.0);
	float distance = sqrt(nearest);
	float spread = 1.0 + age * 0.32;
	float ridge = distance - spread;
	return vec3(ridge, age, strength * end_fade * exp(-age * 0.18));
}
float wake_sample(vec2 p) {
	vec3 profile = wake_profile(p);
	return sin(profile.x * 4.0) * exp(-profile.x * profile.x * 1.25) * 0.10 * profile.z;
}
