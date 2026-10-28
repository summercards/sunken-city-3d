// Night uses the renderer's real lighting. Day retains the authored emission
// model; no screen-space patches or hand-positioned lamp reflections are added.
global uniform float world_night;
group_uniforms night;
uniform vec3 night_albedo : source_color = vec3(0.40, 0.48, 0.59);
uniform vec3 night_deep_albedo : source_color = vec3(0.18, 0.29, 0.44);
uniform float night_depth_distance : hint_range(1.0, 16.0, 0.1) = 5.0;
uniform float night_shallow_opacity : hint_range(0.1, 0.9, 0.01) = 0.32;
uniform float night_roughness : hint_range(0.08, 1.0, 0.01) = 0.36;
group_uniforms;
