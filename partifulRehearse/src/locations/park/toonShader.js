import * as THREE from 'three';

const TOON_VERTEX = /* glsl */`
#include <fog_pars_vertex>

varying vec3 vNormal;
varying vec3 vViewDir;
varying vec3 vWorldPosition;
varying vec2 vUv;

void main() {
    vec4 modelPosition = modelMatrix * vec4(position, 1.0);
    vec4 viewPosition = viewMatrix * modelPosition;

    vNormal = normalize(normalMatrix * normal);
    vViewDir = normalize(-viewPosition.xyz);
    vWorldPosition = modelPosition.xyz;
    vUv = uv;

    gl_Position = projectionMatrix * viewPosition;

    #ifdef USE_FOG
        vFogDepth = -viewPosition.z;
    #endif
}
`;

const TOON_FRAGMENT = /* glsl */`
#include <common>
#include <packing>
#include <lights_pars_begin>
#include <fog_pars_fragment>

uniform vec3 uColor;
uniform vec3 uAmbientColor;
uniform float uGlossiness;
uniform float uRimPower;
uniform vec3 uRimColor;
uniform float uShadowSteps;

varying vec3 vNormal;
varying vec3 vViewDir;
varying vec3 vWorldPosition;
varying vec2 vUv;

void main() {
    vec3 normal = normalize(vNormal);
    vec3 viewDir = normalize(vViewDir);

    // Directional light diffuse
    #if NUM_DIR_LIGHTS > 0
    vec3 lightDir = directionalLights[0].direction;
    vec3 lightColor = directionalLights[0].color;
    #else
    vec3 lightDir = normalize(vec3(1.0, 1.0, 0.5));
    vec3 lightColor = vec3(1.0, 0.95, 0.8);
    #endif

    float NdotL = dot(normal, lightDir);

    // Quantize into discrete bands
    float bands = uShadowSteps;
    float rawBand = NdotL * bands;
    float lightIntensity = floor(max(rawBand, 0.0)) / bands;

    // Smooth band edges slightly
    float bandEdge = fract(max(rawBand, 0.0));
    lightIntensity += smoothstep(0.0, 0.07, bandEdge) / bands;
    lightIntensity = clamp(lightIntensity, 0.0, 1.0);

    vec3 diffuse = lightColor * lightIntensity;

    // Point lights contribution
    vec3 pointLightContrib = vec3(0.0);
    #if NUM_POINT_LIGHTS > 0
    for (int i = 0; i < NUM_POINT_LIGHTS; i++) {
        vec3 plDir = pointLights[i].position - vWorldPosition;
        float plDist = length(plDir);
        plDir = normalize(plDir);
        float plAtten = 1.0 / (1.0 + plDist * plDist * 0.05);
        float plNdotL = max(dot(normal, plDir), 0.0);
        float plBanded = floor(plNdotL * 3.0) / 3.0;
        pointLightContrib += pointLights[i].color * plBanded * plAtten;
    }
    #endif

    // Specular (Blinn-Phong, hard cutoff)
    vec3 halfDir = normalize(lightDir + viewDir);
    float specAngle = max(dot(normal, halfDir), 0.0);
    float specular = pow(specAngle, uGlossiness);
    specular = smoothstep(0.4, 0.41, specular);

    // Rim lighting
    float rimDot = 1.0 - max(dot(viewDir, normal), 0.0);
    float rimIntensity = smoothstep(0.55, 0.56, rimDot * pow(max(NdotL, 0.0) + 0.3, 0.25));
    vec3 rim = uRimColor * rimIntensity;

    // Combine
    vec3 ambient = uAmbientColor * 0.45;
    vec3 finalColor = uColor * (ambient + diffuse + pointLightContrib) + specular * lightColor * 0.25 + rim;

    gl_FragColor = vec4(finalColor, 1.0);

    #include <fog_fragment>
}
`;

export const PALETTE = {
    GRASS_LIGHT:    '#7DB46C',
    GRASS_DARK:     '#4A7A3F',
    TREE_TRUNK:     '#5C4033',
    TREE_CANOPY:    '#5B8C4A',
    TREE_CANOPY_2:  '#7BAA5E',

    STONE_LIGHT:    '#C8BEB0',
    STONE_DARK:     '#6B5F54',
    MARBLE_WHITE:   '#E8E0D4',
    FOUNTAIN_STONE: '#A09888',

    COBBLE_LIGHT:   '#9B8B7A',
    COBBLE_DARK:    '#6B5F54',

    BENCH_WOOD:     '#6B4F3A',
    IRON_FENCE:     '#3A3A3A',

    WATER_PARK:     '#5BA5C9',
};

export function createToonMaterial(color, options = {}) {
    return new THREE.ShaderMaterial({
        lights: true,
        fog: true,
        uniforms: {
            ...THREE.UniformsLib.lights,
            ...THREE.UniformsLib.fog,
            uColor: { value: new THREE.Color(color) },
            uAmbientColor: { value: new THREE.Color(options.ambient || '#7B6A8F') },
            uGlossiness: { value: options.glossiness || 32.0 },
            uRimPower: { value: options.rimPower || 2.0 },
            uRimColor: { value: new THREE.Color(options.rimColor || '#ffeedd') },
            uShadowSteps: { value: options.shadowSteps || 4.0 },
        },
        vertexShader: TOON_VERTEX,
        fragmentShader: TOON_FRAGMENT,
    });
}
