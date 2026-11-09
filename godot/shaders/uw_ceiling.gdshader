shader_type spatial;
// Same underside adapter as the home map; no independent sine displacement.
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://shaders/uw_surface_shared.gdshaderinc"
uniform float elapsed = 0.0;
varying vec3 v_world;
void vertex() {
    v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float clock = elapsed == 0.0 ? TIME : elapsed;
    ALBEDO = underside_surface(v_world, clock,
        max(0.0, v_world.y - CAMERA_POSITION_WORLD.y), SCREEN_UV,
        CAMERA_POSITION_WORLD, max(0.0, -VERTEX.z));
}
