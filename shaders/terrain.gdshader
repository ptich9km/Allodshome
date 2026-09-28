shader_type canvas_item;

uniform sampler2D u_atlas;

void fragment() {
	// Un-premultiply: Godot Forward+ premultiplies vertex color by alpha
	float a = max(COLOR.a, 0.001);
	float r = COLOR.r / a;
	float rb = COLOR.b / a;

	// Decode terrain type using step functions (GPU-precision-safe)
	int ta = 0;
	if (r > 0.07) ta = 1;
	if (r > 0.21) ta = 2;
	if (r > 0.36) ta = 3;
	if (r > 0.50) ta = 4;
	if (r > 0.64) ta = 5;
	if (r > 0.79) ta = 6;

	int tb = 0;
	if (rb > 0.07) tb = 1;
	if (rb > 0.21) tb = 2;
	if (rb > 0.36) tb = 3;
	if (rb > 0.50) tb = 4;
	if (rb > 0.64) tb = 5;
	if (rb > 0.79) tb = 6;

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

	vec3 col = tex.rgb * tint * COLOR.a;
	COLOR = vec4(col, 1.0);
}
