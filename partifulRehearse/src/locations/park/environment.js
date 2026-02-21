import * as THREE from 'three';
import { createToonMaterial, PALETTE } from './toonShader.js';

export function buildPark(scene) {
    const wallBounds = [];

    // --- Ground ---
    const ground = new THREE.Mesh(
        new THREE.PlaneGeometry(80, 80),
        new THREE.MeshStandardMaterial({ color: PALETTE.GRASS_LIGHT, roughness: 0.9 })
    );
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    scene.add(ground);

    // --- Washington Arch ---
    buildArch(scene, wallBounds);

    // --- Central Fountain ---
    buildFountain(scene, wallBounds);

    // --- Paths ---
    buildPaths(scene);

    // --- Trees ---
    buildTrees(scene, wallBounds);

    // --- Benches ---
    buildBenches(scene, wallBounds);

    // --- Chess Tables ---
    buildChessTables(scene, wallBounds);

    // --- Bushes ---
    buildBushes(scene);

    // --- Perimeter Fence ---
    buildFence(scene, wallBounds);

    return wallBounds;
}

function buildArch(scene, wallBounds) {
    const marbleMat = createToonMaterial(PALETTE.MARBLE_WHITE, { glossiness: 48 });
    const archGroup = new THREE.Group();
    archGroup.position.set(0, 0, -32);

    // Two pillars
    for (const side of [-1, 1]) {
        const pillar = new THREE.Mesh(new THREE.BoxGeometry(2, 10, 3), marbleMat);
        pillar.position.set(side * 4, 5, 0);
        pillar.castShadow = true;
        archGroup.add(pillar);
    }

    // Lintel
    const lintel = new THREE.Mesh(new THREE.BoxGeometry(10, 2, 3), marbleMat);
    lintel.position.set(0, 9, 0);
    lintel.castShadow = true;
    archGroup.add(lintel);

    // Cornice
    const cornice = new THREE.Mesh(new THREE.BoxGeometry(11, 0.5, 3.2), marbleMat);
    cornice.position.set(0, 10, 0);
    cornice.castShadow = true;
    archGroup.add(cornice);

    scene.add(archGroup);

    // Collision for pillars
    for (const side of [-1, 1]) {
        wallBounds.push(new THREE.Box3(
            new THREE.Vector3(side * 4 - 1 + 0, 0, -32 - 1.5),
            new THREE.Vector3(side * 4 + 1 + 0, 10, -32 + 1.5)
        ));
    }
}

function buildFountain(scene, wallBounds) {
    const stoneMat = createToonMaterial(PALETTE.FOUNTAIN_STONE, { glossiness: 24 });
    const waterMat = createToonMaterial(PALETTE.WATER_PARK, { glossiness: 64, rimColor: '#aaddff' });
    const fountainGroup = new THREE.Group();

    // Basin rim (torus)
    const rim = new THREE.Mesh(new THREE.TorusGeometry(5, 0.4, 8, 24), stoneMat);
    rim.position.y = 1.0;
    rim.rotation.x = -Math.PI / 2;
    rim.castShadow = true;
    fountainGroup.add(rim);

    // Basin wall (cylinder)
    const wall = new THREE.Mesh(
        new THREE.CylinderGeometry(5, 5, 1, 24, 1, true),
        stoneMat
    );
    wall.position.y = 0.5;
    wall.castShadow = true;
    fountainGroup.add(wall);

    // Water surface
    const water = new THREE.Mesh(new THREE.CircleGeometry(4.5, 24), waterMat);
    water.rotation.x = -Math.PI / 2;
    water.position.y = 0.4;
    fountainGroup.add(water);

    // Central pedestal
    const pedestal = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.6, 2, 8), stoneMat);
    pedestal.position.y = 1.0;
    pedestal.castShadow = true;
    fountainGroup.add(pedestal);

    scene.add(fountainGroup);

    // Collision: 4 box segments forming a square ring around the fountain
    const r = 5.2, t = 1.0;
    wallBounds.push(new THREE.Box3(new THREE.Vector3(-r, 0, -r), new THREE.Vector3(r, 1.5, -r + t)));
    wallBounds.push(new THREE.Box3(new THREE.Vector3(-r, 0, r - t), new THREE.Vector3(r, 1.5, r)));
    wallBounds.push(new THREE.Box3(new THREE.Vector3(-r, 0, -r), new THREE.Vector3(-r + t, 1.5, r)));
    wallBounds.push(new THREE.Box3(new THREE.Vector3(r - t, 0, -r), new THREE.Vector3(r, 1.5, r)));
}

