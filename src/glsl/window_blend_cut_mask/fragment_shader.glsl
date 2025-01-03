#version 330

precision highp float;

uniform vec2 u_resolution;        // Tamanho da janela
uniform vec3 u_camera_position;   // Posição da câmera
uniform vec2 u_camera_rotation;   // Rotação da câmera (pitch e yaw)
uniform float u_time;             // Tempo em segundos
uniform float u_blend_strength;   // Força do smooth blending
uniform float u_shadow_intensity; // Intensidade da sombra
uniform float u_brightness;       // Brilho da cena
uniform vec3 u_global_light_dir;  // Direção da luz global
uniform vec3 u_move_cube_coord;
uniform ivec3 u_move_cube_func;
uniform int u_reflection_steps;        // Número máximo de reflexos (default: 2)
uniform float u_reflection_intensity; // Intensidade dos reflexos (default: 0.5)

#define M_PI 3.14159265358979
#define MAX_STEPS 100
#define MAX_DIST 100.0
#define MIN_DIST 0.01

out vec4 fragColor;  // Cor final do fragmento

// Constantes
const vec3 background_color = vec3(0.5); 
const float epsilon = 0.001;

// Estrutura e funções SDF
float sphereSDF(vec3 p, vec3 center, float radius) {
    return length(p - center) - radius;
}

float roundedBoxSDF(vec3 p, vec3 b, float r) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// Função de blend suave de distâncias e cores
vec4 Blend(float a, float b, vec3 colA, vec3 colB, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    float blendDst = mix(b, a, h) - k * h * (1.0 - h);
    vec3 blendCol = mix(colB, colA, h);
    return vec4(blendCol, blendDst);
}

// Cena: retorna cor e distância
vec4 sceneDistColor(vec3 p) {
    // Primitivas:
    float sphere1 = sphereSDF(p, vec3(5, sin(u_time) * 2 + 3, 6.0), 1.0);
    vec3 colSphere1 = vec3(1.0, 0.0, 0.0);

    float cube1 = roundedBoxSDF(p - vec3(5.0, 1.0, 6.0), vec3(1.0), 0.2);
    vec3 colCube1 = vec3(0.0, 1.0, 0.0);

    // Primeiro blend entre esfera1 e cubo1
    vec4 blend1 = Blend(sphere1, cube1, colSphere1, colCube1, u_blend_strength);

    float sphere2 = sphereSDF(p, vec3(0, sin(u_time) * 2 + 3, 6.0), 1.4);
    vec3 colSphere2 = vec3(1.0, 0.0, 0.0);

    float cube2 = roundedBoxSDF(p - vec3(0, 1.0, 6.0), vec3(1.0), 0.2);
    vec3 colCube2 = vec3(0.0, 1.0, 0.0);
    

    // cut
    cube2 = max(cube2, -sphere2);

    vec4 blend2 = Blend(cube2, blend1.w, colCube2, blend1.xyz, u_blend_strength);


    float sphere3 = sphereSDF(p, vec3(10, sin(u_time) * 2 + 3, 6.0), 1.4);
    vec3 colSphere3 = vec3(1.0, 0.0, 0.0);

    float cube3 = roundedBoxSDF(p - vec3(10, 1.0, 6.0), vec3(1.0), 0.2);
    vec3 colCube3 = vec3(0.0, 1.0, 0.0);

    //mask
    cube3 = max(cube3, sphere3);   

    vec4 finalBlend = Blend(cube3, blend2.w, colCube3, blend2.xyz, u_blend_strength); 

    return finalBlend; // finalBlend.xyz = cor, finalBlend.w = distancia
}

// Apenas distância para cálculo de normal e raymarch
float sceneSDF(vec3 p) {
    return sceneDistColor(p).w;
}

// Cálculo da normal no ponto p
vec3 calculateNormal(vec3 p) {
    const vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        sceneSDF(p + e.xyy) - sceneSDF(p - e.xyy),
        sceneSDF(p + e.yxy) - sceneSDF(p - e.yxy),
        sceneSDF(p + e.yyx) - sceneSDF(p - e.yyx)
    ));
}

// Raymarch simples
float RayMarch(vec3 ro, vec3 rd) {
    float d0 = 0.0;
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * d0;
        float d1 = sceneSDF(p);
        d0 += d1;
        if (d1 < MIN_DIST || d0 > MAX_DIST) break;
    }
    return d0;
}

