import CoreGraphics

/// Verlet integration physics for the skeleton.
/// Heavily dampened for a gentle, pendulum-like sway.
/// Cross-constraints prevent the skeleton from collapsing into a line.
@MainActor
class SkeletonPhysics {
    private(set) var pose: SkeletonPose
    private var prevPositions: [JointID: CGPoint]
    private let bones: [Bone]
    private let crossConstraints: [(JointID, JointID, CGFloat)] // structural width constraints
    private let pinnedJoint: JointID = .top

    // Physics constants
    private let gravity: CGFloat = 350
    private let damping: CGFloat = 0.82
    private let constraintIterations: Int = 10
    private let deltaScale: CGFloat = 0.35

    // Tracking
    private var pinnedPosition: CGPoint
    private var totalVelocity: CGFloat = 0
    private var pendingDelta: CGPoint = .zero

    init(anchorPoint: CGPoint, canvasSize: CGSize) {
        self.bones = SkeletonDefinition.bones.filter { $0.length > 0 }
        self.pinnedPosition = anchorPoint
        self.pose = SkeletonDefinition.restPose(hangingFrom: anchorPoint)
        self.prevPositions = pose.jointPositions

        // Cross-constraints keep the skeleton from collapsing to a vertical line.
        // These enforce minimum distances between sibling joints.
        let rest = self.pose
        func dist(_ a: JointID, _ b: JointID) -> CGFloat {
            let pa = rest.position(of: a)
            let pb = rest.position(of: b)
            return hypot(pa.x - pb.x, pa.y - pb.y)
        }
        self.crossConstraints = [
            // Rib spread
            (.ribLeftEnd1, .ribRightEnd1, dist(.ribLeftEnd1, .ribRightEnd1)),
            (.ribLeftEnd2, .ribRightEnd2, dist(.ribLeftEnd2, .ribRightEnd2)),
            (.ribLeftEnd3, .ribRightEnd3, dist(.ribLeftEnd3, .ribRightEnd3)),
            // Arm spread
            (.elbowLeft, .elbowRight, dist(.elbowLeft, .elbowRight) * 0.8),
            (.handLeft, .handRight, dist(.handLeft, .handRight) * 0.7),
            // Leg spread
            (.kneeLeft, .kneeRight, dist(.kneeLeft, .kneeRight) * 0.8),
            (.footLeft, .footRight, dist(.footLeft, .footRight) * 0.7),
            // Rib-to-spine triangulation (keeps ribs from folding behind spine)
            (.ribLeftEnd1, .hip, dist(.ribLeftEnd1, .hip) * 0.6),
            (.ribRightEnd1, .hip, dist(.ribRightEnd1, .hip) * 0.6),
        ]
    }

    func setPinnedPosition(_ point: CGPoint) {
        pinnedPosition = point
    }

    func applyWindowDelta(dx: CGFloat, dy: CGFloat) {
        pendingDelta.x += dx * deltaScale
        pendingDelta.y += dy * deltaScale
    }

    func step(dt: CGFloat) {
        let clampedDt = min(dt, 1.0 / 30.0)

        // Apply mouse delta to previous positions for inertia
        if pendingDelta.x != 0 || pendingDelta.y != 0 {
            for joint in JointID.allCases {
                if joint == pinnedJoint { continue }
                if var prev = prevPositions[joint] {
                    prev.x += pendingDelta.x
                    prev.y += pendingDelta.y
                    prevPositions[joint] = prev
                }
            }
            pendingDelta = .zero
        }

        // 1. Verlet integration
        var newPositions = pose.jointPositions
        totalVelocity = 0

        for joint in JointID.allCases {
            if joint == pinnedJoint { continue }
            guard let pos = pose.jointPositions[joint],
                  let prev = prevPositions[joint] else { continue }

            var vx = (pos.x - prev.x) * damping
            var vy = (pos.y - prev.y) * damping

            let maxV: CGFloat = 150
            vx = max(-maxV, min(maxV, vx))
            vy = max(-maxV, min(maxV, vy))

            newPositions[joint] = CGPoint(x: pos.x + vx, y: pos.y + vy + gravity * clampedDt * clampedDt)
            totalVelocity += hypot(vx, vy)
        }

        prevPositions = pose.jointPositions
        newPositions[pinnedJoint] = pinnedPosition

        // 2. Solve bone length constraints + cross-constraints
        for _ in 0..<constraintIterations {
            // Bone length constraints
            for bone in bones {
                solveDistanceConstraint(
                    &newPositions,
                    a: bone.parentJoint, b: bone.childJoint,
                    targetDist: bone.length,
                    stiffness: bone.softness,
                    pinA: bone.parentJoint == pinnedJoint
                )
            }

            // Cross-constraints (structural width)
            for (a, b, targetDist) in crossConstraints {
                solveDistanceConstraint(
                    &newPositions,
                    a: a, b: b,
                    targetDist: targetDist,
                    stiffness: 0.5,  // softer than bone constraints
                    pinA: false
                )
            }

            newPositions[pinnedJoint] = pinnedPosition
        }

        // Sync derived joints
        if let shoulder = newPositions[.shoulder] {
            newPositions[.shoulderLeft] = shoulder
            newPositions[.shoulderRight] = shoulder
        }
        if let hip = newPositions[.hip] {
            newPositions[.hipLeft] = hip
            newPositions[.hipRight] = hip
        }
        newPositions[.skullTop] = pinnedPosition

        pose.jointPositions = newPositions
    }

    private func solveDistanceConstraint(
        _ positions: inout [JointID: CGPoint],
        a: JointID, b: JointID,
        targetDist: CGFloat,
        stiffness: CGFloat,
        pinA: Bool
    ) {
        guard let p1 = positions[a], let p2 = positions[b] else { return }
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let dist = hypot(dx, dy)
        guard dist > 0.001 else { return }

        let diff = (targetDist - dist) / dist
        let cx = dx * diff * stiffness * 0.5
        let cy = dy * diff * stiffness * 0.5

        if pinA {
            positions[b] = CGPoint(x: p2.x + cx * 2, y: p2.y + cy * 2)
        } else {
            positions[a] = CGPoint(x: p1.x - cx, y: p1.y - cy)
            positions[b] = CGPoint(x: p2.x + cx, y: p2.y + cy)
        }
    }

    func currentVelocity() -> CGFloat {
        return totalVelocity
    }

    func resetToRestPose(hangingFrom point: CGPoint) {
        pinnedPosition = point
        pose = SkeletonDefinition.restPose(hangingFrom: point)
        prevPositions = pose.jointPositions
        totalVelocity = 0
        pendingDelta = .zero
    }
}
