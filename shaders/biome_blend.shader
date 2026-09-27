shader_type canvas_item;

// Шейдер плавного смешивания биомов
// Принимает две текстуры и смешивает их на основе noise

uniform sampler2D tex_a : hint_default_white;  // Текстура биома A (трава)
uniform sampler2D tex_b : hint_default_white;  // Текстура биома B (песок)
uniform float blend_width : hint_range(0.0, 1.0) = 0.3;  // Ширина перехода
uniform float noise_scale : hint_range(1.0, 10.0) = 3.0;  // Масштаб шума
uniform float time : hint_range(0.0, 100.0) = 0.0;  // Для анимации (опционально)

// Простой hash для noise
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

// Fractal noise для более естественных переходов
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
    // Базовые UV координаты
    vec2 uv = UV;
    
    // Получаем цвета из обеих текстур
    vec4 color_a = texture(tex_a, uv);
    vec4 color_b = texture(tex_b, uv);
    
    // Вычисляем noise для плавного перехода
    float n = fbm(uv * noise_scale);
    
    // Создаём градиент смешивания на основе noise
    float blend = smoothstep(0.5 - blend_width, 0.5 + blend_width, n);
    
    // Смешиваем текстуры
    vec4 final_color = mix(color_a, color_b, blend);
    
    COLOR = final_color;
}
