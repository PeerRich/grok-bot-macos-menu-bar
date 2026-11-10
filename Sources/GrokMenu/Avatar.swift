import AppKit

/// Draws bot avatars: the custom photo when one is cached, otherwise a flat rendition of the
/// bot's shape + colour mark with its two eyes.
enum Avatar {
    private static var cache: [String: NSImage] = [:]

    static func image(for bot: Bot, size: CGFloat) -> NSImage {
        let key = "\(bot.id)|\(bot.shape)|\(bot.color)|\(bot.photoKey ?? "")|\(size)"
        if let cached = cache[key] { return cached }
        let image = photo(for: bot, size: size) ?? mark(shape: resolvedShape(bot), color: resolvedColor(bot), size: size)
        cache[key] = image
        return image
    }

    /// Monochrome mark for the menu bar when nothing is running.
    static func templateIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            NSColor.black.setFill()
            bodyPath("blob", in: rect).fill()
            cutEyes("blob", in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Photo

    private static func photo(for bot: Bot, size: CGFloat) -> NSImage? {
        guard let key = bot.photoKey,
              let source = NSImage(contentsOf: GrokPaths.avatars.appendingPathComponent(key)) else { return nil }
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            let from = source.size
            let side = min(from.width, from.height)
            let crop = NSRect(x: (from.width - side) / 2, y: (from.height - side) / 2, width: side, height: side)
            source.draw(in: rect, from: crop, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    // MARK: - Mark

    private static let shapes = ["blob", "pebble", "squircle", "tablet", "wedge", "hex", "cloud", "teardrop"]
    private static let gradients: [String: (String, String)] = [
        "black": ("#5A5A5A", "#1F1F1F"), "brown": ("#A27952", "#855C36"), "red": ("#FF3E51", "#E02135"),
        "orange": ("#FF8A3C", "#FF6700"), "yellow": ("#FFB84D", "#FF9800"), "green": ("#1CCF82", "#009957"),
        "cyan": ("#58D3C5", "#00A592"), "blue": ("#459FFE", "#0E74E0"), "violet": ("#B792FE", "#804EE0"),
        "magenta": ("#FF77BE", "#E02A88"), "gray": ("#A6A6A6", "#696969"),
    ]

    private static func stableHash(_ text: String) -> Int {
        Int(text.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 } % 100_000)
    }

    private static func resolvedShape(_ bot: Bot) -> String {
        bot.shape.isEmpty ? shapes[stableHash(bot.id) % shapes.count] : bot.shape
    }

    private static func resolvedColor(_ bot: Bot) -> String {
        if gradients[bot.color] != nil { return bot.color }
        let names = gradients.keys.filter { $0 != "black" && $0 != "gray" }.sorted()
        return names[stableHash(bot.id + "c") % names.count]
    }

    private static func mark(shape: String, color: String, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let (from, to) = gradients[color] ?? gradients["violet"]!
            NSGradient(starting: NSColor(hex: from), ending: NSColor(hex: to))?
                .draw(in: bodyPath(shape, in: rect), angle: 45)
            cutEyes(shape, in: rect)
            return true
        }
    }

    // MARK: - Bloub geometry
    //
    // Body silhouettes and eye placement are ported from bloub by Jérémy Perret (MIT),
    // https://github.com/jeremy-prt/bloub: `src/bot/skins.ts`, `shape.ts` and `face.ts`.
    // A silhouette is a radial profile r(theta) sampled at 64 angles, theta clockwise with y
    // pointing down, drawn as a closed Catmull-Rom curve. Eyes are capsules painted on a sphere
    // and projected flat, cut out of the body as holes.

    private static let samples = 64
    private static let angles: [CGFloat] = (0..<samples).map { CGFloat($0) / CGFloat(samples) * 2 * .pi }
    private static var profiles: [String: [CGFloat]] = [:]

    /// Grok Bot shape names mapped onto bloub's eight customiser shapes.
    private static func profile(_ shape: String) -> [CGFloat] {
        if let cached = profiles[shape] { return cached }
        let radii: [CGFloat]
        switch shape {
        case "pebble", "bean", "egg":
            radii = normalize(angles.map { 1 + 0.075 * cos(2 * $0 + 0.5) + 0.035 * cos(3 * $0 + 2.1) }, 1.02)
        case "squircle", "square", "house", "shield":
            radii = normalize(angles.map { pow(pow(abs(cos($0)), 4.2) + pow(abs(sin($0)), 4.2), -1 / 4.2) }, 1.15)
        case "tablet", "capsule", "cylinder":
            radii = polygonProfile(hull(-0.42, 0, 0.62, 0.42, 0, 0.62))
        case "wedge", "dome", "arch":
            radii = regularPolygon(sides: 3, radius: 1.12, corner: 0.34, rotation: -.pi / 2)
        case "hex", "gem", "crystal":
            radii = regularPolygon(sides: 6, radius: 1.04, corner: 0.26, rotation: 0)
        case "cloud":
            radii = normalize(unionProfile([(-0.44, 0.2, 0.54), (0.46, 0.2, 0.5), (0.02, 0.3, 0.6),
                                            (-0.24, -0.3, 0.48), (0.3, -0.24, 0.44)]), 1.02)
        case "teardrop", "leaf":
            radii = normalize(polygonProfile(hull(0, 0.28, 0.66, 0, -0.96, 0.05)), 1.04)
        // Shapes bloub does not have; same pipeline, hand-made profiles.
        case "star": radii = normalize(angles.map { 0.86 + 0.14 * cos(6 * $0 + .pi / 2) }, 1.06)
        case "flower": radii = normalize(angles.map { 0.9 + 0.1 * cos(8 * $0) }, 1.04)
        case "clover": radii = normalize(angles.map { 0.82 + 0.18 * cos(4 * $0 + .pi) }, 1.08)
        case "sparkle": radii = normalize(angles.map { 0.66 + 0.34 * pow(abs(cos(2 * $0)), 2.2) }, 1.1)
        case "heart":
            radii = normalize(unionProfile([(-0.36, -0.22, 0.52), (0.36, -0.22, 0.52)]).enumerated().map { index, lobe in
                max(lobe, polygonRay([NSPoint(x: -0.8, y: 0.02), NSPoint(x: 0.8, y: 0.02), NSPoint(x: 0, y: 0.95)], index))
            }, 1.06)
        default:
            radii = Array(repeating: 1, count: samples)
        }
        profiles[shape] = radii
        return radii
    }

    private static func normalize(_ radii: [CGFloat], _ peakTarget: CGFloat) -> [CGFloat] {
        guard let peak = radii.max(), peak > 0 else { return radii }
        return radii.map { $0 * peakTarget / peak }
    }

    /// Distance from the origin to the polygon outline along sample direction `index`.
    private static func polygonRay(_ polygon: [NSPoint], _ index: Int) -> CGFloat {
        let dx = cos(angles[index]), dy = sin(angles[index])
        var best: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let ex = b.x - a.x, ey = b.y - a.y
            let den = dx * ey - dy * ex
            if abs(den) < 1e-9 { continue }
            let t = (a.x * ey - a.y * ex) / den
            let u = (a.x * dy - a.y * dx) / den
            if t > best, u >= 0, u <= 1 { best = t }
        }
        return best
    }

