shader_type canvas_item;
render_mode unshaded;

// Pixel distances keep the opening circular on wide and tall viewports.
uniform vec2 viewport_size = vec2(1600.0, 1000.0);
uniform vec2 focus_uv = vec2(0.5);
uniform float openness : hint_range(0.0, 1.0) = 1.0;
uniform float feather_pixels : hint_range(0.5, 4.0) = 1.5;

void fragment() {
	vec2 offset = (UV - focus_uv) * viewport_size;
	vec2 farthest_corner = max(focus_uv, vec2(1.0) - focus_uv) * viewport_size;
	float full_radius = length(farthest_corner);
	// At 0 even the centre is black; at 1 even the farthest corner is clear.
	float radius = openness * (full_radius + 2.0 * feather_pixels) - feather_pixels;
	float black = smoothstep(radius - feather_pixels, radius + feather_pixels, length(offset));
	COLOR = vec4(0.0, 0.0, 0.0, black);
}
