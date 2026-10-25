import SwiftUI
import SpotKit
import SolarCore

/// Switches between spots, and adds them.
///
/// Lives in the toolbar rather than on a screen of its own: which spot you are looking at is
/// context for everything else, not a place you go.
struct SpotPicker: ToolbarContent {
    @Environment(SpotStore.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(LocationProvider.self) private var location
    @Environment(IntroductionFlow.self) private var introduction

    @Binding var renaming: Spot?
    @Binding var showingPaywall: Bool
    @Binding var comparing: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if store.spots.count > 1 {
                    Section("Spots") {
                        ForEach(store.spots) { spot in
                            Button {
                                store.select(spot.id)
                            } label: {
                                Label(
                                    spot.name,
                                    systemImage: spot.id == store.spot?.id ? "checkmark" : ""
                                )
                            }
                        }
                    }
                }

                Section {
                    // Only worth offering once there is something to compare against.
                    if store.spots.count > 1 {
                        Button {
                            comparing = true
                        } label: {
                            Label("Which is better?", systemImage: "square.on.square.dashed")
                        }
                    }

                    Button {
                        addSpot()
                    } label: {
                        Label(
                            "Add a spot",
                            systemImage: store.canAddSpot(isUnlocked: purchases.isUnlocked)
                                ? "plus" : "lock"
                        )
                    }

                    if let current = store.spot {
                        Button {
                            renaming = current
                        } label: {
                            Label("Rename \(current.name)", systemImage: "pencil")
                        }

                        // Never offer to delete the last one: an empty app has nothing to show
                        // and no obvious way back.
                        if store.spots.count > 1 {
                            Button(role: .destructive) {
                                store.remove(current.id)
                            } label: {
                                Label("Delete \(current.name)", systemImage: "trash")
                            }
                        }
                    }
                }

                // Last, and apart: it is about the app rather than about any spot.
                Section {
                    Button {
                        introduction.replay()
                    } label: {
                        Label("How Sunplot works", systemImage: "questionmark.circle")
                    }
                }
            } label: {
                // Spelled out rather than a Label: a Label in a toolbar menu collapses to
                // its icon, and which spot you are looking at is the one thing this control
                // exists to tell you.
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    // The name is the person's own words and stays as typed; only the
                    // stand-in for having none is ours to translate.
                    if let name = store.spot?.name {
                        Text(name).lineLimit(1)
                    } else {
                        Text("Spots")
                    }
                }
                .font(.subheadline)
            }
        }
    }

    /// Puts a new spot somewhere the person can see it, then leaves them to drag it into place.
    private func addSpot() {
        guard store.canAddSpot(isUnlocked: purchases.isUnlocked) else {
            showingPaywall = true
            return
        }

        // Where the phone is, if it knows; otherwise beside the spot already on screen, so
        // the new pin lands somewhere in view rather than off in the ocean.
        let coordinate: GeoCoordinate
        if case let .located(latitude, longitude) = location.state {
            coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        } else if let existing = store.spot?.coordinate {
            coordinate = existing.destination(atAzimuth: 90, distance: 30)
        } else {
            return
        }
        store.addSpot(at: coordinate)
    }
}

/// The rename sheet, small enough to be an alert.
struct RenameSpotAlert: ViewModifier {
    @Environment(SpotStore.self) private var store
    @Binding var spot: Spot?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("Name this spot", isPresented: .constant(spot != nil)) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) { spot = nil }
                Button("Save") {
                    if let spot { store.rename(spot.id, to: name) }
                    spot = nil
                }
            } message: {
                Text("Something you will recognise: the bed by the fence, the balcony, the shed roof.")
            }
            .onChange(of: spot?.id) { _, _ in
                name = spot?.name ?? ""
            }
    }
}

extension View {
    func renameSpot(_ spot: Binding<Spot?>) -> some View {
        modifier(RenameSpotAlert(spot: spot))
    }
}