    private static func polygonProfile(_ polygon: [NSPoint]) -> [CGFloat] {
        (0..<samples).map { polygonRay(polygon, $0) }
    }

    /// Convex hull of two circles, as a polygon.
    private static func hull(_ x1: CGFloat, _ y1: CGFloat, _ r1: CGFloat,
                             _ x2: CGFloat, _ y2: CGFloat, _ r2: CGFloat) -> [NSPoint] {
        let dx = x2 - x1, dy = y2 - y1
        let distance = max(hypot(dx, dy), 1e-6)
        let base = atan2(dy, dx)
        let spread = acos(max(-1, min(1, (r1 - r2) / distance)))
        var points: [NSPoint] = []
        for i in 0...48 {
            let a = base + spread + (2 * .pi - 2 * spread) * CGFloat(i) / 48
            points.append(NSPoint(x: x1 + cos(a) * r1, y: y1 + sin(a) * r1))
        }
        for i in 0...48 {
            let a = base - spread + 2 * spread * CGFloat(i) / 48
            points.append(NSPoint(x: x2 + cos(a) * r2, y: y2 + sin(a) * r2))
        }
        return points
    }

    private static func unionProfile(_ circles: [(CGFloat, CGFloat, CGFloat)]) -> [CGFloat] {
        angles.map { angle in
            let dx = cos(angle), dy = sin(angle)
            var best: CGFloat = 0
            for (x, y, r) in circles {
                let b = dx * x + dy * y
                let disc = b * b - (x * x + y * y - r * r)
                if disc >= 0 { best = max(best, b + sqrt(disc)) }
            }
            return best
        }
    }

