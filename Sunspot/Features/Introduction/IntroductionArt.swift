import SwiftUI
import SpotKit

/// The picture above each page of the tour.
///
/// Drawn rather than photographed or screenshotted, for three reasons. It is the same handful
/// of shapes the app itself draws — the sun's arc, the traced skyline, the three rays on the
/// map — so what somebody learns here is what they will recognise on the screens. It costs a
/// few kilobytes instead of a few megabytes of images times fourteen languages: there is no
/// text baked into any of it. And it can move, which is the only honest way to show a line
/// being traced.
struct IntroArt: View {
    let page: IntroPage
    let isActive: Bool
    let topInset: CGFloat

    var body: some View {
        switch page {
        case .question: DawnArt(isActive: isActive, topInset: topInset)
        case .path:     PathArt(isActive: isActive, topInset: topInset)
        case .skyline:  TraceArt(isActive: isActive, topInset: topInset)
        case .map:      RaysArt(isActive: isActive, topInset: topInset)
        case .place:    PlaceArt(isActive: isActive, topInset: topInset)
        }
    }
}

// MARK: - Time

/// Runs a picture's clock only while its page is in front, and only for as long as the
/// picture is still moving.
///
/// The clock counts seconds since the page arrived and every drawing below is a function of
/// it, so a page replays from the start each time it is swiped back to. A picture that has
/// finished stops asking to be redrawn: a tour somebody leaves open on a page should not keep
/// the screen busy sixty times a second to show the same frame. With Reduce Motion on there is
/// no clock at all — the picture is shown finished and standing still.
private struct ArtClock<Content: View>: View {
    let isActive: Bool
    /// When the picture has finished moving, or nil if it never does.
    let settlesAfter: Double?
    let content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var began = Date()
    @State private var hasPlayed = false

    init(isActive: Bool, settlesAfter: Double?, @ViewBuilder content: @escaping (Double) -> Content) {
        self.isActive = isActive
        self.settlesAfter = settlesAfter
        self.content = content
    }

    /// A picture that has not been reached yet waits at its first frame, and one that has been
    /// left stays at its last, so it does not rewind while it slides away.
    private var restingTime: Double {
        hasPlayed ? (settlesAfter ?? 60) : 0
    }

    var body: some View {
        Group {
            if reduceMotion {
                content(60)
            } else if isActive {
                TimelineView(FrameSchedule(start: began, duration: settlesAfter)) { context in
                    content(max(0, context.date.timeIntervalSince(began)))
                }
                .id(began)
            } else {
                content(restingTime)
            }
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            hasPlayed = true
            began = Date()
        }
    }
}

/// Sixty frames a second from the moment a page arrives, until the picture has finished.
private struct FrameSchedule: TimelineSchedule {
    let start: Date
    let duration: Double?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Frames {
        Frames(cursor: max(startDate, start), end: duration.map { start.addingTimeInterval($0) })
    }

    struct Frames: Sequence, IteratorProtocol {
        var cursor: Date
        let end: Date?

        mutating func next() -> Date? {
            if let end, cursor > end { return nil }
            defer { cursor = cursor.addingTimeInterval(1.0 / 60.0) }
            return cursor
        }
    }
}

private enum Ease {
    static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    /// How far through the stretch between two moments the clock is, from 0 to 1.
    static func span(_ t: Double, _ from: Double, _ to: Double) -> Double {
        clamp((t - from) / (to - from))
    }

    static func inOut(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * (3 - 2 * x)
    }

    static func out(_ value: Double) -> Double {
        1 - pow(1 - clamp(value), 3)
    }

    /// Falls, hits, and settles — for the pin.
    static func bounce(_ value: Double) -> Double {
        let x = clamp(value)
        let n = 7.5625, d = 2.75
        if x < 1 / d { return n * x * x }
        if x < 2 / d { let y = x - 1.5 / d; return n * y * y + 0.75 }
        if x < 2.5 / d { let y = x - 2.25 / d; return n * y * y + 0.9375 }
        let y = x - 2.625 / d
        return n * y * y + 0.984375
    }
}

/// The same shapes every run: a picture that changes between launches is one nobody can
/// check, and a garden that is different each time cannot be tuned by eye.
private struct Seeded: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Shapes

