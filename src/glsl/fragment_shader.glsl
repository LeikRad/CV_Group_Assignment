#version 330

precision highp float;

struct Shape {
    vec3 position;
    vec3 size;
    vec3 colour;
    int shapeType;
    int operation;
    float blendStrength;
    int numChildren;
};

struct Ray {
    vec3 origin;
    vec3 direction;
};

layout(std140) uniform ShapesBlock {
    Shape shapes[10];
};

uniform int numShapes;
uniform vec2 u_resolution;        // Tamanho da janela
uniform vec3 u_camera_position;   // Posição da câmera
uniform vec2 u_camera_rotation;   // Rotação da câmera (pitch e yaw)
uniform float u_time;             // Tempo em segundos


#define M_PI 3.14159265358979



out vec4 fragColor;  // Cor final do fragmento

// Constantes
const vec3 background_color = vec3(0.5);  // Fundo preto
const vec3 global_light_dir = normalize(vec3(0.0, 10.0, 0.0));  // Global light direction from above
const float epsilon = 0.001;
const float shadowBias = epsilon * 50;
const float maxDst = 100;
const float max_Steps = 100;

// Função SDF para uma esfera
float SphereDistance(vec3 eye, vec3 centre, float radius) {
    return distance(eye, centre) - radius;
}

// Função SDF para um cubo
float CubeDistance(vec3 eye, vec3 centre, vec3 size) {
    vec3 o = abs(eye-centre) -size;
    float ud = length(max(o,0));
    float n = max(max(min(o.x,0),min(o.y,0)), min(o.z,0));
    return ud+n;
}

// Following distance functions from http://iquilezles.org/www/articles/distfunctions/distfunctions.htm

Ray CreateRay(vec3 origin, vec3 direction) {
    Ray ray;
    ray.origin = origin;
    ray.direction = direction;
    return ray;
}

// Cria a matriz de rotação a partir do pitch e yaw
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
    vec3 origin = u_camera_position;
    mat3 rot = rotationMatrix(u_camera_rotation.x, u_camera_rotation.y);
    vec3 direction = normalize(rot * vec3(uv, 1.0));
    return CreateRay(origin,direction);
}

// polynomial smooth min (k = 0.1);
// from https://www.iquilezles.org/www/articles/smin/smin.htm
vec4 Blend( float a, float b, vec3 colA, vec3 colB, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    float blendDst = mix( b, a, h ) - k*h*(1.0-h);
    vec3 blendCol = mix(colB,colA,h);
    return vec4(blendCol, blendDst);
}

vec4 Combine(float dstA, float dstB, vec3 colourA, vec3 colourB, int operation, float blendStrength) {
    float dst = dstA;
    vec3 colour = colourA;

    if (operation == 0) {
        if (dstB < dstA) {
            dst = dstB;
            colour = colourB;
        }
    }
    // Blend
    else if (operation == 1) {
        vec4 blend = Blend(dstA,dstB,colourA,colourB, blendStrength);
        dst = blend.w;
        colour = blend.xyz;
    }
    // Cut
    else if (operation == 2) {
        // max(a,-b)
        if (-dstB > dst) {
            dst = -dstB;
            colour = colourB;
        }
    }
    // Mask
    else if (operation == 3) {
        // max(a,b)
        if (dstB > dst) {
            dst = dstB;
            colour = colourB;
        }
    }

    return vec4(colour,dst);
}

float GetShapeDistance(Shape shape, vec3 eye) {

    if (shape.shapeType == 0) {
        return SphereDistance(eye, shape.position, shape.size.x);
    }
    else if (shape.shapeType == 1) {
        return CubeDistance(eye, shape.position, shape.size);
    }

    return maxDst;
}

vec4 SceneInfo(vec3 eye){
    float globalDst = maxDst;
    vec3 globalColour = vec3(1.0);

    for (int i = 0; i < numShapes; i ++) {
        Shape shape = shapes[i];
        int numChildren = shape.numChildren;

        float localDst = GetShapeDistance(shape,eye);
        vec3 localColour = shape.colour;


        for (int j = 0; j < numChildren; j ++) {
            Shape childShape = shapes[i+j+1];
            float childDst = GetShapeDistance(childShape,eye);

            vec4 combined = Combine(localDst, childDst, localColour, childShape.colour, childShape.operation, childShape.blendStrength);
            localColour = combined.xyz;
            localDst = combined.w;
        }
        i+=numChildren; // skip over children in outer loop

        vec4 globalCombined = Combine(globalDst, localDst, globalColour, localColour, shape.operation, shape.blendStrength);
        globalColour = globalCombined.xyz;
        globalDst = globalCombined.w;
    }

    return vec4(globalColour, globalDst);
}

// Calcula a normal da superfície no ponto p
vec3 EstimateNormal(vec3 p) {
    float x = SceneInfo(vec3(p.x+epsilon,p.y,p.z)).w - SceneInfo(vec3(p.x-epsilon,p.y,p.z)).w;
    float y = SceneInfo(vec3(p.x,p.y+epsilon,p.z)).w - SceneInfo(vec3(p.x,p.y-epsilon,p.z)).w;
    float z = SceneInfo(vec3(p.x,p.y,p.z+epsilon)).w - SceneInfo(vec3(p.x,p.y,p.z-epsilon)).w;
    return normalize(vec3(x,y,z));
}

float CalculateShadow(Ray ray, float dstToShadePoint) {
    float rayDst = 0;
    int marchSteps = 0;
    float shadowIntensity = .2;
    float brightness = 1;

    while (rayDst < dstToShadePoint) {
        marchSteps ++;
        vec4 sceneInfo = SceneInfo(ray.origin);
        float dst = sceneInfo.w;

        if (dst <= epsilon) {
            return shadowIntensity;
        }

        brightness = min(brightness,dst*200);

        ray.origin += ray.direction * dst;
        rayDst += dst;
    }
    return shadowIntensity + (1-shadowIntensity) * brightness;
}

void main() {

    uint width, height;
    width = uint(u_resolution.x);
    height = uint(u_resolution.y);

    vec2 uv = gl_FragCoord.xy / u_resolution.xy * 2.0 - 1.0;
    float rayDst = 0;

    Ray ray = CreateCameraRay(uv);
    int marchSteps = 0;

    while (rayDst < maxDst && marchSteps < max_Steps) {
        marchSteps ++;
        vec4 sceneInfo = SceneInfo(ray.origin);
        float dst = sceneInfo.w;

        if (dst <= epsilon) {
            vec3 pointOnSurface = ray.origin + ray.direction * rayDst;
            vec3 normal = EstimateNormal(pointOnSurface - ray.direction * epsilon);
            float lighting = clamp(dot(normal, global_light_dir), 0.0, 1.0);
            vec3 color = sceneInfo.xyz;

            // Apply shadows
            vec3 offset = pointOnSurface + normal * epsilon;
            vec3 dirToLight = normalize(global_light_dir - offset);

            ray.origin = offset;
            ray.direction = dirToLight;

            float dstToLight = distance(offset, global_light_dir);
            float shadow = CalculateShadow(ray, dstToLight);

            color *= shadow * lighting;
            fragColor = vec4(color, 1.0);

            break;
        }

        ray.origin += ray.direction * dst;
        rayDst += dst;
    }

    if (numShapes > 0){
        fragColor = vec4(shapes[0].colour, 1.0);
    }
}