    private static func regularPolygon(sides: Int, radius: CGFloat, corner: CGFloat, rotation: CGFloat) -> [CGFloat] {
        let vertices = (0..<sides).map { index -> NSPoint in
            let a = rotation + CGFloat(index) / CGFloat(sides) * 2 * .pi
            return NSPoint(x: cos(a) * (radius - corner), y: sin(a) * (radius - corner))
        }
        var outline: [NSPoint] = []
        func normal(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(hypot(dx, dy), 1e-6)
            return atan2(-dx / length, dy / length)
        }
        for i in 0..<sides {
            let current = vertices[i]
            let start = normal(vertices[(i - 1 + sides) % sides], current)
            var delta = normal(current, vertices[(i + 1) % sides]) - start
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            for step in 0...10 {
                let a = start + delta * CGFloat(step) / 10
                outline.append(NSPoint(x: current.x + cos(a) * corner, y: current.y + sin(a) * corner))
            }
        }
        return polygonProfile(outline)
    }

    /// Ball radius in points: the largest profile (1.15) must fit the image.
    private static func ballRadius(_ rect: NSRect) -> CGFloat { rect.width / 2 / 1.17 }

    private static func bodyPath(_ shape: String, in rect: NSRect) -> NSBezierPath {
        let radii = profile(shape), scale = ballRadius(rect)
        let points = (0..<samples).map {
            NSPoint(x: rect.midX + radii[$0] * cos(angles[$0]) * scale, y: rect.midY + radii[$0] * sin(angles[$0]) * scale)
        }
        let path = NSBezierPath()
        path.move(to: points[0])
        let tension: CGFloat = 1 / 6
        for i in 0..<samples {
            let p0 = points[(i - 1 + samples) % samples], p1 = points[i]
            let p2 = points[(i + 1) % samples], p3 = points[(i + 2) % samples]
            path.curve(to: p2,
                       controlPoint1: NSPoint(x: p1.x + (p2.x - p0.x) * tension, y: p1.y + (p2.y - p0.y) * tension),
                       controlPoint2: NSPoint(x: p2.x - (p3.x - p1.x) * tension, y: p2.y - (p3.y - p1.y) * tension))
        }
        path.close()
        return path
    }

    /// Two eye capsules on a sphere, head turned to bloub's rest gaze (softened so the eyes
    /// stay inside every silhouette at menu sizes).
    private static func cutEyes(_ shape: String, in rect: NSRect) {
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setFill()
        eyes(shape, in: rect).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    /// Narrow-topped silhouettes need the face lower down to keep both eyes on the body.
    private static let eyeDrop: [String: CGFloat] = ["teardrop": 0.34, "leaf": 0.34, "wedge": 0.2, "dome": 0.2, "arch": 0.2, "heart": 0.1]

    private static func eyes(_ shape: String, in rect: NSRect) -> NSBezierPath {
        typealias Vec = (CGFloat, CGFloat, CGFloat)
        func spin(_ u: Vec, _ v: Vec, _ degrees: CGFloat) -> (Vec, Vec) {
            let c = cos(degrees * .pi / 180), s = sin(degrees * .pi / 180)
            return ((u.0 * c + v.0 * s, u.1 * c + v.1 * s, u.2 * c + v.2 * s),
                    (v.0 * c - u.0 * s, v.1 * c - u.1 * s, v.2 * c - u.2 * s))
        }
        let yaw: CGFloat = 28.49 * 0.45, pitch: CGFloat = 28.62 * 0.45, roll: CGFloat = -13 * 0.6
        let split: CGFloat = 15.46, eyeWidth: CGFloat = 0.186, eyeHeight: CGFloat = 0.412
        var forward: Vec = (0, 0, 1), right: Vec = (1, 0, 0), down: Vec = (0, 1, 0)
        (forward, right) = spin(forward, right, yaw)
        (down, forward) = spin(down, forward, pitch)
        (right, down) = spin(right, down, roll)

        let scale = ballRadius(rect)
        let path = NSBezierPath()
        for side in [CGFloat(-1), 1] {
            let (eyeForward, eyeRight) = spin(forward, right, split * side)
            let capsule = NSBezierPath(
                roundedRect: NSRect(x: -eyeWidth / 2, y: -eyeHeight / 2, width: eyeWidth, height: eyeHeight),
                xRadius: eyeWidth / 2, yRadius: eyeWidth / 2)
            let transform = AffineTransform(
                m11: eyeRight.0 * scale, m12: eyeRight.1 * scale, m21: down.0 * scale, m22: down.1 * scale,
                tX: rect.midX + eyeForward.0 * scale, tY: rect.midY + (eyeForward.1 + (eyeDrop[shape] ?? 0)) * scale)
            capsule.transform(using: transform)
            path.append(capsule)
        }
        return path
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
