import Foundation
import SpotKit
import Observation
import WidgetKit
import SolarCore

/// Every spot the person keeps, which one they are looking at, and the moment being examined.
///
/// All the screens read from here so they can never disagree: scrubbing the day on the map
/// moves the sun on every other screen too, and switching spots switches all of them at once.
@MainActor
@Observable
final class SpotStore {

    /// How many spots come without paying. One is enough to answer the question that brought
    /// somebody here; the second is what the purchase is for.
    static let freeSpotLimit = 1

    private(set) var spots: [Spot] = [] {
        didSet { persist() }
    }

    /// Which spot every screen is currently talking about.
    private(set) var selectedID: UUID? {
        didSet {
            guard oldValue != selectedID else { return }
            SharedSelection.record(selectedID: selectedID)
            WidgetRefresh.reload()
        }
    }

    private let archive: SpotArchive?

    /// The moment under examination. Starts at now and follows the clock until the person
    /// scrubs, after which it stays where they put it.
    var viewedDate: Date = .now

    /// True while the app is still following the clock rather than a chosen time.
    private(set) var followsClock = true

    init(archive: SpotArchive? = try? SpotArchive()) {
        self.archive = archive
        // Assigning through the backing store on purpose: loading is not a change worth
        // writing straight back to disk.
        let restored = archive?.loadIgnoringDamage() ?? []
        _spots = restored
        // A selection made before the app was last closed outlives it.
        selectedID = SharedSelection.spot(from: restored)?.id
    }

    // MARK: - The spot in front of you

    /// The spot every screen is showing.
    var spot: Spot? {
        guard let selectedID else { return spots.first }
        return spots.first { $0.id == selectedID } ?? spots.first
    }

    func select(_ id: UUID) {
        guard spots.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// True when another spot may be added.
    func canAddSpot(isUnlocked: Bool) -> Bool {
        isUnlocked || spots.count < Self.freeSpotLimit
    }

    // MARK: - Changing the collection

    /// Adds a spot and makes it the one being looked at.
    @discardableResult
    func addSpot(at coordinate: GeoCoordinate, named name: String? = nil) -> Spot {
        let spot = Spot(name: name ?? Self.nextName(after: spots), coordinate: coordinate)
        spots.append(spot)
        selectedID = spot.id
        return spot
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty name would leave a row with nothing in it and no way to tell spots apart.
        guard !trimmed.isEmpty, let index = spots.firstIndex(where: { $0.id == id }) else { return }
        spots[index].name = trimmed
    }

    func remove(_ id: UUID) {
        spots.removeAll { $0.id == id }
        if selectedID == id { selectedID = spots.first?.id }
    }

    /// Names for spots after the first, so a list of them can be told apart at a glance.
    static func nextName(after existing: [Spot]) -> String {
        guard !existing.isEmpty else { return "Here" }
        let taken = Set(existing.map(\.name))
        var number = 2
        while taken.contains("Spot \(number)") { number += 1 }
        return "Spot \(number)"
    }

    // MARK: - Changing the selected spot

    /// Adopts a position from the device, unless a spot has already been placed by hand — a
    /// location update should not yank the pin out from under anybody.
    func adoptDeviceLocation(latitude: Double, longitude: Double) {
        // A restored spot counts as already placed, so a location fix on launch must not
        // discard the skyline someone traced last week.
        guard spots.isEmpty else { return }
        addSpot(
            at: GeoCoordinate(latitude: latitude, longitude: longitude),
            named: "Here"
        )
    }

    /// Moves the selected spot, keeping any skyline already traced for it.
    func move(to coordinate: GeoCoordinate) {
        guard updateSelected({ $0.coordinate = coordinate }) else {
            addSpot(at: coordinate, named: "Spot")
            return
        }
    }

    func setHorizon(_ horizon: HorizonProfile) {
        _ = updateSelected { $0.horizon = horizon }
    }

    /// Turns the arrival warning on or off for the selected spot.
    func setAlert(minutesBefore: Int?) {
        _ = updateSelected { $0.alertMinutesBefore = minutesBefore }
    }

    /// Applies a change to the selected spot. Returns false when there is nothing selected.
    @discardableResult
    private func updateSelected(_ change: (inout Spot) -> Void) -> Bool {
        guard let id = spot?.id, let index = spots.firstIndex(where: { $0.id == id }) else {
            return false
        }
        change(&spots[index])
        return true
    }

    // MARK: - Time

    /// Jumps to a time on the day currently being viewed.
    func scrub(toMinuteOfDay minute: Int) {
        guard let spot else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = spot.timeZone
        let startOfDay = calendar.startOfDay(for: viewedDate)
        viewedDate = startOfDay.addingTimeInterval(Double(minute) * 60)
        followsClock = false
    }

    /// Moves to a calendar day in the spot's own time zone, keeping the minute of the day. Only a
    /// screenshot run asks for it; an ordinary launch never leaves today.
    func jump(toYear year: Int, month: Int, day: Int) {
        guard let spot else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = spot.timeZone
        guard let start = calendar.date(from: DateComponents(timeZone: spot.timeZone, year: year, month: month, day: day))
        else { return }
        viewedDate = start.addingTimeInterval(Double(viewedMinuteOfDay) * 60)
        followsClock = false
    }

    /// Returns to following the clock.
    func returnToNow() {
        viewedDate = .now
        followsClock = true
    }

    /// Called on the app's timer. Only advances while the person has not taken control.
    func clockTicked(to date: Date) {
        guard followsClock else { return }
        viewedDate = date
    }

    /// Minutes since local midnight for the viewed moment, for driving a slider.
    var viewedMinuteOfDay: Int {
        guard let spot else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = spot.timeZone
        let startOfDay = calendar.startOfDay(for: viewedDate)
        return Int(viewedDate.timeIntervalSince(startOfDay) / 60)
    }

    // MARK: - Storing

    private func persist() {
        guard let archive else { return }
        do {
            try archive.save(spots)
            // The home screen is showing a figure for one of these; it may have just changed.
            WidgetRefresh.reload()
        } catch {
            // Losing a save is bad but not worth taking the app down for; the person can
            // trace again. Silence here is deliberate rather than forgotten.
        }
    }
}