function buildPaths(scene) {
    const pathMat = new THREE.MeshStandardMaterial({ color: PALETTE.COBBLE_LIGHT, roughness: 0.95 });

    // North approach: fountain to arch
    const north = new THREE.Mesh(new THREE.PlaneGeometry(4, 22), pathMat);
    north.rotation.x = -Math.PI / 2;
    north.position.set(0, 0.01, -16);
    north.receiveShadow = true;
    scene.add(north);

    // South approach
    const south = new THREE.Mesh(new THREE.PlaneGeometry(4, 22), pathMat);
    south.rotation.x = -Math.PI / 2;
    south.position.set(0, 0.01, 16);
    south.receiveShadow = true;
    scene.add(south);

    // 4 diagonal paths from fountain toward corners
    const diagonals = [
        { x: 14, z: -14, angle: Math.PI / 4 },
        { x: -14, z: -14, angle: -Math.PI / 4 },
        { x: 14, z: 14, angle: -Math.PI / 4 },
        { x: -14, z: 14, angle: Math.PI / 4 },
    ];

    for (const d of diagonals) {
        const diag = new THREE.Mesh(new THREE.PlaneGeometry(3, 30), pathMat);
        diag.rotation.x = -Math.PI / 2;
        diag.rotation.z = d.angle;
        diag.position.set(d.x, 0.01, d.z);
        diag.receiveShadow = true;
        scene.add(diag);
    }
}

function buildTrees(scene, wallBounds) {
    const trunkMat = createToonMaterial(PALETTE.TREE_TRUNK);
    const canopyMat = createToonMaterial(PALETTE.TREE_CANOPY, { shadowSteps: 3 });
    const canopyMat2 = createToonMaterial(PALETTE.TREE_CANOPY_2, { shadowSteps: 3 });

    // Tree positions along paths and in grassy areas
    const treePositions = [];

    // Trees along north path (left and right)
    for (let z = -8; z >= -28; z -= 5) {
        treePositions.push([-4.5, z]);
        treePositions.push([4.5, z]);
    }

    // Trees along south path
    for (let z = 8; z <= 28; z += 5) {
        treePositions.push([-4.5, z]);
        treePositions.push([4.5, z]);
    }

    // Trees along NE diagonal
    treePositions.push([10, -10], [16, -16], [20, -20]);
    // Trees along NW diagonal
    treePositions.push([-10, -10], [-16, -16], [-20, -20]);
    // Trees along SE diagonal
    treePositions.push([10, 10], [16, 16], [20, 20]);
    // Trees along SW diagonal
    treePositions.push([-10, 10], [-16, 16], [-20, 20]);

    // Extra trees in open areas
    treePositions.push(
        [-28, -5], [-28, 5], [28, -5], [28, 5],
        [-25, -25], [25, -25], [-25, 25], [25, 25],
        [-30, 0], [30, 0], [-15, 0], [15, 0]
    );

    for (const [tx, tz] of treePositions) {
        const h = 2.5 + Math.random() * 2;
        const tree = new THREE.Group();

        // Trunk
        const trunk = new THREE.Mesh(
            new THREE.CylinderGeometry(0.2, 0.35, h, 6),
            trunkMat
        );
        trunk.position.y = h / 2;
        trunk.castShadow = true;
        tree.add(trunk);

        // Canopy: 2-3 stacked icosahedrons with vertex noise
        const layers = 2 + Math.floor(Math.random() * 2);
        for (let i = 0; i < layers; i++) {
            const radius = 1.5 + Math.random() * 0.8 - i * 0.3;
            const geo = new THREE.IcosahedronGeometry(radius, 1);
            // Vertex noise
            const posAttr = geo.attributes.position;
            for (let v = 0; v < posAttr.count; v++) {
                posAttr.setX(v, posAttr.getX(v) + (Math.random() - 0.5) * 0.4);
                posAttr.setY(v, posAttr.getY(v) + (Math.random() - 0.5) * 0.3);
                posAttr.setZ(v, posAttr.getZ(v) + (Math.random() - 0.5) * 0.4);
            }
            geo.computeVertexNormals();

            const mat = i % 2 === 0 ? canopyMat : canopyMat2;
            const canopy = new THREE.Mesh(geo, mat);
            canopy.position.y = h + i * 1.2 + 0.5;
            canopy.castShadow = true;
            tree.add(canopy);
        }

        tree.position.set(tx, 0, tz);
        scene.add(tree);

        // Trunk collision
        wallBounds.push(new THREE.Box3(
            new THREE.Vector3(tx - 0.35, 0, tz - 0.35),
            new THREE.Vector3(tx + 0.35, h, tz + 0.35)
        ));
    }
}