/// Where a point is, from fractions of the picture: across from the left, up from the bottom.
private func pt(_ x: Double, _ h: Double, _ size: CGSize) -> CGPoint {
    CGPoint(x: x * Double(size.width), y: (1 - h) * Double(size.height))
}

/// The sun's path across a picture, a single curve rising from the horizon and coming back
/// down to it.
private struct Arc {
    let startHeight: Double
    let peakHeight: Double
    let margin: Double

    private var controlHeight: Double { 2 * peakHeight - startHeight }

    func point(_ u: Double, in size: CGSize) -> CGPoint {
        let v = 1 - u
        let x = v * v * margin + 2 * v * u * 0.5 + u * u * (1 - margin)
        let h = v * v * startHeight + 2 * v * u * controlHeight + u * u * startHeight
        return pt(x, h, size)
    }

    func path(in size: CGSize) -> Path {
        var path = Path()
        path.move(to: pt(margin, startHeight, size))
        path.addQuadCurve(to: pt(1 - margin, startHeight, size), control: pt(0.5, controlHeight, size))
        return path
    }
}

/// A line of roofs and treetops, as a height at every position across.
///
/// One description serves two jobs: it is filled in as the silhouette things stand behind, and
/// its upper edge is what the finger traces on the third page.
private struct Treeline {
    struct House {
        let x: Double, width: Double, wall: Double, roof: Double
        var chimney = false
    }
    struct Crown {
        let x: Double, halfWidth: Double, centre: Double, halfHeight: Double
    }

    let floor: Double
    var houses: [House] = []
    var crowns: [Crown] = []

    func height(at x: Double) -> Double {
        var top = floor
        for house in houses where x >= house.x && x <= house.x + house.width {
            let middle = house.x + house.width / 2
            let ridge = max(0, 1 - abs(x - middle) / (house.width / 2))
            top = max(top, house.wall + house.roof * ridge)
            if house.chimney {
                let stack = middle + house.width * 0.18
                if abs(x - stack) < 0.011 {
                    let roofHere = house.wall + house.roof * max(0, 1 - abs(stack - middle) / (house.width / 2))
                    top = max(top, roofHere + 0.05)
                }
            }
        }
        for crown in crowns {
            let d = (x - crown.x) / crown.halfWidth
            if abs(d) <= 1 {
                top = max(top, crown.centre + crown.halfHeight * (1 - d * d).squareRoot())
            }
        }
        return top
    }

    /// The upper edge, left to right, in the same fractions `pt` takes.
    func contour(steps: Int = 240) -> [CGPoint] {
        (0...steps).map { index in
            let x = Double(index) / Double(steps)
            return CGPoint(x: x, y: height(at: x))
        }
    }

    func silhouette(in size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height + 4))
        for point in contour() { path.addLine(to: pt(point.x, point.y, size)) }
        path.addLine(to: CGPoint(x: size.width, y: size.height + 4))
        path.closeSubpath()
        return path
    }

    /// A quiet street: two houses and a few trees, low enough that a sun can rise from behind them.
    static let street = Treeline(
        floor: 0.07,
        houses: [
            House(x: -0.03, width: 0.34, wall: 0.17, roof: 0.12, chimney: true),
            House(x: 0.60, width: 0.30, wall: 0.15, roof: 0.10),
            House(x: 0.88, width: 0.20, wall: 0.13, roof: 0.08)
        ],
        crowns: [
            Crown(x: 0.41, halfWidth: 0.09, centre: 0.13, halfHeight: 0.13),
            Crown(x: 0.51, halfWidth: 0.06, centre: 0.10, halfHeight: 0.09),
            Crown(x: 0.98, halfWidth: 0.10, centre: 0.16, halfHeight: 0.14)
        ]
    )

    /// Rolling treetops far off, so the arc has a horizon to meet.
    static let distant = Treeline(
        floor: 0.08,
        houses: [House(x: 0.82, width: 0.12, wall: 0.10, roof: 0.05)],
        crowns: [0.08, 0.24, 0.40, 0.57, 0.72, 0.93].enumerated().map { index, x in
            Crown(x: x, halfWidth: 0.10, centre: 0.07, halfHeight: index.isMultiple(of: 2) ? 0.06 : 0.04)
        }
    )

    /// What actually stands in the way in the third picture: a tall house on the left, a row of
    /// trees on the right, and a gap between them where the sun gets through.
    static let garden = Treeline(
        floor: 0.17,
        houses: [House(x: -0.03, width: 0.38, wall: 0.30, roof: 0.16, chimney: true)],
        crowns: [
            Crown(x: 0.62, halfWidth: 0.07, centre: 0.12, halfHeight: 0.12),
            Crown(x: 0.74, halfWidth: 0.13, centre: 0.20, halfHeight: 0.22),
            Crown(x: 0.88, halfWidth: 0.15, centre: 0.22, halfHeight: 0.24)
        ]
    )
}

