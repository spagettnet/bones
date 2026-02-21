import AppKit
import CoreGraphics

// MARK: - Skeleton Data Model

enum BoneID: CaseIterable {
    case skull
    case spine1, spine2, spine3
    case ribLeft1, ribLeft2, ribLeft3
    case ribRight1, ribRight2, ribRight3
    case upperArmLeft, lowerArmLeft
    case upperArmRight, lowerArmRight
    case pelvis
    case upperLegLeft, lowerLegLeft
    case upperLegRight, lowerLegRight
}

enum JointID: CaseIterable, Hashable {
    case top            // attachment point (pinned to mouse)
    case skullTop
    case skullBase
    case shoulder       // where arms + ribs attach
    case midSpine
    case hip            // where legs attach
    case ribLeftEnd1, ribLeftEnd2, ribLeftEnd3
    case ribRightEnd1, ribRightEnd2, ribRightEnd3
    case shoulderLeft, elbowLeft, handLeft
    case shoulderRight, elbowRight, handRight
    case hipLeft, kneeLeft, footLeft
    case hipRight, kneeRight, footRight
}

struct Bone {
    let id: BoneID
    let parentJoint: JointID
    let childJoint: JointID
    let length: CGFloat
    let softness: CGFloat  // 1.0 = fully rigid, 0.7 = wobbly ribs
}

struct SkeletonPose {
    var jointPositions: [JointID: CGPoint]

    func position(of joint: JointID) -> CGPoint {
        return jointPositions[joint] ?? .zero
    }
}

// MARK: - Skeleton Definition

enum SkeletonDefinition {
    static let bones: [Bone] = [
        // Skull hangs from top attachment
        Bone(id: .skull, parentJoint: .top, childJoint: .skullBase, length: 14, softness: 1.0),

        // Spine segments
        Bone(id: .spine1, parentJoint: .skullBase, childJoint: .shoulder, length: 8, softness: 1.0),
        Bone(id: .spine2, parentJoint: .shoulder, childJoint: .midSpine, length: 8, softness: 1.0),
        Bone(id: .spine3, parentJoint: .midSpine, childJoint: .hip, length: 8, softness: 1.0),

        // Ribs (soft constraints for wobble)
        Bone(id: .ribLeft1, parentJoint: .shoulder, childJoint: .ribLeftEnd1, length: 10, softness: 0.6),
        Bone(id: .ribLeft2, parentJoint: .midSpine, childJoint: .ribLeftEnd2, length: 8, softness: 0.6),
        Bone(id: .ribLeft3, parentJoint: .midSpine, childJoint: .ribLeftEnd3, length: 6, softness: 0.6),
        Bone(id: .ribRight1, parentJoint: .shoulder, childJoint: .ribRightEnd1, length: 10, softness: 0.6),
        Bone(id: .ribRight2, parentJoint: .midSpine, childJoint: .ribRightEnd2, length: 8, softness: 0.6),
        Bone(id: .ribRight3, parentJoint: .midSpine, childJoint: .ribRightEnd3, length: 6, softness: 0.6),

        // Arms
        Bone(id: .upperArmLeft, parentJoint: .shoulder, childJoint: .elbowLeft, length: 12, softness: 0.85),
        Bone(id: .lowerArmLeft, parentJoint: .elbowLeft, childJoint: .handLeft, length: 10, softness: 0.85),
        Bone(id: .upperArmRight, parentJoint: .shoulder, childJoint: .elbowRight, length: 12, softness: 0.85),
        Bone(id: .lowerArmRight, parentJoint: .elbowRight, childJoint: .handRight, length: 10, softness: 0.85),

        // Pelvis
        Bone(id: .pelvis, parentJoint: .hip, childJoint: .hip, length: 0, softness: 1.0), // virtual

        // Legs
        Bone(id: .upperLegLeft, parentJoint: .hip, childJoint: .kneeLeft, length: 14, softness: 0.9),
        Bone(id: .lowerLegLeft, parentJoint: .kneeLeft, childJoint: .footLeft, length: 12, softness: 0.9),
        Bone(id: .upperLegRight, parentJoint: .hip, childJoint: .kneeRight, length: 14, softness: 0.9),
        Bone(id: .lowerLegRight, parentJoint: .kneeRight, childJoint: .footRight, length: 12, softness: 0.9),
    ]

