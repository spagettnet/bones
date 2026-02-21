import * as THREE from 'three';

const SKY_VERTEX = /* glsl */`
varying vec3 vWorldPosition;

void main() {
    vec4 worldPos = modelMatrix * vec4(position, 1.0);
    vWorldPosition = worldPos.xyz;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

const SKY_FRAGMENT = /* glsl */`
uniform vec3 uTopColor;
uniform vec3 uHorizonColor;
uniform vec3 uSunColor;
uniform vec3 uSunDirection;

varying vec3 vWorldPosition;

void main() {
    vec3 dir = normalize(vWorldPosition);
    float heightFactor = dir.y * 0.5 + 0.5;

    // Base sky gradient
    vec3 sky = mix(uHorizonColor, uTopColor, pow(clamp(heightFactor, 0.0, 1.0), 0.7));

    // Sun glow
    float sunDot = max(dot(dir, normalize(uSunDirection)), 0.0);
    float sunGlow = pow(sunDot, 80.0);
    float sunHalo = pow(sunDot, 8.0) * 0.35;
    sky += uSunColor * (sunGlow * 1.5 + sunHalo);

    // Subtle cloud wisps
    float cloudNoise = sin(dir.x * 12.0 + dir.z * 8.0) * sin(dir.x * 6.0 - dir.z * 15.0);
    cloudNoise = smoothstep(0.25, 0.55, cloudNoise) * 0.12 * (1.0 - heightFactor);
    sky += vec3(cloudNoise) * vec3(1.0, 0.95, 0.85);

    // Warm the horizon
    float horizonGlow = pow(1.0 - clamp(heightFactor, 0.0, 1.0), 3.0);
    sky += vec3(0.4, 0.2, 0.05) * horizonGlow * 0.3;

    gl_FragColor = vec4(sky, 1.0);
}
`;

export function createSky(scene) {
    const skyGeo = new THREE.SphereGeometry(400, 32, 32);
    const skyMat = new THREE.ShaderMaterial({
        side: THREE.BackSide,
        depthWrite: false,
        uniforms: {
            uTopColor: { value: new THREE.Color('#3A7BD5') },
            uHorizonColor: { value: new THREE.Color('#F0C27F') },
            uSunColor: { value: new THREE.Color('#FFE4B5') },
            uSunDirection: { value: new THREE.Vector3(30, 40, 20).normalize() },
        },
        vertexShader: SKY_VERTEX,
        fragmentShader: SKY_FRAGMENT,
    });

    const sky = new THREE.Mesh(skyGeo, skyMat);
    scene.add(sky);
    return sky;
}