private enum Sky {
    static let dawn = Gradient(stops: [
        .init(color: Color(red: 0.07, green: 0.08, blue: 0.26), location: 0),
        .init(color: Color(red: 0.36, green: 0.17, blue: 0.46), location: 0.50),
        .init(color: Color(red: 0.93, green: 0.45, blue: 0.28), location: 0.84),
        .init(color: Color(red: 1.00, green: 0.72, blue: 0.34), location: 1)
    ])
    static let day = Gradient(stops: [
        .init(color: Color(red: 0.05, green: 0.20, blue: 0.50), location: 0),
        .init(color: Color(red: 0.20, green: 0.50, blue: 0.86), location: 0.55),
        .init(color: Color(red: 0.66, green: 0.82, blue: 0.96), location: 1)
    ])
    static let golden = Gradient(stops: [
        .init(color: Color(red: 0.15, green: 0.10, blue: 0.34), location: 0),
        .init(color: Color(red: 0.60, green: 0.25, blue: 0.42), location: 0.32),
        .init(color: Color(red: 0.96, green: 0.52, blue: 0.27), location: 0.56),
        .init(color: Color(red: 1.00, green: 0.78, blue: 0.40), location: 1)
    ])
}

private func fillSky(_ context: inout GraphicsContext, _ gradient: Gradient, size: CGSize) {
    context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
    )
}

/// The sun as the Sky screen draws it: a yellow disc inside a thin white ring, with a glow the
/// app's own screen does not have room for.
private func drawSun(
    _ context: inout GraphicsContext,
    at point: CGPoint,
    radius: CGFloat,
    glow: CGFloat,
    alpha: Double = 1
) {
    context.drawLayer { layer in
        layer.opacity = alpha
        layer.fill(
            Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.5).opacity(0.6), .clear]),
                center: point, startRadius: 0, endRadius: glow
            )
        )
        let disc = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        layer.fill(Path(ellipseIn: disc), with: .color(.yellow))
        layer.stroke(
            Path(ellipseIn: disc.insetBy(dx: -radius * 0.38, dy: -radius * 0.38)),
            with: .color(.white.opacity(0.8)),
            lineWidth: 3
        )
    }
}

/// Four corner marks, like a camera finder: the quickest way to say "this is what the phone sees".
private func drawBrackets(_ context: inout GraphicsContext, size: CGSize, topInset: CGFloat) {
    let left: CGFloat = 24
    let right = size.width - 24
    // Below the Skip button, which sits in the top corner, and near the bottom of the picture,
    // where the finder closes around everything the page draws.
    let top = topInset + 62
    let bottom = size.height - 26
    let leg: CGFloat = 26
    let radius: CGFloat = 9

    var path = Path()
    for (x, dx) in [(left, CGFloat(1)), (right, CGFloat(-1))] {
        for (y, dy) in [(top, CGFloat(1)), (bottom, CGFloat(-1))] {
            path.move(to: CGPoint(x: x, y: y + dy * leg))
            path.addLine(to: CGPoint(x: x, y: y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: x + dx * radius, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * leg, y: y))
        }
    }
    context.stroke(
        path,
        with: .color(.white.opacity(0.7)),
        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
    )
}

/// The small white label the pictures hang on things.
private struct Chip: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(red: 0.10, green: 0.12, blue: 0.20))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.94)))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

// MARK: - 1. The question

/// Dawn, and the hours counting up as the sun climbs out from behind the roofs.
private struct DawnArt: View {
    let isActive: Bool
    let topInset: CGFloat

