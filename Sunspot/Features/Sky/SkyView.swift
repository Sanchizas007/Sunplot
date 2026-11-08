import SwiftUI
import UIKit
import SpotKit
import SolarCore

/// Point the phone at the sky and see where the sun goes — then trace what stands in its way.
struct SkyView: View {
    @Environment(SpotStore.self) private var store

    @State private var motion = MotionTracker()
    @State private var camera = CameraFeed()
    @State private var draft: [HorizonProfile.Sample] = []
    @State private var isTracing = false
    @State private var arc: SunArc?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Only the live view bleeds to the edges. The controls must not, or they
                // end up underneath the tab bar where nobody can reach them.
                background.ignoresSafeArea()
                if let spot = store.spot, let projection = projection(in: geometry.size),
                   let arc = currentArc(for: spot) {
                    Overlay(
                        spot: spot,
                        moment: store.viewedDate,
                        arc: arc,
                        projection: projection,
                        size: geometry.size,
                        draft: draft,
                        trusted: motion.trust.isUsable
                    )
                    .gesture(traceGesture(projection: projection, size: geometry.size))
                    .ignoresSafeArea()
                }
                controls(canTrace: projection(in: geometry.size) != nil)
            }
        }
        .onAppear {
            camera.start()
            motion.start()
        }
        .onDisappear {
            camera.stop()
            motion.stop()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var background: some View {
        switch camera.state {
        case .running:
            #if targetEnvironment(simulator)
            // No lens here, so the view is a picture rather than a film: the one Tools/shots.py
            // leaves in the temp folder, or, without it, a sky drawn at dusk.
            if let picture = StandInPicture.image {
                Color.clear.overlay { Image(uiImage: picture).resizable().scaledToFill() }.clipped()
            } else {
                StandInSky()
            }
            #else
            CameraPreview(session: camera.session)
            #endif
        case .denied:
            Message(
                title: "Camera is off",
                detail: "Sunplot uses the camera so you can trace the roofs and trees around a spot. Turn it on in Settings."
            )
        case .unavailable(let reason):
            Message(title: "No live view", detail: reason)
        case .idle:
            Color.black
        }
    }

    @ViewBuilder
    private func controls(canTrace: Bool) -> some View {
        VStack {
            if let advice = motion.trust.advice {
                CompassWarning(advice: advice, severe: !motion.trust.isUsable)
            }
            Spacer()
            // Offering to trace a skyline with no live view and no compass would be a button
            // that cannot work, which is worse than no button.
            if canTrace {
                TraceControls(
                    isTracing: $isTracing,
                    draftArc: HorizonProfile(samples: draft).measuredArc,
                    targetArc: store.spot?.sunArcWidth(in: Calendar.current.component(.year, from: .now)),
                    onSave: {
                        store.setHorizon(HorizonProfile(samples: draft))
                        isTracing = false
                    },
                    onClear: { draft = [] }
                )
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Wiring

    /// Rebuilds the arc only when the day it describes is no longer the day being viewed.
    private func currentArc(for spot: Spot) -> SunArc? {
        if let arc, arc.covers(store.viewedDate, in: spot.timeZone) { return arc }
        let fresh = SunArc(spot: spot, containing: store.viewedDate)
        Task { @MainActor in arc = fresh }
        return fresh
    }

    private func projection(in size: CGSize) -> SkyProjection? {
        guard let rotation = motion.rotation,
              case let .running(fieldOfView) = camera.state,
              size.width > 0, size.height > 0
        else { return nil }

        let shown = SkyProjection.displayedFieldOfView(
            cameraFieldOfView: fieldOfView,
            viewAspectRatio: size.width / size.height
        )
        return SkyProjection(
            rotation: rotation,
            horizontalFieldOfView: shown.horizontal,
            verticalFieldOfView: shown.vertical
        )
    }

    private func traceGesture(projection: SkyProjection, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isTracing else { return }
                let normalised = ScreenPoint(
                    x: (value.location.x / size.width) * 2 - 1,
                    y: (value.location.y / size.height) * 2 - 1
                )
                let sky = projection.direction(at: normalised)
                // Below the horizon is not a roofline; it is the ground.
                guard sky.elevation >= 0 else { return }
                draft.append(.init(azimuth: sky.azimuth, elevation: sky.elevation))
            }
    }
}

// MARK: - Overlay

/// The sun's arc, the skyline being drawn, and nothing else.
private struct Overlay: View {
    let spot: Spot
    let moment: Date
    let arc: SunArc
    let projection: SkyProjection
    let size: CGSize
    let draft: [HorizonProfile.Sample]
    let trusted: Bool

    var body: some View {
        Canvas { context, _ in
            drawStandInSkyline(in: &context)
            drawArc(in: &context)
            drawSkyline(in: &context)
            drawSun(in: &context)
        }
        .allowsHitTesting(true)
        .opacity(trusted ? 1 : 0.45)
    }

    private func screen(_ azimuth: Double, _ elevation: Double) -> CGPoint? {
        guard let point = projection.project(azimuth: azimuth, elevation: elevation) else {
            return nil
        }
        let screenPoint = CGPoint(
            x: (point.x + 1) / 2 * size.width,
            y: (point.y + 1) / 2 * size.height
        )
        // The projection already refuses anything wild, but nothing that reaches a drawing
        // surface should be taken on trust.
        guard screenPoint.x.isFinite, screenPoint.y.isFinite else { return nil }
        return screenPoint
    }

    /// The whole day's path. The positions were worked out once; only the projection of
    /// them changes as the phone moves.
    private func drawArc(in context: inout GraphicsContext) {
        var path = Path()
        var started = false
        for step in arc.steps {
            guard let point = screen(step.azimuth, step.elevation) else {
                started = false
                continue
            }
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }
        context.stroke(path, with: .color(.yellow.opacity(0.9)), lineWidth: 4)
    }

    private func drawSun(in context: inout GraphicsContext) {
        let sun = spot.sunPosition(at: moment)
        guard let point = screen(sun.azimuth, sun.elevation) else { return }
        let disc = CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32)
        context.fill(Circle().path(in: disc), with: .color(.yellow))
        context.stroke(Circle().path(in: disc.insetBy(dx: -6, dy: -6)),
                       with: .color(.white.opacity(0.8)), lineWidth: 3)
    }

    /// Fills in what the camera would have been looking at, where there is no camera.
    ///
    /// Drawn from the traced profile itself, through the same projection as everything else,
    /// so the silhouette and the cyan line agree the way a roofline and a tracing of it do on
    /// a phone. Nothing here is invented: it is the same numbers the hours are counted from,
    /// filled in rather than plotted. On a device this never runs — there is a lens.
    private func drawStandInSkyline(in context: inout GraphicsContext) {
        #if targetEnvironment(simulator)
        // A picture already shows the trees and roofs the traced line follows.
        guard StandInPicture.image == nil else { return }
        let horizon = spot.effectiveHorizon
        guard !horizon.samples.isEmpty else { return }

        // Half a degree at a time: fine enough that the ridge reads as an edge rather than a
        // chain of segments, coarse enough to cost nothing.
        var runs: [[CGPoint]] = []
        var run: [CGPoint] = []
        for azimuth in stride(from: 0.0, to: 360.0, by: 0.5) {
            guard let point = screen(azimuth, horizon.obstructionElevation(atAzimuth: azimuth)) else {
                if run.count > 1 { runs.append(run) }
                run = []
                continue
            }
            run.append(point)
        }
        if run.count > 1 { runs.append(run) }

        // Filled well past the bottom of the frame rather than to it. The canvas is laid out
        // inside the safe area while the sky behind it is not, so a fill that stops at the
        // frame's own edge leaves a pale band of sky under the ground, right where the tab bar
        // sits — which reads as a drawing error rather than a horizon.
        let below = size.height * 1.4
        for run in runs {
            guard let first = run.first, let last = run.last else { continue }
            var path = Path()
            path.move(to: CGPoint(x: first.x, y: below))
            for point in run { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: below))
            path.closeSubpath()
            context.fill(path, with: .color(Color(red: 0.06, green: 0.09, blue: 0.19)))
        }
        #endif
    }

    /// What the person has traced so far, plus whatever was already saved.
    private func drawSkyline(in context: inout GraphicsContext) {
        let samples = draft.isEmpty ? spot.effectiveHorizon.samples : draft
        guard samples.count > 1 else { return }

        var path = Path()
        var started = false
        for sample in samples.sorted(by: { $0.azimuth < $1.azimuth }) {
            guard let point = screen(sample.azimuth, sample.elevation) else {
                started = false
                continue
            }
            if started { path.addLine(to: point) } else { path.move(to: point); started = true }
        }
        context.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }
}