    /// Rest pose: skeleton hanging straight down from a point
    static func restPose(hangingFrom anchor: CGPoint, flipped: Bool = false) -> SkeletonPose {
        // In flipped coordinate system (CoreGraphics), Y increases upward
        // In non-flipped (our physics), Y increases downward
        let dir: CGFloat = flipped ? -1 : 1
        var positions: [JointID: CGPoint] = [:]

        let x = anchor.x
        var y = anchor.y

        positions[.top] = CGPoint(x: x, y: y)

        // Skull
        y += 14 * dir
        positions[.skullBase] = CGPoint(x: x, y: y)

        // Spine
        y += 8 * dir
        positions[.shoulder] = CGPoint(x: x, y: y)

        // Shoulder joints for arms
        positions[.shoulderLeft] = CGPoint(x: x, y: y)
        positions[.shoulderRight] = CGPoint(x: x, y: y)

        // Ribs from shoulder
        positions[.ribLeftEnd1] = CGPoint(x: x - 10, y: y + 2 * dir)
        positions[.ribRightEnd1] = CGPoint(x: x + 10, y: y + 2 * dir)

        y += 8 * dir
        positions[.midSpine] = CGPoint(x: x, y: y)

        // More ribs
        positions[.ribLeftEnd2] = CGPoint(x: x - 8, y: y + 1 * dir)
        positions[.ribRightEnd2] = CGPoint(x: x + 8, y: y + 1 * dir)
        positions[.ribLeftEnd3] = CGPoint(x: x - 6, y: y + 4 * dir)
        positions[.ribRightEnd3] = CGPoint(x: x + 6, y: y + 4 * dir)

        y += 8 * dir
        positions[.hip] = CGPoint(x: x, y: y)
        positions[.hipLeft] = CGPoint(x: x, y: y)
        positions[.hipRight] = CGPoint(x: x, y: y)

        // Arms hanging down
        positions[.elbowLeft] = CGPoint(x: x - 6, y: y - 4 * dir)
        positions[.handLeft] = CGPoint(x: x - 8, y: y + 6 * dir)
        positions[.elbowRight] = CGPoint(x: x + 6, y: y - 4 * dir)
        positions[.handRight] = CGPoint(x: x + 8, y: y + 6 * dir)

        // Legs
        y += 14 * dir
        positions[.kneeLeft] = CGPoint(x: x - 5, y: y)
        positions[.kneeRight] = CGPoint(x: x + 5, y: y)

        y += 12 * dir
        positions[.footLeft] = CGPoint(x: x - 7, y: y)
        positions[.footRight] = CGPoint(x: x + 7, y: y)

        // Skull top (above the anchor for drawing the skull circle)
        positions[.skullTop] = anchor

        return SkeletonPose(jointPositions: positions)
    }
}

// MARK: - Renderer

enum SkeletonRenderer {