    /// As high as the picture allows without the sun coming to rest on the figure above it: on
    /// a short screen the figure takes a larger share of the picture, and the path has to come down.
    private func arc(in size: CGSize) -> Arc {
        let room = 1 - Double(topInset + 150) / Double(size.height)
        return Arc(startHeight: 0.14, peakHeight: max(0.32, min(0.58, room)), margin: 0.06)
    }

    private static let reach = 0.58          // how far along its path the sun is when it stops
    private static let minutes = 462         // 7h 42m, the figure the store listing shows

    var body: some View {
        ArtClock(isActive: isActive, settlesAfter: 5.4) { t in
            let progress = Ease.inOut(Ease.span(t, 0.5, 4.8))
            ZStack(alignment: .top) {
                Canvas { context, size in
                    draw(&context, size: size, t: t, progress: progress)
                }
                counter(progress: progress)
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double, progress: Double) {
        let u = Self.reach * progress
        let arc = arc(in: size)
        fillSky(&context, Sky.dawn, size: size)
        context.drawLayer { layer in
            layer.opacity = Ease.out(progress * 1.15)
            fillSky(&layer, Sky.day, size: size)
        }

        // Stars, until there is too much light for them.
        var rng = Seeded(seed: 5)
        for index in 0..<26 {
            let x = Double.random(in: 0.04...0.96, using: &rng)
            let h = Double.random(in: 0.50...0.97, using: &rng)
            let radius = Double.random(in: 0.8...1.9, using: &rng)
            let twinkle = 0.55 + 0.45 * sin(t * 2.2 + Double(index))
            let alpha = max(0, 1 - progress * 1.8) * twinkle
            guard alpha > 0.01 else { continue }
            let centre = pt(x, h, size)
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(alpha))
            )
        }

        // The whole day's path, only hinted at, so the sun has somewhere visible to go.
        context.stroke(
            arc.path(in: size),
            with: .color(.white.opacity(0.32)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 9])
        )

