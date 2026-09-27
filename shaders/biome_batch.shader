shader_type canvas_item;

// Шейдер для батча тайлов одного биома
// Делает плавное смешивание на границах с соседними биомами

uniform sampler2D biome_texture : hint_default_white;
uniform float biome_type : hint_range(0.0, 6.0) = 0.0;

// Соседние биомы (-1 = нет соседа)
uniform float left_biome : hint_range(-1.0, 6.0) = -1.0;
uniform float right_biome : hint_range(-1.0, 6.0) = -1.0;
uniform float top_biome : hint_range(-1.0, 6.0) = -1.0;
uniform float bottom_biome : hint_range(-1.0, 6.0) = -1.0;

// Параметры blending
uniform float blend_width : hint_range(0.0, 0.5) = 0.1;  // Ширина зоны смешивания
uniform float noise_scale : hint_range(1.0, 10.0) = 4.0;  // Масштаб шума для переходов

// Hash для noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 2D noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

void fragment() {
    vec2 uv = UV;
    vec4 color = texture(biome_texture, uv);
    
    // Вычисляем distance to edge для каждой стороны
    float dist_left = uv.x;
    float dist_right = 1.0 - uv.x;
    float dist_top = uv.y;
    float dist_bottom = 1.0 - uv.y;
    
    // Проверяем есть ли соседний биом
    bool has_left = left_biome >= 0.0;
    bool has_right = right_biome >= 0.0;
    bool has_top = top_biome >= 0.0;
    bool has_bottom = bottom_biome >= 0.0;
    
    // Вычисляем blend factor для каждой границы
    float blend_left = has_left ? smoothstep(0.0, blend_width, dist_left) : 1.0;
    float blend_right = has_right ? smoothstep(0.0, blend_width, dist_right) : 1.0;
    float blend_top = has_top ? smoothstep(0.0, blend_width, dist_top) : 1.0;
    float blend_bottom = has_bottom ? smoothstep(0.0, blend_width, dist_bottom) : 1.0;
    
    // Общий blend factor (минимум из всех)
    float blend = min(min(blend_left, blend_right), min(blend_top, blend_bottom));
    
    // Добавляем noise для естественности перехода
    float n = fbm(uv * noise_scale);
    blend = mix(blend, 1.0, n * 0.3);
    
    // Применяем blend
    color.rgb *= blend;
    
    COLOR = color;
}
