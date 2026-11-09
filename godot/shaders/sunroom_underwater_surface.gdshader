shader_type spatial;
// Underside adapter over the existing surface waves/normal texture/sun lobe.
render_mode cull_disabled, unshaded, depth_draw_opaque, fog_disabled;
#include "res://shaders/uw_surface_shared.gdshaderinc"
uniform float water_level = 101.587442;
uniform float elapsed = 0.0;
uniform float view_depth = -1.0;
uniform float region_view_depth = 10.0;
uniform float dive_depth = -1.0;
varying vec3 v_world;
void vertex() {
    v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float clock = elapsed == 0.0 ? TIME : elapsed;
    ALBEDO = underside_surface(v_world, clock,
        max(0.0, water_level - CAMERA_POSITION_WORLD.y), SCREEN_UV,
        CAMERA_POSITION_WORLD, max(0.0, -VERTEX.z));
}