// Estrutura de raio
struct Ray {
    vec3 origin;
    vec3 direction;
};

mat3 rotationMatrix(float pitch, float yaw) {
    float cp = cos(pitch);
    float sp = sin(pitch);
    float cy = cos(yaw);
    float sy = sin(yaw);

    return mat3(
        vec3(cy, 0, -sy),
        vec3(sp * sy, cp, sp * cy),
        vec3(cp * sy, -sp, cp * cy)
    );
}

Ray CreateCameraRay(vec2 uv) {
    vec3 ro = u_camera_position;
    mat3 rot = rotationMatrix(u_camera_rotation.x, u_camera_rotation.y);
    vec3 rd = normalize(rot * vec3(uv, 1.0));
    Ray r;
    r.origin = ro;
    r.direction = rd;
    return r;
}

// Cálculo de sombras simplificado
float CalculateShadow(vec3 p, vec3 lightDir) {
    float rayDst = 0.0;
    float shadowFactor = 1.0; // Começa sem sombra

    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 samplePoint = p + lightDir * rayDst;
        float dist = sceneSDF(samplePoint);

        if (dist < epsilon) {
            return 1.0 - u_shadow_intensity;
        }

        shadowFactor = min(shadowFactor, 10.0 * dist / rayDst);

        rayDst += dist;

        if (rayDst >= MAX_DIST) {
            break;
        }
    }

    return mix(1.0 - u_shadow_intensity, 1.0, shadowFactor);
}

// Função para calcular a cor do reflexo
vec3 calculateReflection(vec3 origin, vec3 direction, int maxSteps) {
    vec3 reflectedColor = vec3(0.0); // Acumula a cor refletida
    float reflectivity = 1.0;       // Intensidade inicial do reflexo

    for (int i = 0; i < maxSteps; i++) {
        float d = RayMarch(origin, direction);

        if (d >= MAX_DIST) {
            // Se o raio não intersecta nada, retorna a cor de fundo
            reflectedColor += background_color * reflectivity;
            break;
        }

        // Calcula o ponto de interseção
        vec3 hitPoint = origin + direction * d;
        vec3 normal = calculateNormal(hitPoint);

        // Obtemos a cor da superfície no ponto de interseção
        vec4 sceneInfo = sceneDistColor(hitPoint);
        vec3 surfaceColor = sceneInfo.xyz;

        // Iluminação local no ponto refletido
        vec3 dirToLight = normalize(u_global_light_dir);
        vec3 offset = hitPoint + normal * epsilon; // Evita auto-interseção
        float shadow = CalculateShadow(offset, dirToLight);
        float diff = max(dot(normal, dirToLight), 0.0);

        // Cor local da superfície com luz
        vec3 localColor = surfaceColor * shadow * diff * u_brightness;

        // Acumula a cor do reflexo
        reflectedColor += localColor * reflectivity;

        // Atualiza direção e origem do raio refletido
        direction = reflect(direction, normal);
        origin = hitPoint + direction * epsilon;

        // Reduz a intensidade do reflexo para reflexos subsequentes
        reflectivity *= u_reflection_intensity;

        // Interrompe se o reflexo for muito fraco
        if (reflectivity < 0.01) break;
    }

    return reflectedColor;
}

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution.xy) / u_resolution.y;
    Ray ray = CreateCameraRay(uv);

    float d = RayMarch(ray.origin, ray.direction);
    vec3 color = background_color;

    if (d < MAX_DIST) {
        vec3 hitPoint = ray.origin + ray.direction * d;
        vec3 normal = calculateNormal(hitPoint);

        // Cor local da superfície
        vec4 sceneInfo = sceneDistColor(hitPoint);
        vec3 surfaceColor = sceneInfo.xyz;

        // Iluminação local
        vec3 dirToLight = normalize(u_global_light_dir);
        vec3 offset = hitPoint + normal * epsilon;
        float shadow = CalculateShadow(offset, dirToLight);
        float diff = max(dot(normal, dirToLight), 0.0);
        vec3 localColor = surfaceColor * shadow * diff * u_brightness;

        // Calcula a cor do reflexo
        vec3 reflectionColor = calculateReflection(hitPoint, reflect(ray.direction, normal), u_reflection_steps);

        // Combina a cor local com os reflexos
        color = mix(localColor, reflectionColor, u_reflection_intensity);
    }

    fragColor = vec4(color, 1.0);
}