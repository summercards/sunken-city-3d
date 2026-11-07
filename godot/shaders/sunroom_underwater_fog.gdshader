shader_type spatial;
// Same proven pass ordering as the older dive maps. One water colour for opaque
// objects, water ceiling, finite terrain edge and empty background; no double fog.
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
#include "res://shaders/sunroom_underwater_color.gdshaderinc"
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
void vertex() { POSITION=vec4(VERTEX.xy,1.0,1.0); }
void fragment() {
 float depth=textureLod(scene_depth,SCREEN_UV,0.0).r;
 vec3 ndc=vec3(SCREEN_UV*2.0-1.0,depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 ndc.z=depth*2.0-1.0;
#endif
 vec4 view=INV_PROJECTION_MATRIX*vec4(ndc,1.0);
 vec3 point=view.xyz/view.w;
 vec3 direction=normalize((INV_VIEW_MATRIX*vec4(point,0.0)).xyz);
 vec3 world=(INV_VIEW_MATRIX*vec4(point,1.0)).xyz;
 float fog=region_fog_amount(length(point),world.xz);
 if(depth<0.00001) { fog=1.0; }
 vec3 scene_display=uw_hdr_to_display(textureLod(scene_color,SCREEN_UV,0.0).rgb);
 ALBEDO=uw_display_to_hdr(mix(scene_display,region_water_display(direction),fog));
 ALPHA=1.0;
}
