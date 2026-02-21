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
    case top
    case skullTop
    case skullBase
    case shoulder
    case midSpine
    case hip
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
    let softness: CGFloat
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
        Bone(id: .skull, parentJoint: .top, childJoint: .skullBase, length: 16, softness: 1.0),
        Bone(id: .spine1, parentJoint: .skullBase, childJoint: .shoulder, length: 6, softness: 1.0),
        Bone(id: .spine2, parentJoint: .shoulder, childJoint: .midSpine, length: 8, softness: 1.0),
        Bone(id: .spine3, parentJoint: .midSpine, childJoint: .hip, length: 8, softness: 1.0),

        // Ribs — stiffer now
        Bone(id: .ribLeft1, parentJoint: .shoulder, childJoint: .ribLeftEnd1, length: 9, softness: 0.85),
        Bone(id: .ribLeft2, parentJoint: .midSpine, childJoint: .ribLeftEnd2, length: 7, softness: 0.85),
        Bone(id: .ribLeft3, parentJoint: .midSpine, childJoint: .ribLeftEnd3, length: 5, softness: 0.85),
        Bone(id: .ribRight1, parentJoint: .shoulder, childJoint: .ribRightEnd1, length: 9, softness: 0.85),
        Bone(id: .ribRight2, parentJoint: .midSpine, childJoint: .ribRightEnd2, length: 7, softness: 0.85),
        Bone(id: .ribRight3, parentJoint: .midSpine, childJoint: .ribRightEnd3, length: 5, softness: 0.85),

        // Arms — stiff
        Bone(id: .upperArmLeft, parentJoint: .shoulder, childJoint: .elbowLeft, length: 10, softness: 0.9),
        Bone(id: .lowerArmLeft, parentJoint: .elbowLeft, childJoint: .handLeft, length: 8, softness: 0.9),
        Bone(id: .upperArmRight, parentJoint: .shoulder, childJoint: .elbowRight, length: 10, softness: 0.9),
        Bone(id: .lowerArmRight, parentJoint: .elbowRight, childJoint: .handRight, length: 8, softness: 0.9),

        Bone(id: .pelvis, parentJoint: .hip, childJoint: .hip, length: 0, softness: 1.0),

        // Legs
        Bone(id: .upperLegLeft, parentJoint: .hip, childJoint: .kneeLeft, length: 12, softness: 0.9),
        Bone(id: .lowerLegLeft, parentJoint: .kneeLeft, childJoint: .footLeft, length: 10, softness: 0.9),
        Bone(id: .upperLegRight, parentJoint: .hip, childJoint: .kneeRight, length: 12, softness: 0.9),
        Bone(id: .lowerLegRight, parentJoint: .kneeRight, childJoint: .footRight, length: 10, softness: 0.9),
    ]

    static func restPose(hangingFrom anchor: CGPoint, flipped: Bool = false) -> SkeletonPose {
        let dir: CGFloat = flipped ? -1 : 1
        var p: [JointID: CGPoint] = [:]
        let x = anchor.x
        var y = anchor.y

        p[.top] = CGPoint(x: x, y: y)
        y += 16 * dir; p[.skullBase] = CGPoint(x: x, y: y)
        y += 6 * dir;  p[.shoulder] = CGPoint(x: x, y: y)
        p[.shoulderLeft] = p[.shoulder]!; p[.shoulderRight] = p[.shoulder]!

        p[.ribLeftEnd1] = CGPoint(x: x - 9, y: y + 2 * dir)
        p[.ribRightEnd1] = CGPoint(x: x + 9, y: y + 2 * dir)

        y += 8 * dir; p[.midSpine] = CGPoint(x: x, y: y)
        p[.ribLeftEnd2] = CGPoint(x: x - 7, y: y + 1 * dir)
        p[.ribRightEnd2] = CGPoint(x: x + 7, y: y + 1 * dir)
        p[.ribLeftEnd3] = CGPoint(x: x - 5, y: y + 3 * dir)
        p[.ribRightEnd3] = CGPoint(x: x + 5, y: y + 3 * dir)

        y += 8 * dir; p[.hip] = CGPoint(x: x, y: y)
        p[.hipLeft] = p[.hip]!; p[.hipRight] = p[.hip]!

        p[.elbowLeft] = CGPoint(x: x - 5, y: y - 6 * dir)
        p[.handLeft] = CGPoint(x: x - 7, y: y + 2 * dir)
        p[.elbowRight] = CGPoint(x: x + 5, y: y - 6 * dir)
        p[.handRight] = CGPoint(x: x + 7, y: y + 2 * dir)

        y += 12 * dir
        p[.kneeLeft] = CGPoint(x: x - 4, y: y)
        p[.kneeRight] = CGPoint(x: x + 4, y: y)
        y += 10 * dir
        p[.footLeft] = CGPoint(x: x - 6, y: y)
        p[.footRight] = CGPoint(x: x + 6, y: y)
        p[.skullTop] = anchor

        return SkeletonPose(jointPositions: p)
    }
}

