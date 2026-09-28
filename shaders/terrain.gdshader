shader_type canvas_item;
render_mode world_vertex_coords;

// === Procedural Terrain Shader ===
// Pure noise — no BMP/PNG tiles needed.

const int T_GRASS    = 0;
const int T_MOUNTAIN = 1;
const int T_WATER    = 2;
const int T_ROAD     = 3;
const int T_SOIL     = 4;
const int T_SAND     = 5;
const int T_MUD      = 6;

uniform float u_time : hint_range(0.0, 1000.0);

varying vec2 v_world;

// === Noise ===

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0, a = 0.5;
	for (int k = 0; k < 6; k++) {
		if (k >= oct) break;
		v += a * vnoise(p);
		p = p * 2.03 + vec2(100.0);
		a *= 0.5;
	}
	return v;
}

float domain_warp(vec2 p) {
	vec2 q = vec2(fbm(p, 4), fbm(p + vec2(5.2, 1.3), 4));
	vec2 r = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2), 4),
	              fbm(p + 3.0 * q + vec2(8.3, 2.8), 4));
	return fbm(p + 2.0 * r, 4);
}

// === Vertex ===

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// === Palettes ===

vec3 terrain_base(int t) {
	if (t == T_GRASS)    return vec3(0.25, 0.50, 0.18);
	if (t == T_MOUNTAIN) return vec3(0.52, 0.48, 0.42);
	if (t == T_WATER)    return vec3(0.12, 0.30, 0.65);
	if (t == T_ROAD)     return vec3(0.50, 0.42, 0.30);
	if (t == T_SOIL)     return vec3(0.42, 0.28, 0.14);
	if (t == T_SAND)     return vec3(0.85, 0.70, 0.22);
	if (t == T_MUD)      return vec3(0.22, 0.15, 0.08);
	return vec3(0.5);
}

vec3 terrain_var1(int t) {
	if (t == T_GRASS)    return vec3(0.32, 0.58, 0.24);
	if (t == T_MOUNTAIN) return vec3(0.62, 0.58, 0.52);
	if (t == T_WATER)    return vec3(0.18, 0.38, 0.75);
	if (t == T_ROAD)     return vec3(0.55, 0.48, 0.35);
	if (t == T_SOIL)     return vec3(0.48, 0.32, 0.18);
	if (t == T_SAND)     return vec3(0.92, 0.78, 0.28);
	if (t == T_MUD)      return vec3(0.28, 0.18, 0.10);
	return vec3(0.6);
}

vec3 terrain_var2(int t) {
	if (t == T_GRASS)    return vec3(0.18, 0.40, 0.12);
	if (t == T_MOUNTAIN) return vec3(0.38, 0.35, 0.32);
	if (t == T_WATER)    return vec3(0.08, 0.22, 0.55);
	if (t == T_ROAD)     return vec3(0.42, 0.35, 0.25);
	if (t == T_SOIL)     return vec3(0.35, 0.22, 0.10);
	if (t == T_SAND)     return vec3(0.78, 0.62, 0.18);
	if (t == T_MUD)      return vec3(0.18, 0.12, 0.06);
	return vec3(0.4);
}

float terrain_freq(int t) {
	if (t == T_GRASS)    return 4.0;
	if (t == T_MOUNTAIN) return 3.0;
	if (t == T_WATER)    return 2.0;
	if (t == T_ROAD)     return 6.0;
	if (t == T_SOIL)     return 3.5;
	if (t == T_SAND)     return 5.0;
	if (t == T_MUD)      return 3.0;
	return 4.0;
}

// === Generate color ===

vec3 gen_terrain(int t, vec2 wp) {
	if (t == T_WATER) {
		vec2 p = wp * 0.03;
		float w1 = sin(p.x * 4.0 + u_time * 1.2) * 0.5 + 0.5;
		float w2 = sin(p.y * 3.0 + u_time * 0.8 + 1.7) * 0.5 + 0.5;
		float w3 = domain_warp(p + vec2(u_time * 0.1, 0.0));
		vec3 deep = terrain_base(T_WATER);
		vec3 shallow = terrain_var1(T_WATER);
		vec3 foam = vec3(0.5, 0.6, 0.75);
		vec3 col = mix(deep, shallow, w3 * 0.7 + 0.15);
		col = mix(col, foam, smoothstep(0.72, 0.82, w1 * w2) * 0.25);
		return col;
	}

	float freq = terrain_freq(t);
	vec2 p = wp * freq * 0.01;
	float n1 = domain_warp(p);
	float n2 = fbm(p * 2.5 + 31.7, 3);
	vec3 base = terrain_base(t);
	vec3 v1 = terrain_var1(t);
	vec3 v2 = terrain_var2(t);
	vec3 col = mix(base, v1, smoothstep(0.3, 0.7, n1));
	col = mix(col, v2, smoothstep(0.5, 0.8, n2) * 0.4);
	// Micro grain
	float grain = hash21(floor(wp * 2.0)) * 0.04 - 0.02;
	col += grain;
	return col;
}

// === Fragment ===

void fragment() {
	// Robust decode: step functions instead of round() (mediump float issues on some GPUs)
	float r = COLOR.r;
	int ta = 0;
	if (r > 0.07) ta = 1;
	if (r > 0.21) ta = 2;
	if (r > 0.36) ta = 3;
	if (r > 0.50) ta = 4;
	if (r > 0.64) ta = 5;
	if (r > 0.79) ta = 6;

	// Debug: flat color per type
	vec3 c;
	if (ta == 0) c = vec3(1.0, 0.0, 0.0);
	else if (ta == 1) c = vec3(0.0, 1.0, 0.0);
	else if (ta == 2) c = vec3(0.0, 0.0, 1.0);
	else if (ta == 3) c = vec3(1.0, 1.0, 0.0);
	else if (ta == 4) c = vec3(0.0, 1.0, 1.0);
	else if (ta == 5) c = vec3(1.0, 0.0, 1.0);
	else c = vec3(1.0, 1.0, 1.0);
	COLOR = vec4(c * COLOR.a, 1.0);
}