function buildBenches(scene, wallBounds) {
    const woodMat = createToonMaterial(PALETTE.BENCH_WOOD);
    const ironMat = createToonMaterial(PALETTE.IRON_FENCE, { glossiness: 16 });

    const benchPositions = [
        // Along north path
        { x: -6.5, z: -12, ry: Math.PI / 2 },
        { x: 6.5, z: -12, ry: -Math.PI / 2 },
        { x: -6.5, z: -20, ry: Math.PI / 2 },
        { x: 6.5, z: -20, ry: -Math.PI / 2 },
        // Along south path
        { x: -6.5, z: 12, ry: Math.PI / 2 },
        { x: 6.5, z: 12, ry: -Math.PI / 2 },
        // Along diagonals
        { x: 14, z: -14, ry: Math.PI / 4 },
        { x: -14, z: -14, ry: -Math.PI / 4 },
        { x: 14, z: 14, ry: -Math.PI / 4 },
        { x: -14, z: 14, ry: Math.PI / 4 },
    ];

    for (const bp of benchPositions) {
        const bench = new THREE.Group();

        // Seat
        const seat = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.08, 0.6), woodMat);
        seat.position.y = 0.45;
        seat.castShadow = true;
        bench.add(seat);

        // Back
        const back = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.5, 0.06), woodMat);
        back.position.set(0, 0.7, -0.27);
        back.castShadow = true;
        bench.add(back);

        // Legs (4)
        for (const sx of [-0.7, 0.7]) {
            for (const sz of [-0.2, 0.2]) {
                const leg = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.45, 0.06), ironMat);
                leg.position.set(sx, 0.22, sz);
                bench.add(leg);
            }
        }

        // Armrests
        for (const side of [-1, 1]) {
            const arm = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.06, 0.6), ironMat);
            arm.position.set(side * 0.87, 0.55, 0);
            bench.add(arm);
        }

        bench.position.set(bp.x, 0, bp.z);
        bench.rotation.y = bp.ry;
        scene.add(bench);

        // Collision
        const halfW = 0.9, halfD = 0.3;
        const cos = Math.cos(bp.ry), sin = Math.sin(bp.ry);
        const ext = Math.abs(halfW * cos) + Math.abs(halfD * sin);
        const extz = Math.abs(halfW * sin) + Math.abs(halfD * cos);
        wallBounds.push(new THREE.Box3(
            new THREE.Vector3(bp.x - ext, 0, bp.z - extz),
            new THREE.Vector3(bp.x + ext, 1.0, bp.z + extz)
        ));
    }
}

function buildChessTables(scene, wallBounds) {
    const stoneMat = createToonMaterial(PALETTE.STONE_DARK, { glossiness: 16 });

    const baseX = -22, baseZ = 22;
    const spacing = 3;

    for (let row = 0; row < 2; row++) {
        for (let col = 0; col < 2; col++) {
            const tx = baseX + col * spacing;
            const tz = baseZ + row * spacing;
            const tableGroup = new THREE.Group();

            // Table
            const table = new THREE.Mesh(new THREE.BoxGeometry(1.0, 0.7, 1.0), stoneMat);
            table.position.y = 0.35;
            table.castShadow = true;
            tableGroup.add(table);

            // 2 stools
            for (const side of [-1, 1]) {
                const stool = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.25, 0.45, 8), stoneMat);
                stool.position.set(side * 0.9, 0.22, 0);
                stool.castShadow = true;
                tableGroup.add(stool);
            }

            tableGroup.position.set(tx, 0, tz);
            scene.add(tableGroup);

            wallBounds.push(new THREE.Box3(
                new THREE.Vector3(tx - 0.5, 0, tz - 0.5),
                new THREE.Vector3(tx + 0.5, 0.7, tz + 0.5)
            ));
        }
    }
}

