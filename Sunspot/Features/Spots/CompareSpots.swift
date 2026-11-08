import SwiftUI
import SolarCore
import SpotKit

/// Every spot, side by side, ranked by how much sun it gets.
///
/// The question people actually arrive with is not "how much sun does this get" but "which of
/// these is better" — the bed by the fence or the bed by the garage, this window or that one.
/// One at a time they have to hold two numbers in their head and compare them; here they do not.
struct CompareSpots: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var readings: [Reading] = []
    @State private var isWorking = true

    struct Reading: Identifiable {
        let spot: Spot
        let todayMinutes: Int
        let season: ClosedRange<Date>?
        let blackout: ClosedRange<Date>?
        var id: UUID { spot.id }
        var exposure: SunExposure { SunExposure(directMinutes: todayMinutes) }
    }

    /// The best figure on screen, so the bars have something to be relative to.
    private var best: Int { max(readings.map(\.todayMinutes).max() ?? 0, 1) }

    var body: some View {
        NavigationStack {
            Group {
                if isWorking {
                    ProgressView("Comparing")
                } else if readings.count < 2 {
                    ContentUnavailableView(
                        "Only one spot",
                        systemImage: "square.on.square.dashed",
                        description: Text("Add another spot and this will put them side by side.")
                    )
                } else {
                    List(readings) { reading in
                        Row(reading: reading, best: best, isSelected: reading.id == store.spot?.id)
                            .contentShape(.rect)
                            .onTapGesture {
                                store.select(reading.id)
                                dismiss()
                            }
                    }
                }
            }
            .navigationTitle("Which is better?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await compare() }
    }

    /// A year for each spot is a few hundred thousand sun positions apiece, so this happens
    /// off the main actor and the screen says it is working.
    private func compare() async {
        let spots = store.spots
        let year = Calendar.current.component(.year, from: .now)
        let now = Date()

        let computed = await Task.detached(priority: .userInitiated) { () -> [Reading] in
            spots.map { spot in
                let sunYear = SunYear(spot: spot, year: year)
                return Reading(
                    spot: spot,
                    todayMinutes: spot.sunDay(on: now).directMinutes,
                    season: sunYear.season(atLeast: .fullSun),
                    blackout: sunYear.blackout
                )
            }
            // Best first: the answer to "which is better" should be at the top.
            .sorted { $0.todayMinutes > $1.todayMinutes }
        }.value

        readings = computed
        isWorking = false
    }
}

private struct Row: View {
    let reading: CompareSpots.Reading
    let best: Int
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reading.spot.name)
                    .font(.headline)
                if isSelected {
                    Text("showing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.duration(minutes: reading.todayMinutes))
                    .font(.title3.weight(.semibold).monospacedDigit())
            }

            // A bar rather than two numbers to subtract: the difference is the point.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.orange)
                        .frame(width: geometry.size.width * (Double(reading.todayMinutes) / Double(best)))
                }
            }
            .frame(height: 8)

            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !reading.spot.hasMeasuredSkyline {
                Label("open sky — not traced yet", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
    }

    private var summary: String {
        // Every piece is a localised string of its own: this line was once glued together from
        // English words, and a Japanese reader got "今日は… today · full sun …".
        var parts = [String(localized: "\(reading.exposure.name) today")]
        if let season = reading.season {
            parts.append(String(localized: "full sun \(Format.dateRange(season, in: reading.spot.timeZone))"))
        } else {
            parts.append(String(localized: "never reaches full sun"))
        }
        if let blackout = reading.blackout {
            parts.append(String(localized: "nothing at all \(Format.dateRange(blackout, in: reading.spot.timeZone))"))
        }
        return parts.joined(separator: " · ")
    }
}