    // MARK: - Menu Bar Icon (18x18 template)

    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let cx: CGFloat = 9
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.2)
            ctx.setLineCap(.round)

            // Skull (top)
            let skullRect = CGRect(x: cx - 3.5, y: 1, width: 7, height: 7)
            ctx.fillEllipse(in: skullRect)
            // Eye holes
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 2, y: 3, width: 1.5, height: 1.5))
            ctx.fillEllipse(in: CGRect(x: cx + 0.5, y: 3, width: 1.5, height: 1.5))
            ctx.setFillColor(NSColor.black.cgColor)

            // Spine
            ctx.move(to: CGPoint(x: cx, y: 8))
            ctx.addLine(to: CGPoint(x: cx, y: 14))
            ctx.strokePath()

            // Ribs
            ctx.setLineWidth(1.0)
            // Top rib pair
            ctx.move(to: CGPoint(x: cx - 4, y: 9.5))
            ctx.addQuadCurve(to: CGPoint(x: cx, y: 9), control: CGPoint(x: cx - 2, y: 8.5))
            ctx.move(to: CGPoint(x: cx + 4, y: 9.5))
            ctx.addQuadCurve(to: CGPoint(x: cx, y: 9), control: CGPoint(x: cx + 2, y: 8.5))
            // Bottom rib pair
            ctx.move(to: CGPoint(x: cx - 3, y: 11.5))
            ctx.addQuadCurve(to: CGPoint(x: cx, y: 11), control: CGPoint(x: cx - 1.5, y: 10.5))
            ctx.move(to: CGPoint(x: cx + 3, y: 11.5))
            ctx.addQuadCurve(to: CGPoint(x: cx, y: 11), control: CGPoint(x: cx + 1.5, y: 10.5))
            ctx.strokePath()

            // Arms
            ctx.setLineWidth(1.2)
            ctx.move(to: CGPoint(x: cx, y: 9))
            ctx.addLine(to: CGPoint(x: cx - 5, y: 12))
            ctx.move(to: CGPoint(x: cx, y: 9))
            ctx.addLine(to: CGPoint(x: cx + 5, y: 12))
            ctx.strokePath()

            // Legs
            ctx.move(to: CGPoint(x: cx, y: 14))
            ctx.addLine(to: CGPoint(x: cx - 4, y: 17.5))
            ctx.move(to: CGPoint(x: cx, y: 14))
            ctx.addLine(to: CGPoint(x: cx + 4, y: 17.5))
            ctx.strokePath()

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Draw Skeleton from Pose

    static func drawSkeleton(in ctx: CGContext, pose: SkeletonPose, boneColor: CGColor? = nil) {
        let color = boneColor ?? NSColor(calibratedWhite: 0.92, alpha: 1.0).cgColor
        let jointColor = NSColor(calibratedWhite: 0.80, alpha: 1.0).cgColor

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Draw skull
        let skullBase = pose.position(of: .skullBase)
        let top = pose.position(of: .top)
        let skullCenter = CGPoint(
            x: (top.x + skullBase.x) / 2,
            y: (top.y + skullBase.y) / 2
        )
        let skullRadius: CGFloat = 7

        // Skull fill
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(
            x: skullCenter.x - skullRadius,
            y: skullCenter.y - skullRadius,
            width: skullRadius * 2,
            height: skullRadius * 2
        ))

        // Skull outline
        ctx.setStrokeColor(jointColor)
        ctx.setLineWidth(1.0)
        ctx.strokeEllipse(in: CGRect(
            x: skullCenter.x - skullRadius,
            y: skullCenter.y - skullRadius,
            width: skullRadius * 2,
            height: skullRadius * 2
        ))

        // Eye sockets
        let eyeY = skullCenter.y - 1
        ctx.setFillColor(NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: skullCenter.x - 4, y: eyeY - 1.5, width: 3, height: 3))
        ctx.fillEllipse(in: CGRect(x: skullCenter.x + 1, y: eyeY - 1.5, width: 3, height: 3))

        // Nose hole
        let noseY = skullCenter.y + 2
        ctx.move(to: CGPoint(x: skullCenter.x - 1, y: noseY))
        ctx.addLine(to: CGPoint(x: skullCenter.x, y: noseY + 2))
        ctx.addLine(to: CGPoint(x: skullCenter.x + 1, y: noseY))
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor)
        ctx.setLineWidth(0.8)
        ctx.strokePath()

        // Jaw / teeth
        let jawY = skullCenter.y + skullRadius - 2
        ctx.setStrokeColor(jointColor)
        ctx.setLineWidth(0.6)
        for i in 0..<5 {
            let tx = skullCenter.x - 3 + CGFloat(i) * 1.5
            ctx.move(to: CGPoint(x: tx, y: jawY))
            ctx.addLine(to: CGPoint(x: tx, y: jawY + 2))
        }
        ctx.strokePath()

        // Draw bones (spine, ribs, arms, legs)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(2.5)

        // Spine segments
        drawBoneLine(ctx, from: pose.position(of: .skullBase), to: pose.position(of: .shoulder))
        drawBoneLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .midSpine))
        drawBoneLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .hip))

        // Ribs (thinner, curved-ish)
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(color)
        drawBoneLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .ribLeftEnd1))
        drawBoneLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .ribRightEnd1))
        drawBoneLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .ribLeftEnd2))
        drawBoneLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .ribRightEnd2))
        drawBoneLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .ribLeftEnd3))
        drawBoneLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .ribRightEnd3))

        // Arms
        ctx.setLineWidth(2.0)
        drawBoneLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .elbowLeft))
        drawBoneLine(ctx, from: pose.position(of: .elbowLeft), to: pose.position(of: .handLeft))
        drawBoneLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .elbowRight))
        drawBoneLine(ctx, from: pose.position(of: .elbowRight), to: pose.position(of: .handRight))

        // Legs
        ctx.setLineWidth(2.5)
        drawBoneLine(ctx, from: pose.position(of: .hip), to: pose.position(of: .kneeLeft))
        drawBoneLine(ctx, from: pose.position(of: .kneeLeft), to: pose.position(of: .footLeft))
        drawBoneLine(ctx, from: pose.position(of: .hip), to: pose.position(of: .kneeRight))
        drawBoneLine(ctx, from: pose.position(of: .kneeRight), to: pose.position(of: .footRight))

        // Joint dots
        ctx.setFillColor(jointColor)
        let jointDotRadius: CGFloat = 2.0
        let majorJoints: [JointID] = [
            .skullBase, .shoulder, .midSpine, .hip,
            .elbowLeft, .elbowRight, .kneeLeft, .kneeRight
        ]
        for joint in majorJoints {
            let p = pose.position(of: joint)
            ctx.fillEllipse(in: CGRect(
                x: p.x - jointDotRadius,
                y: p.y - jointDotRadius,
                width: jointDotRadius * 2,
                height: jointDotRadius * 2
            ))
        }

        // Hand/foot dots (smaller)
        let extremities: [JointID] = [.handLeft, .handRight, .footLeft, .footRight]
        let smallRadius: CGFloat = 1.5
        for joint in extremities {
            let p = pose.position(of: joint)
            ctx.fillEllipse(in: CGRect(
                x: p.x - smallRadius,
                y: p.y - smallRadius,
                width: smallRadius * 2,
                height: smallRadius * 2
            ))
        }
    }

    private static func drawBoneLine(_ ctx: CGContext, from: CGPoint, to: CGPoint) {
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
    }

    // MARK: - Individual Bone Sprites (for scatter animation)

    static func drawBoneSprite(boneID: BoneID, in ctx: CGContext, size: CGSize) {
        let color = NSColor(calibratedWhite: 0.92, alpha: 1.0).cgColor
        ctx.setFillColor(color)
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.80, alpha: 1.0).cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)

        switch boneID {
        case .skull:
            // Draw mini skull
            let r = min(size.width, size.height) / 2 - 1
            let cx = size.width / 2
            let cy = size.height / 2
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            // Eyes
            ctx.setFillColor(NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - r * 0.5, y: cy - r * 0.3, width: r * 0.35, height: r * 0.35))
            ctx.fillEllipse(in: CGRect(x: cx + r * 0.15, y: cy - r * 0.3, width: r * 0.35, height: r * 0.35))

        case .upperLegLeft, .upperLegRight, .upperArmLeft, .upperArmRight:
            // Classic cartoon bone shape: shaft with bulbous ends
            drawCartoonBone(in: ctx, size: size)

        case .lowerLegLeft, .lowerLegRight, .lowerArmLeft, .lowerArmRight:
            drawCartoonBone(in: ctx, size: size)

        case .ribLeft1, .ribLeft2, .ribLeft3, .ribRight1, .ribRight2, .ribRight3:
            // Curved rib
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 2, y: size.height / 2))
            path.addQuadCurve(
                to: CGPoint(x: size.width - 2, y: size.height / 2),
                control: CGPoint(x: size.width / 2, y: 2)
            )
            ctx.addPath(path)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(2.0)
            ctx.strokePath()

        default:
            // Vertebra / pelvis: small rounded rect
            let r = CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)
            let path = CGPath(roundedRect: r, cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    /// Classic cartoon bone: shaft with two knobs on each end
    private static func drawCartoonBone(in ctx: CGContext, size: CGSize) {
        let color = NSColor(calibratedWhite: 0.92, alpha: 1.0).cgColor
        let outlineColor = NSColor(calibratedWhite: 0.75, alpha: 1.0).cgColor

        let knobR: CGFloat = size.height * 0.3
        let shaftY = size.height / 2
        let shaftH = size.height * 0.25
        let margin: CGFloat = knobR

        // Shaft
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: margin, y: shaftY - shaftH / 2, width: size.width - margin * 2, height: shaftH))

        // End knobs
        ctx.fillEllipse(in: CGRect(x: 1, y: shaftY - knobR - 1, width: knobR * 2, height: knobR * 2))
        ctx.fillEllipse(in: CGRect(x: 1, y: shaftY + 1 - knobR, width: knobR * 2, height: knobR * 2))
        ctx.fillEllipse(in: CGRect(x: size.width - knobR * 2 - 1, y: shaftY - knobR - 1, width: knobR * 2, height: knobR * 2))
        ctx.fillEllipse(in: CGRect(x: size.width - knobR * 2 - 1, y: shaftY + 1 - knobR, width: knobR * 2, height: knobR * 2))

        // Outline
        ctx.setStrokeColor(outlineColor)
        ctx.setLineWidth(0.5)
        ctx.strokeEllipse(in: CGRect(x: 1, y: shaftY - knobR - 1, width: knobR * 2, height: knobR * 2))
        ctx.strokeEllipse(in: CGRect(x: 1, y: shaftY + 1 - knobR, width: knobR * 2, height: knobR * 2))
        ctx.strokeEllipse(in: CGRect(x: size.width - knobR * 2 - 1, y: shaftY - knobR - 1, width: knobR * 2, height: knobR * 2))
        ctx.strokeEllipse(in: CGRect(x: size.width - knobR * 2 - 1, y: shaftY + 1 - knobR, width: knobR * 2, height: knobR * 2))
    }

    /// Bone sprite size for scatter animation
    static func spriteSize(for boneID: BoneID) -> CGSize {
        switch boneID {
        case .skull: return CGSize(width: 16, height: 16)
        case .upperLegLeft, .upperLegRight: return CGSize(width: 20, height: 8)
        case .lowerLegLeft, .lowerLegRight: return CGSize(width: 16, height: 7)
        case .upperArmLeft, .upperArmRight: return CGSize(width: 16, height: 7)
        case .lowerArmLeft, .lowerArmRight: return CGSize(width: 14, height: 6)
        case .ribLeft1, .ribRight1: return CGSize(width: 14, height: 6)
        case .ribLeft2, .ribRight2: return CGSize(width: 12, height: 5)
        case .ribLeft3, .ribRight3: return CGSize(width: 10, height: 5)
        case .spine1, .spine2, .spine3: return CGSize(width: 6, height: 6)
        case .pelvis: return CGSize(width: 10, height: 6)
        }
    }

    /// Create an NSImage for a single bone sprite
    static func boneImage(for boneID: BoneID) -> NSImage {
        let size = spriteSize(for: boneID)
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            SkeletonRenderer.drawBoneSprite(boneID: boneID, in: ctx, size: size)
            return true
        }
    }
}