        // The glow along the horizon the sun has just left.
        let horizon = pt(0.5, 0.0, size)
        context.drawLayer { layer in
            layer.opacity = 0.7 * (1 - progress)
            layer.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 1, green: 0.62, blue: 0.25).opacity(0.85), .clear]),
                    center: horizon, startRadius: 0, endRadius: size.width * 0.8
                )
            )
        }

        drawSun(&context, at: arc.point(u, in: size), radius: 0.05 * size.width, glow: (0.20 + 0.14 * progress) * size.width)
        context.fill(Treeline.street.silhouette(in: size), with: .color(IntroStyle.ground))
    }

    private func counter(progress: Double) -> some View {
        let minutes = max(1, Int((Double(Self.minutes) * progress).rounded()))
        return VStack(spacing: 2) {
            Text("Sun today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(Format.duration(minutes: minutes))
                .font(.system(size: topInset > 50 ? 58 : 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
        .padding(.top, topInset + 22)
    }
}

// MARK: - 2. The sun's path

/// The yellow arc drawing itself across a camera's view, and the disc arriving to sit on it.
private struct PathArt: View {
    let isActive: Bool
    let topInset: CGFloat

    /// Kept inside the finder's top marks, whatever the height of the picture.
    private func arc(in size: CGSize) -> Arc {
        let room = 1 - Double(topInset + 62 + 46) / Double(size.height)
        return Arc(startHeight: 0.12, peakHeight: max(0.32, min(0.64, room)), margin: 0.05)
    }

    private static let stop = 0.60

    var body: some View {
        ArtClock(isActive: isActive, settlesAfter: 4.6) { t in
            let drawn = Ease.inOut(Ease.span(t, 0.4, 2.3))
            let glide = Ease.out(Ease.span(t, 2.0, 3.6))
            let discAlpha = Ease.span(t, 2.0, 2.4)
            let chips = Ease.out(Ease.span(t, 3.4, 4.0))

            GeometryReader { proxy in
                let size = proxy.size
                let arc = arc(in: size)
                let disc = arc.point(Self.stop * glide, in: size)
                let anchor = arc.point(0.2, in: size)

                ZStack {
                    Canvas { context, size in
                        fillSky(&context, Sky.day, size: size)

                        let path = arc.path(in: size).trimmedPath(from: 0, to: drawn)
                        context.drawLayer { layer in
                            layer.addFilter(.blur(radius: 7))
                            layer.stroke(path, with: .color(.yellow.opacity(0.5)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        }
                        context.stroke(path, with: .color(.yellow.opacity(0.95)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

                        drawSun(&context, at: disc, radius: 0.05 * size.width, glow: 0.2 * size.width, alpha: discAlpha)
                        context.fill(Treeline.distant.silhouette(in: size), with: .color(IntroStyle.ground))
                        drawBrackets(&context, size: size, topInset: topInset)
                    }

                    Chip(text: "Today")
                        .position(x: anchor.x - 44, y: anchor.y - 6)
                        .opacity(chips)
                        .scaleEffect(0.9 + 0.1 * chips)
                    Chip(text: "Now")
                        .position(x: disc.x, y: disc.y - 0.1 * size.width - 18)
                        .opacity(chips)
                        .scaleEffect(0.9 + 0.1 * chips)
                }
            }
        }
    }
}

// MARK: - 3. The skyline

/// A finger running along the roofs and trees, leaving the cyan line behind it, and the part
/// of the sun's path that falls behind that line going dim.
private struct TraceArt: View {
    let isActive: Bool
    let topInset: CGFloat

    private func arc(in size: CGSize) -> Arc {
        let room = 1 - Double(topInset + 62 + 46) / Double(size.height)
        return Arc(startHeight: 0.10, peakHeight: max(0.40, min(0.66, room)), margin: 0.04)
    }

    private static let skyline = Treeline.garden

    /// The upper edge, wobbled the way a finger wobbles: a trace that follows the roof exactly
    /// would look like a diagram, and the point is that anybody can do it.
    private static let traced: [CGPoint] = skyline.contour(steps: 200)
        .filter { $0.x >= 0.06 && $0.x <= 0.94 }
        .map { point in
            let wobble = 0.005 * sin(point.x * 41) + 0.003 * sin(point.x * 83 + 1.3)
            return CGPoint(x: point.x, y: point.y + 0.012 + wobble)
        }

    var body: some View {
        ArtClock(isActive: isActive, settlesAfter: 5.2) { t in
            let progress = Ease.inOut(Ease.span(t, 0.9, 4.0))
            let done = Ease.inOut(Ease.span(t, 4.0, 4.8))

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Canvas { context, size in
                        draw(&context, size: size, progress: progress, done: done)
                    }

                    ZStack {
                        capsule("Trace the skyline").opacity(1 - done)
                        capsule("Save skyline").opacity(done)
                    }
                    .position(x: size.width / 2, y: size.height - 46)
                }
            }
        }
    }

    private func capsule(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.cyan))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, progress: Double, done: Double) {
        fillSky(&context, Sky.day, size: size)

        let silhouette = Self.skyline.silhouette(in: size)
        context.fill(silhouette, with: .color(IntroStyle.ground))

        let shape = arc(in: size)
        let arc = shape.path(in: size)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            layer.stroke(arc, with: .color(.yellow.opacity(0.45)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }
        context.stroke(arc, with: .color(.yellow.opacity(0.95)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

        // Behind the skyline the sun cannot be seen, so the path goes dim there — once the
        // skyline is known, which is the whole point of drawing it.
        context.drawLayer { layer in
            layer.clip(to: silhouette)
            // Wide enough to take the glow with it, then a thin dotted ghost of the path where
            // the sun would have been.
            layer.stroke(
                arc,
                with: .color(IntroStyle.ground.opacity(0.94 * done)),
                style: StrokeStyle(lineWidth: 22, lineCap: .round)
            )
            layer.stroke(
                arc,
                with: .color(.yellow.opacity(0.38 * done)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 9])
            )
        }

        drawSun(&context, at: shape.point(0.54, in: size), radius: 0.05 * size.width, glow: 0.2 * size.width)

        var line = Path()
        for (index, point) in Self.traced.enumerated() {
            let p = pt(point.x, point.y, size)
            index == 0 ? line.move(to: p) : line.addLine(to: p)
        }
        let drawn = line.trimmedPath(from: 0, to: progress)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.stroke(drawn, with: .color(.cyan.opacity(0.6)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
        }
        context.stroke(drawn, with: .color(.cyan), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        drawBrackets(&context, size: size, topInset: topInset)

        if progress > 0.001, progress < 0.999 {
            let index = min(Self.traced.count - 1, Int(progress * Double(Self.traced.count - 1)))
            let tip = pt(Self.traced[index].x, Self.traced[index].y, size)
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - 21, y: tip.y - 21, width: 42, height: 42)),
                with: .color(.white.opacity(0.22))
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: tip.x - 21, y: tip.y - 21, width: 42, height: 42)),
                with: .color(.white.opacity(0.85)),
                lineWidth: 2
            )
            context.fill(
                Path(ellipseIn: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)),
                with: .color(.white)
            )
        }
    }
}

// MARK: - 4. The map

/// The three lines of the map, exactly as the map draws them, and the yellow one swinging
/// across the day with the legend and the clock following it.
private struct RaysArt: View {
    let isActive: Bool
    let topInset: CGFloat

    private static let arrives = 104.0
    private static let leaves = 240.0
    private static let resting = 191.0       // where the sun stands at half past one

    var body: some View {
        ArtClock(isActive: isActive, settlesAfter: 5.2) { t in
            let sweep = Ease.inOut(Ease.span(t, 2.0, 4.8))
            let now = Self.arrives + (Self.resting - Self.arrives) * sweep
            let minutes = 372 + (810 - 372) * sweep

            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        drawMap(&context, size: size)
                        drawRays(&context, size: size, t: t, now: now, showsSlider: size.height >= 400)
                    }

                    legend(now: now)
                        .padding(.top, topInset + 12)
                        .padding(.leading, 18)

                    // A short screen has no room for the clock as well as the legend and the
                    // lines, and the lines are what the page is about.
                    if size.height >= 400 {
                        slider(minutes: minutes)
                            .frame(width: size.width - 36)
                            .position(x: size.width / 2, y: size.height * 0.84)
                    }
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.86),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
    }

    private func legend(now: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            entry(.orange, Text("Sun arrives from \(Format.compass(Self.arrives))"))
            entry(.pink, Text("Leaves towards \(Format.compass(Self.leaves))"))
            entry(.yellow, Text("Now: \(Format.compass(now))"))
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.45)))
    }

    private func entry(_ colour: Color, _ text: Text) -> some View {
        HStack(spacing: 7) {
            Capsule().fill(colour).frame(width: 16, height: 4)
            text.monospacedDigit()
        }
    }

    private func slider(minutes: Double) -> some View {
        // Set the hour, do not add minutes to midnight: on the day the clocks change that is an
        // hour out, and a slider that says half past twelve for half past one is not teaching
        // anybody to trust the numbers on the map.
        let moment = Calendar.current.date(
            bySettingHour: Int(minutes) / 60, minute: Int(minutes) % 60, second: 0, of: .now
        ) ?? .now
        let fraction = minutes / 1440

        return VStack(spacing: 10) {
            HStack {
                Text(Format.time(moment, in: .current))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Spacer()
            }
            GeometryReader { track in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28)).frame(height: 6)
                    Capsule().fill(.yellow).frame(width: track.size.width * fraction, height: 6)
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                        .offset(x: track.size.width * fraction - 13)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 26)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.5)))
    }

    private func drawRays(_ context: inout GraphicsContext, size: CGSize, t: Double, now: Double, showsSlider: Bool) {
        // Below the legend, whatever language it is written in and however short the screen,
        // and with the lines stopping short of the clock when there is one.
        let legendBottom = topInset + 12 + 96
        let centre = CGPoint(x: size.width * 0.5, y: max(size.height * 0.34, legendBottom + 34))
        let floor = showsSlider ? size.height * 0.84 - 56 : size.height * 0.90
        let length = max(60, min(size.height * 0.34, floor - centre.y - 10))

        func end(_ azimuth: Double) -> CGPoint {
            let radians = azimuth * .pi / 180
            return CGPoint(x: centre.x + length * sin(radians), y: centre.y - length * cos(radians))
        }
        func ray(_ azimuth: Double, _ grow: Double) -> Path {
            var path = Path()
            path.move(to: centre)
            let tip = end(azimuth)
            path.addLine(to: CGPoint(x: centre.x + (tip.x - centre.x) * grow, y: centre.y + (tip.y - centre.y) * grow))
            return path
        }

        let dashed = StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [8, 6])
        context.stroke(ray(Self.arrives, Ease.out(Ease.span(t, 0.5, 1.2))), with: .color(.orange), style: dashed)
        context.stroke(ray(Self.leaves, Ease.out(Ease.span(t, 1.0, 1.7))), with: .color(.pink), style: dashed)
        context.stroke(
            ray(now, Ease.out(Ease.span(t, 1.5, 2.2))),
            with: .color(.yellow),
            style: StrokeStyle(lineWidth: 5.5, lineCap: .round)
        )

        // The pin, as the map draws it: white, ringed in black, with a black dot.
        let pin = CGRect(x: centre.x - 10, y: centre.y - 10, width: 20, height: 20)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.6), radius: 4))
            layer.fill(Path(ellipseIn: pin), with: .color(.white))
        }
        context.stroke(Path(ellipseIn: pin.insetBy(dx: 2, dy: 2)), with: .color(.black), lineWidth: 4)
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)), with: .color(.black))
    }

    /// Gardens and roofs from above, which is all a satellite view is once it is small enough
    /// to be a picture: lawns, a few rooftops, clumps of trees and two roads.
    private func drawMap(_ context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.07, green: 0.16, blue: 0.11)))

        var rng = Seeded(seed: 41)
        let cell: CGFloat = 46
        for row in 0..<(Int(size.height / cell) + 2) {
            for column in 0..<(Int(size.width / cell) + 2) {
                let jitterX = CGFloat.random(in: -4...4, using: &rng)
                let jitterY = CGFloat.random(in: -4...4, using: &rng)
                let kind = Double.random(in: 0..<1, using: &rng)
                let shade = Double.random(in: 0...0.06, using: &rng)
                let plot = CGRect(
                    x: CGFloat(column) * cell - 14 + jitterX,
                    y: CGFloat(row) * cell - 14 + jitterY,
                    width: cell - 7, height: cell - 7
                )
                let lawn = Color(red: 0.11 + shade, green: 0.27 + shade, blue: 0.13 + shade * 0.5)
                context.fill(Path(roundedRect: plot, cornerRadius: 5), with: .color(lawn))

                if kind < 0.30 {
                    let roof = plot.insetBy(dx: 9, dy: 10)
                    context.fill(Path(roundedRect: roof.offsetBy(dx: 2, dy: 2), cornerRadius: 3), with: .color(.black.opacity(0.35)))
                    context.fill(
                        Path(roundedRect: roof, cornerRadius: 3),
                        with: .color(Color(red: 0.60 + shade, green: 0.55 + shade, blue: 0.50 + shade))
                    )
                } else if kind < 0.58 {
                    for _ in 0..<4 {
                        let radius = CGFloat.random(in: 5...9, using: &rng)
                        let x = plot.minX + CGFloat.random(in: 8...(plot.width - 8), using: &rng)
                        let y = plot.minY + CGFloat.random(in: 8...(plot.height - 8), using: &rng)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(Color(red: 0.04, green: 0.19 + shade, blue: 0.08))
                        )
                    }
                }
            }
        }

        for (from, to, c1, c2) in [
            (CGPoint(x: -10, y: size.height * 0.56), CGPoint(x: size.width + 10, y: size.height * 0.42),
             CGPoint(x: size.width * 0.3, y: size.height * 0.46), CGPoint(x: size.width * 0.7, y: size.height * 0.62)),
            (CGPoint(x: size.width * 0.24, y: -10), CGPoint(x: size.width * 0.38, y: size.height + 10),
             CGPoint(x: size.width * 0.10, y: size.height * 0.35), CGPoint(x: size.width * 0.50, y: size.height * 0.7))
        ] {
            var road = Path()
            road.move(to: from)
            road.addCurve(to: to, control1: c1, control2: c2)
            context.stroke(road, with: .color(Color(red: 0.04, green: 0.09, blue: 0.07)), lineWidth: 16)
            context.stroke(road, with: .color(Color(red: 0.50, green: 0.50, blue: 0.45)), lineWidth: 9)
        }

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(0.4)]),
                center: CGPoint(x: size.width / 2, y: size.height * 0.4),
                startRadius: size.width * 0.3, endRadius: size.width * 0.9
            )
        )
    }
}