// MARK: - Pixel Art Renderer

enum SkeletonRenderer {
    /// Pixel size in points for the drag avatar
    static let px: CGFloat = 3.0

    // MARK: - Menu Bar Icon (18x18 template, pixel art)

    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let p: CGFloat = 2.0  // pixel size for menu bar (smaller)
            ctx.setFillColor(NSColor.black.cgColor)

            // Skull (4x4 block, centered)
            let sx: CGFloat = 5
            fillPx(ctx, x: sx+1, y: 0, w: 2, h: 1, p: p) // top of skull
            fillPx(ctx, x: sx, y: 1, w: 4, h: 2, p: p)     // skull body
            fillPx(ctx, x: sx+1, y: 3, w: 2, h: 1, p: p)   // jaw

            // Eyes (cut out — draw skull then cut)
            ctx.setFillColor(NSColor.white.cgColor)
            fillPx(ctx, x: sx+0, y: 1, w: 1, h: 1, p: p)   // left eye
            fillPx(ctx, x: sx+3, y: 1, w: 1, h: 1, p: p)   // right eye
            ctx.setFillColor(NSColor.black.cgColor)

            // Spine
            fillPx(ctx, x: sx+1, y: 4, w: 2, h: 1, p: p)
            fillPx(ctx, x: sx+1, y: 5, w: 2, h: 1, p: p)

            // Ribs
            fillPx(ctx, x: sx-1, y: 4, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx+4, y: 4, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx-1, y: 5, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx+4, y: 5, w: 1, h: 1, p: p)

            // Arms
            fillPx(ctx, x: sx-2, y: 5, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx+5, y: 5, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx-2, y: 6, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx+5, y: 6, w: 1, h: 1, p: p)

            // Pelvis
            fillPx(ctx, x: sx, y: 6, w: 4, h: 1, p: p)

            // Legs
            fillPx(ctx, x: sx, y: 7, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx+3, y: 7, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx, y: 8, w: 1, h: 1, p: p)
            fillPx(ctx, x: sx+3, y: 8, w: 1, h: 1, p: p)

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Draw Skeleton from Pose (pixel art style)

