import * as THREE from 'three';

export function createPollen(scene, count = 150) {
    const positions = new Float32Array(count * 3);
    const phases = new Float32Array(count);

    for (let i = 0; i < count; i++) {
        positions[i * 3] = (Math.random() - 0.5) * 80;
        positions[i * 3 + 1] = Math.random() * 3.7 + 0.3;
        positions[i * 3 + 2] = (Math.random() - 0.5) * 80;
        phases[i] = Math.random() * Math.PI * 2;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('aPhase', new THREE.BufferAttribute(phases, 1));

    const material = new THREE.ShaderMaterial({
        transparent: true,
        depthWrite: false,
        uniforms: {
            uTime: { value: 0 },
            uSize: { value: 18.0 },
        },
        vertexShader: /* glsl */`
            attribute float aPhase;
            uniform float uTime;
            uniform float uSize;
            varying float vAlpha;

            void main() {
                vec3 pos = position;
                pos.y += sin(uTime * 0.2 + aPhase) * 0.8;
                pos.x += sin(uTime * 0.15 + aPhase * 1.3) * 1.0;
                pos.z += cos(uTime * 0.18 + aPhase * 0.7) * 0.6;

                // Gentle catch-the-light effect
                vAlpha = (sin(uTime * 1.5 + aPhase * 5.0) + 1.0) * 0.3 + 0.1;

                vec4 mvPos = modelViewMatrix * vec4(pos, 1.0);
                gl_PointSize = uSize / -mvPos.z;
                gl_Position = projectionMatrix * mvPos;
            }
        `,
        fragmentShader: /* glsl */`
            varying float vAlpha;

            void main() {
                float d = length(gl_PointCoord - 0.5) * 2.0;
                float dot = 1.0 - smoothstep(0.0, 1.0, d);
                gl_FragColor = vec4(1.0, 0.92, 0.7, dot * vAlpha * 0.45);
            }
        `,
    });

    const points = new THREE.Points(geometry, material);
    scene.add(points);
    return { points, material };
}
