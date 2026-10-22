shader_type spatial;
// 诊断用：把面朝相机的一侧涂绿、背面涂红（cull_disabled，两面都画）。
//
// 用途：一眼看出「这栋楼的面到底朝哪边」。
//   · 单面材质（页面版 FrontSide）下，正常的面应该**几乎全绿**；
//   · 大片红 = 三角形绕序反了（glTF 是逆时针为正面，Godot 的顺/逆约定不同，
//     烘焙时若翻转了实例或索引就会整体反掉），单面渲染时这些面会直接消失，
//     双面渲染时它们的法线又是反的 —— 两种表现都像「建筑是碎的」。
render_mode unshaded, cull_disabled, depth_draw_opaque;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 正面绿、背面红；亮度按世界高度轻微变化，方便看清层次。
	float band = 0.75 + 0.25 * sin(v_world.y * 3.0);
	ALBEDO = FRONT_FACING ? vec3(0.22, 0.95, 0.45) * band : vec3(1.0, 0.16, 0.16) * band;
	// 保持不透明深度遮挡，避免背面覆盖正面而误判绕序。
}
