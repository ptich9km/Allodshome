shader_type canvas_item;

uniform sampler2D u_atlas;

void fragment() {
	// Decode terrain type from COLOR.r (alpha=1.0, no premultiply distortion)
	int ta = int(COLOR.r * 7.0 + 0.5);

	// Sample atlas texture
	vec4 tex = texture(u_atlas, UV);

	// Terrain type color tint
	vec3 tint;
	if (ta == 0) tint = vec3(0.30, 0.55, 0.22);
	else if (ta == 1) tint = vec3(0.55, 0.50, 0.45);
	else if (ta == 2) tint = vec3(0.15, 0.35, 0.70);
	else if (ta == 3) tint = vec3(0.55, 0.45, 0.32);
	else if (ta == 4) tint = vec3(0.50, 0.35, 0.18);
	else if (ta == 5) tint = vec3(0.85, 0.72, 0.25);
	else tint = vec3(0.30, 0.22, 0.12);

	// Brightness from COLOR.g, alpha always 1.0
	float brightness = COLOR.g;
	COLOR = vec4(tex.rgb * tint * brightness, 1.0);
}