function buildBushes(scene) {
    const bushMat = createToonMaterial(PALETTE.TREE_CANOPY, { shadowSteps: 2 });
    const bushMat2 = createToonMaterial(PALETTE.GRASS_DARK, { shadowSteps: 2 });

    const bushPositions = [
        [-18, -5], [18, -5], [-18, 5], [18, 5],
        [-8, 18], [8, 18], [-8, -25], [8, -25],
        [-30, 15], [30, -15],
    ];

    for (let i = 0; i < bushPositions.length; i++) {
        const [bx, bz] = bushPositions[i];
        const radius = 0.8 + Math.random() * 0.5;
        const geo = new THREE.SphereGeometry(radius, 8, 6);

        // Vertex noise
        const posAttr = geo.attributes.position;
        for (let v = 0; v < posAttr.count; v++) {
            posAttr.setX(v, posAttr.getX(v) + (Math.random() - 0.5) * 0.2);
            posAttr.setY(v, posAttr.getY(v) * 0.6 + (Math.random() - 0.5) * 0.1);
            posAttr.setZ(v, posAttr.getZ(v) + (Math.random() - 0.5) * 0.2);
        }
        geo.computeVertexNormals();

        const bush = new THREE.Mesh(geo, i % 2 === 0 ? bushMat : bushMat2);
        bush.position.set(bx, radius * 0.35, bz);
        bush.castShadow = true;
        scene.add(bush);
    }
}

function buildFence(scene, wallBounds) {
    const fenceMat = createToonMaterial(PALETTE.IRON_FENCE, { glossiness: 16 });
    const postHeight = 1.0;
    const postSpacing = 3;
    const extent = 37;
    const entranceGap = 5; // gap at center of each side for entrances

    // Build fence along each side with gaps for entrances
    for (const axis of ['x', 'z']) {
        for (const sign of [-1, 1]) {
            const fixedVal = sign * extent;

            // Determine range: skip gap at center
            const posts = [];
            for (let v = -extent; v <= extent; v += postSpacing) {
                // Skip entrance gap at center
                if (Math.abs(v) < entranceGap) continue;
                posts.push(v);
            }

            for (const v of posts) {
                const post = new THREE.Mesh(new THREE.BoxGeometry(0.1, postHeight, 0.1), fenceMat);
                if (axis === 'z') {
                    post.position.set(v, postHeight / 2, fixedVal);
                } else {
                    post.position.set(fixedVal, postHeight / 2, v);
                }
                post.castShadow = true;
                scene.add(post);
            }

            // Horizontal rails between posts
            for (let i = 0; i < posts.length - 1; i++) {
                const v1 = posts[i], v2 = posts[i + 1];
                // Skip rail if posts are far apart (across entrance)
                if (Math.abs(v2 - v1) > postSpacing + 1) continue;

                const len = v2 - v1;
                const mid = (v1 + v2) / 2;

                for (const rh of [0.3, 0.7]) {
                    const rail = new THREE.Mesh(new THREE.BoxGeometry(
                        axis === 'z' ? len : 0.04,
                        0.04,
                        axis === 'z' ? 0.04 : len
                    ), fenceMat);

                    if (axis === 'z') {
                        rail.position.set(mid, rh, fixedVal);
                    } else {
                        rail.position.set(fixedVal, rh, mid);
                    }
                    scene.add(rail);
                }
            }

            // Collision walls for fence segments (skip entrance gaps)
            // Left segment: from -extent to -entranceGap
            if (axis === 'z') {
                wallBounds.push(new THREE.Box3(
                    new THREE.Vector3(-extent, 0, fixedVal - 0.2),
                    new THREE.Vector3(-entranceGap, postHeight, fixedVal + 0.2)
                ));
                wallBounds.push(new THREE.Box3(
                    new THREE.Vector3(entranceGap, 0, fixedVal - 0.2),
                    new THREE.Vector3(extent, postHeight, fixedVal + 0.2)
                ));
            } else {
                wallBounds.push(new THREE.Box3(
                    new THREE.Vector3(fixedVal - 0.2, 0, -extent),
                    new THREE.Vector3(fixedVal + 0.2, postHeight, -entranceGap)
                ));
                wallBounds.push(new THREE.Box3(
                    new THREE.Vector3(fixedVal - 0.2, 0, entranceGap),
                    new THREE.Vector3(fixedVal + 0.2, postHeight, extent)
                ));
            }
        }
    }
}
