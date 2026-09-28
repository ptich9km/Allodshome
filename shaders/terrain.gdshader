shader_type canvas_item;

uniform sampler2D u_atlas;

void fragment() {
	// Decode terrain type from COLOR.r (step functions for GPU precision safety)
	float r = COLOR.r;
	int ta = 0;
	if (r > 0.07) ta = 1;
	if (r > 0.21) ta = 2;
	if (r > 0.36) ta = 3;
	if (r > 0.50) ta = 4;
	if (r > 0.64) ta = 5;
	if (r > 0.79) ta = 6;

	// Sample atlas texture
	vec4 tex = texture(u_atlas, UV);

	// Terrain type color tint
	vec3 tint = vec3(0.5);
	if (ta == 0) tint = vec3(0.30, 0.55, 0.22);
	else if (ta == 1) tint = vec3(0.55, 0.50, 0.45);
	else if (ta == 2) tint = vec3(0.15, 0.35, 0.70);
	else if (ta == 3) tint = vec3(0.55, 0.45, 0.32);
	else if (ta == 4) tint = vec3(0.50, 0.35, 0.18);
	else if (ta == 5) tint = vec3(0.85, 0.72, 0.25);
	else if (ta == 6) tint = vec3(0.30, 0.22, 0.12);

	COLOR = vec4(tex.rgb * tint * COLOR.a, 1.0);
}
