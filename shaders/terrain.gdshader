shader_type canvas_item;

uniform sampler2D u_atlas;

varying float v_type;

void vertex() {
	// Terrain type encoded in VERTEX.z (integer, no precision loss)
	v_type = VERTEX.z;
}

void fragment() {
	// Decode terrain type from vertex Z (integer, no premultiply/precision issues)
	int ta = int(v_type + 0.5);

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

	COLOR = vec4(tex.rgb * tint * COLOR.a, 1.0);
}