// MARK: - Controls

/// Says plainly when the compass cannot be trusted, instead of drawing a confident lie.
private struct CompassWarning: View {
    let advice: String
    let severe: Bool

    var body: some View {
        Label(advice, systemImage: severe ? "exclamationmark.triangle.fill" : "location.circle")
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(12)
            .background(
                (severe ? Color.red : Color.orange).opacity(0.85),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .padding(.horizontal, 16)
    }
}

private struct TraceControls: View {
    @Binding var isTracing: Bool
    /// How much of the horizon the current drawing covers, in degrees.
    let draftArc: Double
    /// How much of it the sun actually crosses here, if that is known.
    let targetArc: Double?
    let onSave: () -> Void
    let onClear: () -> Void

    private var isEnough: Bool { draftArc >= Spot.minimumUsefulArc }

    var body: some View {
        VStack(spacing: 12) {
            if isTracing {
                VStack(spacing: 6) {
                    Text("Sweep along the tops of the roofs and trees")
                        .font(.subheadline.weight(.medium))
                    // Without this the screen accepted a single tap as a finished skyline.
                    Text(progress)
                        .font(.footnote)
                        .foregroundStyle(isEnough ? .green : .orange)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 12) {
                if isTracing {
                    Button("Cancel") { isTracing = false; onClear() }
                        .buttonStyle(.bordered)
                    Button("Save skyline", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(!isEnough)
                } else {
                    Button("Trace the skyline") { isTracing = true; onClear() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .tint(.cyan)
        }
        .padding(.horizontal, 20)
    }

    private var progress: String {
        let done = Int(draftArc.rounded())
        guard isEnough else {
            return done == 0
                ? "Keep your finger down and turn on the spot"
                : "\(done)° so far — keep going"
        }
        if let targetArc {
            return "\(done)° of the \(Int(targetArc.rounded()))° the sun crosses here"
        }
        return "\(done)° traced"
    }
}

private struct Message: View {
    let title: LocalizedStringKey
    let detail: String

    var body: some View {
        ZStack {
            Color.black
            ContentUnavailableView {
                Label(title, systemImage: "camera.metering.unknown")
            } description: {
                Text(detail)
            }
            .foregroundStyle(.white)
        }
    }
}

#if targetEnvironment(simulator)
/// The picture a screenshot run stands in for the lens, if there is one: a photograph cut to the
/// screen by Tools/make-standin-sky.py, which also puts the photograph's skyline into the demo
/// garden so the traced line lands on it. Tools/shots.py copies it next to the app's other
/// temporary files before each launch.
private enum StandInPicture {
    static let image = UIImage(contentsOfFile: NSTemporaryDirectory() + "sunplot-standin-sky.jpg")
}

/// What a lens would have shown at the end of a clear day, for the runs that have no lens:
/// deep blue overhead, a violet band, and a warm glow sitting on the horizon with a few
/// streaks of cloud lit from below. Drawn in the frame's own proportions, so the glow lands
/// where the stand-in skyline's ridge is. On a device this never runs — there is a camera.
private struct StandInSky: View {
    /// Position across and down (0...1), width as a share of the frame, and how opaque.
    private let clouds: [(x: Double, y: Double, width: Double, opacity: Double, tilt: Double)] = [
        (0.28, 0.19, 0.80, 0.10, -4), (0.72, 0.27, 0.70, 0.16, 3),
        (0.40, 0.35, 0.90, 0.28, -2), (0.80, 0.42, 0.60, 0.38, 2),
        (0.20, 0.46, 0.55, 0.36, -3)
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.07, green: 0.15, blue: 0.42), location: 0),
                        .init(color: Color(red: 0.17, green: 0.27, blue: 0.62), location: 0.26),
                        .init(color: Color(red: 0.46, green: 0.42, blue: 0.76), location: 0.40),
                        .init(color: Color(red: 0.96, green: 0.58, blue: 0.55), location: 0.49),
                        .init(color: Color(red: 1.00, green: 0.75, blue: 0.36), location: 0.55),
                        .init(color: Color(red: 1.00, green: 0.82, blue: 0.48), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color(red: 1, green: 0.80, blue: 0.40).opacity(0.8), .clear],
                    center: UnitPoint(x: 0.82, y: 0.53),
                    startRadius: 0, endRadius: size.width * 0.95
                )
                ForEach(clouds.indices, id: \.self) { index in
                    let cloud = clouds[index]
                    Capsule()
                        .fill(Color(red: 1, green: 0.66, blue: 0.58).opacity(cloud.opacity))
                        .frame(width: size.width * cloud.width, height: size.height * 0.022)
                        .rotationEffect(.degrees(cloud.tilt))
                        .blur(radius: 14)
                        .position(x: size.width * cloud.x, y: size.height * cloud.y)
                }
            }
        }
    }
}
#endif
