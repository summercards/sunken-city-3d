// soft_cards 的世界风纯函数；不声明 global，不读取 TIME。
vec3 plant_game_wind(vec3 pivot, float seconds, float strength, vec2 direction,
		float displacement, float weight, float phase, float detail_coordinate) {
	float travel = dot(pivot.xz, direction) * 0.65;
	float gust = pow(0.5 + 0.5 * sin(travel - seconds * 1.8), 2.0);
	float movement = min(0.44, displacement * strength) * weight * weight;
	float flex = 0.20 + gust * 1.05 + sin(seconds * 2.3 + phase) * 0.10;
	vec2 horizontal = direction * movement * flex;
	horizontal += vec2(-direction.y, direction.x)
		* sin(seconds * 3.1 + phase + detail_coordinate * 1.7) * movement * 0.10;
	return vec3(horizontal.x, -movement * flex * 0.14, horizontal.y);
}