    static func drawSkeleton(in ctx: CGContext, pose: SkeletonPose, boneColor: CGColor? = nil) {
        let white = boneColor ?? NSColor.white.cgColor
        let dark = NSColor(calibratedWhite: 0.15, alpha: 1.0).cgColor
        let p = px

        // --- Skull ---
        let skullBase = pose.position(of: .skullBase)
        let top = pose.position(of: .top)
        let skullCX = (top.x + skullBase.x) / 2
        let skullCY = (top.y + skullBase.y) / 2

        ctx.setFillColor(white)
        // Skull shape: 5px wide, 5px tall pixel block with rounded top
        fillPx(ctx, x: skullCX/p - 1, y: skullCY/p - 3, w: 3, h: 1, p: p)  // top row (3 wide)
        fillPx(ctx, x: skullCX/p - 2, y: skullCY/p - 2, w: 5, h: 3, p: p)  // main block (5 wide)
        fillPx(ctx, x: skullCX/p - 1, y: skullCY/p + 1, w: 3, h: 1, p: p)  // jaw (3 wide)

        // Eyes
        ctx.setFillColor(dark)
        fillPx(ctx, x: skullCX/p - 1.5, y: skullCY/p - 1, w: 1, h: 1, p: p)
        fillPx(ctx, x: skullCX/p + 0.5, y: skullCY/p - 1, w: 1, h: 1, p: p)

        // Smile/teeth line
        fillPx(ctx, x: skullCX/p - 1, y: skullCY/p + 1, w: 1, h: 1, p: p)
        fillPx(ctx, x: skullCX/p + 1, y: skullCY/p + 1, w: 1, h: 1, p: p)

        // --- Spine ---
        ctx.setFillColor(white)
        drawPixelLine(ctx, from: skullBase, to: pose.position(of: .shoulder), width: 2, p: p)
        drawPixelLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .midSpine), width: 2, p: p)
        drawPixelLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .hip), width: 2, p: p)

        // --- Ribs ---
        drawPixelLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .ribLeftEnd1), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .ribRightEnd1), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .ribLeftEnd2), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .ribRightEnd2), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .ribLeftEnd3), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .midSpine), to: pose.position(of: .ribRightEnd3), width: 1, p: p)

        // --- Arms ---
        drawPixelLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .elbowLeft), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .elbowLeft), to: pose.position(of: .handLeft), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .shoulder), to: pose.position(of: .elbowRight), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .elbowRight), to: pose.position(of: .handRight), width: 1, p: p)

        // --- Pelvis ---
        let hip = pose.position(of: .hip)
        fillPx(ctx, x: hip.x/p - 2, y: hip.y/p, w: 4, h: 1, p: p)

        // --- Legs ---
        drawPixelLine(ctx, from: hip, to: pose.position(of: .kneeLeft), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .kneeLeft), to: pose.position(of: .footLeft), width: 1, p: p)
        drawPixelLine(ctx, from: hip, to: pose.position(of: .kneeRight), width: 1, p: p)
        drawPixelLine(ctx, from: pose.position(of: .kneeRight), to: pose.position(of: .footRight), width: 1, p: p)

        // --- Joint dots ---
        let jointColor = NSColor(calibratedWhite: 0.75, alpha: 1.0).cgColor
        ctx.setFillColor(jointColor)
        for joint: JointID in [.shoulder, .hip, .elbowLeft, .elbowRight, .kneeLeft, .kneeRight] {
            let jp = pose.position(of: joint)
            fillPx(ctx, x: jp.x/p - 0.5, y: jp.y/p - 0.5, w: 1, h: 1, p: p)
        }
    }

    // MARK: - Pixel drawing helpers

    /// Fill a rectangle of pixel-grid cells
    private static func fillPx(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, p: CGFloat) {
        ctx.fill(CGRect(
            x: (x * p).rounded(.down),
            y: (y * p).rounded(.down),
            width: (w * p).rounded(.down),
            height: (h * p).rounded(.down)
        ))
    }

    /// Draw a pixelated line between two points (Bresenham-style, snapped to pixel grid)
    private static func drawPixelLine(_ ctx: CGContext, from: CGPoint, to: CGPoint, width: CGFloat, p: CGFloat) {
        // Convert points to pixel coordinates
        let x0 = Int((from.x / p).rounded())
        let y0 = Int((from.y / p).rounded())
        let x1 = Int((to.x / p).rounded())
        let y1 = Int((to.y / p).rounded())

        let dx = abs(x1 - x0)
        let dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy

        var cx = x0, cy = y0

        let hw = Int((width / 2).rounded(.up))

        while true {
            // Draw a pixel block of the given width
            for ox in -hw..<(hw + 1) {
                for oy in -hw..<(hw + 1) {
                    ctx.fill(CGRect(
                        x: CGFloat(cx + ox) * p,
                        y: CGFloat(cy + oy) * p,
                        width: p, height: p
                    ))
                }
            }

            if cx == x1 && cy == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; cx += sx }
            if e2 <= dx { err += dx; cy += sy }
        }
    }

    // MARK: - Bone Sprites (for scatter)

    static func spriteSize(for boneID: BoneID) -> CGSize {
        let p = px
        switch boneID {
        case .skull: return CGSize(width: 5 * p, height: 6 * p)
        case .upperLegLeft, .upperLegRight: return CGSize(width: 6 * p, height: 2 * p)
        case .lowerLegLeft, .lowerLegRight: return CGSize(width: 5 * p, height: 2 * p)
        case .upperArmLeft, .upperArmRight: return CGSize(width: 5 * p, height: 2 * p)
        case .lowerArmLeft, .lowerArmRight: return CGSize(width: 4 * p, height: 2 * p)
        case .ribLeft1, .ribRight1: return CGSize(width: 4 * p, height: 1 * p)
        case .ribLeft2, .ribRight2: return CGSize(width: 3 * p, height: 1 * p)
        case .ribLeft3, .ribRight3: return CGSize(width: 3 * p, height: 1 * p)
        case .spine1, .spine2, .spine3: return CGSize(width: 2 * p, height: 2 * p)
        case .pelvis: return CGSize(width: 4 * p, height: 1 * p)
        }
    }

    static func drawBoneSprite(boneID: BoneID, in ctx: CGContext, size: CGSize) {
        let p = px
        ctx.setFillColor(NSColor.white.cgColor)

        switch boneID {
        case .skull:
            // Mini pixel skull
            fillPx(ctx, x: 1, y: 0, w: 3, h: 1, p: p)
            fillPx(ctx, x: 0, y: 1, w: 5, h: 3, p: p)
            fillPx(ctx, x: 1, y: 4, w: 3, h: 1, p: p)
            ctx.setFillColor(NSColor.black.cgColor)
            fillPx(ctx, x: 1, y: 2, w: 1, h: 1, p: p)
            fillPx(ctx, x: 3, y: 2, w: 1, h: 1, p: p)

        case .upperLegLeft, .upperLegRight, .upperArmLeft, .upperArmRight:
            // Cartoon bone: knobs at ends
            fillPx(ctx, x: 0, y: 0, w: 1, h: 2, p: p)
            fillPx(ctx, x: 1, y: 0.5, w: size.width/p - 2, h: 1, p: p)
            let endX = size.width/p - 1
            fillPx(ctx, x: endX, y: 0, w: 1, h: 2, p: p)

        case .lowerLegLeft, .lowerLegRight, .lowerArmLeft, .lowerArmRight:
            fillPx(ctx, x: 0, y: 0, w: 1, h: 2, p: p)
            fillPx(ctx, x: 1, y: 0.5, w: size.width/p - 2, h: 1, p: p)
            fillPx(ctx, x: size.width/p - 1, y: 0, w: 1, h: 2, p: p)

        case .ribLeft1, .ribLeft2, .ribLeft3, .ribRight1, .ribRight2, .ribRight3:
            fillPx(ctx, x: 0, y: 0, w: size.width/p, h: 1, p: p)

        default:
            // Vertebra / pelvis block
            fillPx(ctx, x: 0, y: 0, w: size.width/p, h: size.height/p, p: p)
        }
    }

    static func boneImage(for boneID: BoneID) -> NSImage {
        let size = spriteSize(for: boneID)
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            SkeletonRenderer.drawBoneSprite(boneID: boneID, in: ctx, size: size)
            return true
        }
    }
}
