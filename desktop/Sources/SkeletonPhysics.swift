import CoreGraphics

/// Verlet integration physics for the skeleton.
/// The `top` joint is pinned to the mouse cursor. All other joints respond
/// to gravity and inertia, with distance constraints enforcing bone lengths.
@MainActor
class SkeletonPhysics {
    private(set) var pose: SkeletonPose
    private var prevPositions: [JointID: CGPoint]
    private let bones: [Bone]
    private let pinnedJoint: JointID = .top

    // Physics constants
    private let gravity: CGFloat = 800
    private let damping: CGFloat = 0.97
    private let constraintIterations: Int = 5

    // Tracking
    private var pinnedPosition: CGPoint
    private var totalVelocity: CGFloat = 0

    init(anchorPoint: CGPoint, canvasSize: CGSize) {
        self.bones = SkeletonDefinition.bones.filter { $0.length > 0 }
        self.pinnedPosition = anchorPoint

        // Start with rest pose (Y increases downward in our local coords)
        self.pose = SkeletonDefinition.restPose(hangingFrom: anchorPoint)
        self.prevPositions = pose.jointPositions
    }

    func setPinnedPosition(_ point: CGPoint) {
        pinnedPosition = point
    }

    func step(dt: CGFloat) {
        let clampedDt = min(dt, 1.0 / 30.0) // Cap dt to prevent explosion

        // 1. Verlet integration for all non-pinned joints
        var newPositions = pose.jointPositions
        totalVelocity = 0

        for joint in JointID.allCases {
            if joint == pinnedJoint { continue }

            guard let pos = pose.jointPositions[joint],
                  let prev = prevPositions[joint] else { continue }

            // Velocity = current - previous (Verlet)
            let vx = (pos.x - prev.x) * damping
            let vy = (pos.y - prev.y) * damping

            // New position with gravity (Y increases downward)
            let nx = pos.x + vx
            let ny = pos.y + vy + gravity * clampedDt * clampedDt

            newPositions[joint] = CGPoint(x: nx, y: ny)
            totalVelocity += hypot(vx, vy)
        }

        // Save previous positions before constraint solving
        prevPositions = pose.jointPositions

        // Pin the top joint
        newPositions[pinnedJoint] = pinnedPosition

        // 2. Solve distance constraints
        for _ in 0..<constraintIterations {
            for bone in bones {
                guard let p1 = newPositions[bone.parentJoint],
                      let p2 = newPositions[bone.childJoint] else { continue }

                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let dist = hypot(dx, dy)
                guard dist > 0.001 else { continue }

                let diff = (bone.length - dist) / dist
                let correction = diff * bone.softness * 0.5

                let cx = dx * correction
                let cy = dy * correction

                // Parent moves less if it's closer to the root (pinned joint)
                if bone.parentJoint == pinnedJoint {
                    // Only move the child
                    newPositions[bone.childJoint] = CGPoint(x: p2.x + cx * 2, y: p2.y + cy * 2)
                } else {
                    newPositions[bone.parentJoint] = CGPoint(x: p1.x - cx, y: p1.y - cy)
                    newPositions[bone.childJoint] = CGPoint(x: p2.x + cx, y: p2.y + cy)
                }
            }

            // Re-pin after each iteration
            newPositions[pinnedJoint] = pinnedPosition
        }

        // Sync derived joints that share positions
        // shoulderLeft/Right track shoulder
        if let shoulder = newPositions[.shoulder] {
            newPositions[.shoulderLeft] = shoulder
            newPositions[.shoulderRight] = shoulder
        }
        // hipLeft/Right track hip
        if let hip = newPositions[.hip] {
            newPositions[.hipLeft] = hip
            newPositions[.hipRight] = hip
        }
        // skullTop tracks top
        newPositions[.skullTop] = pinnedPosition

        pose.jointPositions = newPositions
    }

    /// Total velocity magnitude of all bones (for sound triggering)
    func currentVelocity() -> CGFloat {
        return totalVelocity
    }

    /// Reset to rest pose hanging from a point
    func resetToRestPose(hangingFrom point: CGPoint) {
        pinnedPosition = point
        pose = SkeletonDefinition.restPose(hangingFrom: point)
        prevPositions = pose.jointPositions
        totalVelocity = 0
    }
}
