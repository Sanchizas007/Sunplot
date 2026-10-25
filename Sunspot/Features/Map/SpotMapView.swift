import SwiftUI
import SpotKit
import MapKit
import SolarCore

/// The spot on the ground, with the sun's arrival and departure drawn across it.
struct SpotMapView: View {
    @Environment(SpotStore.self) private var store

    @State private var camera: MapCameraPosition = .automatic
    @State private var hasFramedSpot = false

    var body: some View {
        NavigationStack {
            Group {
                if let spot = store.spot {
                    map(for: spot)
                } else {
                    FirstSpotMap()
                }
            }
            // No navigation bar: the tab already says "Map", and every point of screen
            // given back to the map is a building whose shadow you can see.
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private func map(for spot: Spot) -> some View {
        let rays = SunRays(spot: spot, at: store.viewedDate)

        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(rays.all) { ray in
                        MapPolyline(coordinates: [ray.from.clCoordinate, ray.to.clCoordinate])
                            .stroke(colour(for: ray.kind), style: strokeStyle(for: ray.kind))
                    }
                    Annotation("The spot", coordinate: spot.coordinate.clCoordinate) {
                        SpotPin()
                    }
                    .annotationTitles(.hidden)
                }
                // Flat, looking straight down. A tilted three-dimensional view is prettier
                // and useless here: you cannot read a bearing off a plane you are seeing
                // edge-on, and bearings are the whole point of this screen. Labels stay on
                // so people can find their own street.
                .mapStyle(.hybrid(elevation: .flat))
                // Long press, not tap. A stray tap while panning would move a spot someone
                // had carefully placed, and they would have no idea what they had done.
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard case let .second(_, drag?) = value,
                                  let picked = proxy.convert(drag.location, from: .local)
                            else { return }
                            store.move(to: GeoCoordinate(
                                latitude: picked.latitude, longitude: picked.longitude
                            ))
                        }
                )
            }
            // Top, not bottom: Apple's Maps attribution sits in the bottom-left corner and
            // covering it breaks the terms the map data comes under.
            .overlay(alignment: .topLeading) { Legend(rays: rays) }

            TimeScrubber(spot: spot)
        }
        .onAppear { frame(spot) }
    }

    private func frame(_ spot: Spot) {
        guard !hasFramedSpot else { return }
        hasFramedSpot = true
        camera = .region(MKCoordinateRegion(
            center: spot.coordinate.clCoordinate,
            // Wide enough to take in the buildings that cast the shade, tight enough to
            // pick out a single flower bed.
            latitudinalMeters: 400,
            longitudinalMeters: 400
        ))
    }

    private func colour(for kind: SunRays.Ray.Kind) -> Color {
        switch kind {
        case .sunrise: .orange
        case .sunset: .pink
        case .now: .yellow
        }
    }

    private func strokeStyle(for kind: SunRays.Ray.Kind) -> StrokeStyle {
        switch kind {
        case .now: StrokeStyle(lineWidth: 5, lineCap: .round)
        default: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6])
        }
    }
}

/// The map for somebody who has no spot yet — which is everybody for the first few seconds,
/// and, for anybody who says no to the question about location, for good.
///
/// Every message the app shows such a person ends "pick a spot on the map instead", and for a
/// long time the Map tab answered that with a notice and no map: nothing to press and hold on,
/// so no way to place a first spot and no way out. A person who declines to share where they
/// are is exactly who needs this screen to work.
private struct FirstSpotMap: View {
    @Environment(SpotStore.self) private var store

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        MapReader { proxy in
            Map(position: $camera)
                .mapStyle(.hybrid(elevation: .flat))
                // The same long press as on the map that has a spot: a tap while panning
                // must not put a pin somewhere nobody meant.
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard case let .second(_, drag?) = value,
                                  let picked = proxy.convert(drag.location, from: .local)
                            else { return }
                            store.move(to: GeoCoordinate(
                                latitude: picked.latitude, longitude: picked.longitude
                            ))
                        }
                )
        }
        .overlay(alignment: .top) {
            Label("Press and hold the map to place your spot.", systemImage: "hand.tap")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
    }
}

private struct SpotPin: View {
    var body: some View {
        // Has to stay readable with three bright rays converging underneath it.
        Circle()
            .fill(.white)
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(.black, lineWidth: 4))
            .overlay(Circle().fill(.black).frame(width: 6, height: 6))
            .shadow(color: .black.opacity(0.6), radius: 4)
            .accessibilityLabel("The spot")
    }
}

/// Names the lines. Sun Seeker's own reviewers ask what the lines mean and give it one star
/// when nobody tells them, so this is not decoration.
private struct Legend: View {
    let rays: SunRays

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sunrise = rays.sunrise {
                entry(.orange, "Sun arrives from \(Format.compass(sunrise.azimuth))")
            }
            if let sunset = rays.sunset {
                entry(.pink, "Leaves towards \(Format.compass(sunset.azimuth))")
            }
            if let now = rays.now {
                entry(.yellow, "Now: \(Format.compass(now.azimuth))")
            } else {
                entry(.gray, "The sun is down")
            }
            Text("Press and hold to move the spot")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .font(.caption)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func entry(_ colour: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 7) {
            Capsule().fill(colour).frame(width: 16, height: 4)
            Text(text)
        }
    }
}

/// Drags the whole scene through the day.
private struct TimeScrubber: View {
    @Environment(SpotStore.self) private var store
    let spot: Spot

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 8) {
            HStack {
                Text(Format.time(store.viewedDate, in: spot.timeZone))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Spacer()
                if !store.followsClock {
                    Button("Now") { store.returnToNow() }
                        .font(.subheadline)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(store.viewedMinuteOfDay) },
                    set: { store.scrub(toMinuteOfDay: Int($0)) }
                ),
                in: 0...1439,
                step: 5
            )
            .tint(.yellow)

            HStack {
                Text("Midnight").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Noon").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Midnight").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

extension GeoCoordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