// MARK: - 5. Where is the spot?

/// A pin dropping onto the ground at golden hour, and rings spreading out from where it lands.
private struct PlaceArt: View {
    let isActive: Bool
    let topInset: CGFloat

    var body: some View {
        ArtClock(isActive: isActive, settlesAfter: nil) { t in
            Canvas { context, size in
                draw(&context, size: size, t: t)
            }
        }
    }

    private func hills(in size: CGSize, base: CGFloat, amplitude: CGFloat, phase: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height + 4))
        for step in 0...80 {
            let x = Double(step) / 80
            let y = Double(base) - Double(amplitude) * (0.55 + 0.45 * sin(x * 7 + phase)) * (0.7 + 0.3 * sin(x * 17 + phase * 2))
            path.addLine(to: CGPoint(x: x * Double(size.width), y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height + 4))
        path.closeSubpath()
        return path
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let horizon = size.height * 0.56
        fillSky(&context, Sky.golden, size: size)

        drawSun(
            &context,
            at: CGPoint(x: size.width * 0.5, y: horizon - size.height * 0.05),
            radius: 0.085 * size.width, glow: 0.6 * size.width
        )
        context.fill(
            hills(in: size, base: horizon + 6, amplitude: size.height * 0.07, phase: 0.6),
            with: .color(Color(red: 0.36, green: 0.17, blue: 0.36))
        )

        let plane = Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon + 4))
        context.fill(
            plane,
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.25, green: 0.12, blue: 0.24), IntroStyle.ground]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        // Where the pin comes to rest.
        let base = CGPoint(x: size.width * 0.5, y: horizon + (size.height - horizon) * 0.60)
        let fall = Ease.bounce(Ease.span(t, 0.4, 1.5))

        // Rings, starting once it has landed and going on while the page is up.
        for index in 0..<3 {
            let phase = ((t - 1.4) / 2.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            guard t > 1.4, phase >= 0 else { continue }
            let rx = size.width * 0.46 * phase
            let ring = CGRect(x: base.x - rx, y: base.y - rx * 0.3, width: rx * 2, height: rx * 0.6)
            context.stroke(
                Path(ellipseIn: ring),
                with: .color(IntroStyle.amber.opacity(0.75 * (1 - phase))),
                lineWidth: 2.5
            )
        }

        // The pin's shadow grows as it comes down.
        let shadowWidth = 26 + 16 * fall
        context.fill(
            Path(ellipseIn: CGRect(x: base.x - shadowWidth / 2, y: base.y - 5, width: shadowWidth, height: 10)),
            with: .color(.black.opacity(0.35 * fall))
        )

        let lift = (1 - fall) * -230
        let head = CGPoint(x: base.x, y: base.y - 58 + lift)
        let radius: CGFloat = 25
        let tip = CGPoint(x: base.x, y: base.y + lift)

        var tail = Path()
        tail.move(to: CGPoint(x: head.x - radius * 0.86, y: head.y + radius * 0.5))
        tail.addQuadCurve(to: tip, control: CGPoint(x: head.x - radius * 0.35, y: head.y + radius * 1.5))
        tail.addQuadCurve(to: CGPoint(x: head.x + radius * 0.86, y: head.y + radius * 0.5), control: CGPoint(x: head.x + radius * 0.35, y: head.y + radius * 1.5))
        tail.closeSubpath()

        let fill = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [IntroStyle.amber, IntroStyle.orange]),
            startPoint: CGPoint(x: head.x, y: head.y - radius), endPoint: tip
        )
        context.drawLayer { layer in
            layer.opacity = Ease.span(t, 0.4, 0.7)
            layer.addFilter(.shadow(color: IntroStyle.orange.opacity(0.5), radius: 10))
            layer.fill(tail, with: fill)
            layer.fill(Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)), with: fill)
        }
        context.fill(
            Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)),
            with: .color(IntroStyle.ground.opacity(0.85 * Ease.span(t, 0.4, 0.7)))
        )
    }
}
