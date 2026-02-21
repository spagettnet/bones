import * as THREE from 'three';

export function setupLighting(scene) {
    // Warm directional sun (golden hour, low angle)
    const sunLight = new THREE.DirectionalLight('#FFE4B5', 1.3);
    sunLight.position.set(30, 40, 20);
    sunLight.castShadow = true;
    sunLight.shadow.mapSize.set(2048, 2048);
    sunLight.shadow.camera.near = 0.5;
    sunLight.shadow.camera.far = 150;
    sunLight.shadow.camera.left = -60;
    sunLight.shadow.camera.right = 60;
    sunLight.shadow.camera.top = 60;
    sunLight.shadow.camera.bottom = -60;
    sunLight.shadow.bias = -0.001;
    sunLight.shadow.normalBias = 0.02;

    // Purple-warm ambient (fills shadows with color, not black)
    const ambientLight = new THREE.AmbientLight('#5B4A6F', 0.35);

    // Hemisphere: sky blue above, grass green below
    const hemiLight = new THREE.HemisphereLight('#87CEEB', '#5B8C4A', 0.3);

    scene.add(sunLight, ambientLight, hemiLight);

    return { sunLight, ambientLight, hemiLight };
}
