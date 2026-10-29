// Runtime solids supplement the static coastline without rebaking its atlas.
uniform vec4 runtime_contact_rects[24];
uniform int runtime_contact_count = 0;

vec2 with_runtime_contacts(vec2 p, vec2 static_contact) {
	vec2 result = static_contact;
	for (int i = 0; i < runtime_contact_count; i++) {
		vec4 rect = runtime_contact_rects[i];
		vec2 q = abs(p - rect.xy) - rect.zw;
		float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		// Interior gaps between planks must not become a sheet of white foam.
		if (d >= 0.0 && d < result.x) result = vec2(d, 0.8);
	}
	return result;
}
