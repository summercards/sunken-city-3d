// Shared by the displaced surface and its world-space wake ribbon.
// CPU sampling uses exactly these waves and phases (water_surface.gd).
uniform float u_time = 0.0;
uniform vec4 ocean_waves[4]; // direction x/z, amplitude in metres, wavelength
uniform float wave_scale = 1.0;
uniform vec4 u_boat = vec4(0.0);

vec3 ocean_sample(vec2 p) {
	vec3 result = vec3(0.0); // height, dh/dx, dh/dz
	for (int i = 0; i < 4; i++) {
		vec4 w = ocean_waves[i];
		vec2 d = normalize(w.xy);
		float k = 6.2831853 / max(w.w, 0.01);
		// Short-crested wave packets: bend the phase across the travel direction.
		// Include envelope and phase derivatives so lighting still matches geometry.
		vec2 cross_dir = vec2(-d.y, d.x);
		float cross_k = k * 0.61;
		float cross_phase = cross_k * dot(cross_dir, p) + float(i) * 2.31 - u_time * 0.19;
		float envelope = 0.72 + 0.28 * sin(cross_phase);
		vec2 envelope_grad = cross_dir * (0.28 * cross_k * cos(cross_phase));
		float phase = k * dot(d, p) - sqrt(9.81 * k) * u_time + float(i) * 1.73
			+ 0.85 * sin(cross_phase * 0.83 + 0.7);
		vec2 phase_grad = k * d + cross_dir * (0.85 * 0.83 * cross_k * cos(cross_phase * 0.83 + 0.7));
		float height = sin(phase) + 0.18 * sin(phase * 2.0);
		float derivative = cos(phase) + 0.36 * cos(phase * 2.0);
		result.x += w.z * envelope * height;
		result.yz += w.z * (envelope_grad * height + envelope * phase_grad * derivative);
	}
	return result * wave_scale;
}

// Boat points toward -Z, matching Boat._forward(). Bow shoulders displace water.
float bow_height(vec2 p) {
	vec2 forward = -vec2(sin(u_boat.z), cos(u_boat.z));
	vec2 rel = p - u_boat.xy;
	float along = dot(rel, forward);
	float across = dot(rel, vec2(forward.y, -forward.x));
	float front = along - (2.35 - abs(across) * 0.72);
	return exp(-front * front * 4.0) * exp(-across * across * 0.24)
		* smoothstep(0.0, 1.0, abs(across)) * clamp(u_boat.w / 3.4, 0.0, 1.0) * 0.12;
}
