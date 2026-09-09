import SwiftUI

/// What the year screen sits behind.
///
/// Shown after somebody has already traced a skyline and seen today's number, because that
/// is the moment the next question arrives on its own: fine, but what about in October?
struct Paywall: View {
    @Environment(Purchases.self) private var purchases

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 16) {
                    Feature(
                        icon: "calendar",
                        title: "The whole year at this spot",
                        detail: "When full sun starts and ends, and the weeks it gets none at all."
                    )
                    Feature(
                        icon: "mappin.and.ellipse",
                        title: "As many spots as you like",
                        detail: "The bed by the fence and the one by the garage answer differently."
                    )
                    Feature(
                        icon: "bell",
                        title: "Told when the sun arrives",
                        detail: "A word before it reaches the spot, so a short winter afternoon is not missed."
                    )
                    Feature(
                        icon: "square.grid.2x2",
                        title: "The widget",
                        detail: "Today's hours on the home screen, without opening anything."
                    )
                }

                buyButton
                restoreButton

                if let error = purchases.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("One payment. No subscription, no renewal, nothing to cancel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .task { await purchases.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sun.max.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("What about in October?")
                .font(.title.bold())
            Text("You know what this spot gets today. The year is where the surprises are.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var buyButton: some View {
        switch purchases.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .locked(let price):
            Button {
                Task { await purchases.buy() }
            } label: {
                Text(purchases.isWorking ? "One moment…" : "Unlock for \(price)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.orange)
            .disabled(purchases.isWorking)
        case .unlocked:
            Label("Unlocked", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unavailable:
            // A bad connection, not a refusal, and worth saying so — with a way out. This app
            // is used standing in a garden at the edge of a signal, which is exactly where the
            // store is hardest to reach, and until now a single failed request left the paywall
            // dead until somebody thought to close and reopen it.
            VStack(spacing: 12) {
                Label("Can't reach the App Store just now", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                Button {
                    Task { await purchases.load() }
                } label: {
                    Text(purchases.state == .loading ? "One moment…" : "Try again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var restoreButton: some View {
        if purchases.state != .unlocked {
            Button("Already bought it? Restore") {
                Task { await purchases.restore() }
            }
            .font(.subheadline)
            .disabled(purchases.isWorking)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct Feature: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
