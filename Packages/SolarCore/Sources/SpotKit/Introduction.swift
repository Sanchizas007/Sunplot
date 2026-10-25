import Foundation

/// Whether the short tour at the first launch has already been seen.
///
/// Written where the app's other small facts are written — the App Group its widget shares —
/// and not into the app's own standard defaults. That is the one place the privacy manifest
/// already accounts for, and a flag that somebody has seen a tour is not worth a second
/// declaration to Apple.
public enum Introduction {

    private static let key = "hasSeenIntroduction"

    private static var store: UserDefaults? {
        UserDefaults(suiteName: SpotArchive.appGroup)
    }

    public static var hasBeenSeen: Bool {
        store?.bool(forKey: key) ?? false
    }

    public static func markSeen() {
        store?.set(true, forKey: key)
    }

    /// Whether this launch should open with the tour.
    ///
    /// Only for somebody who has neither seen it nor already has spots. An update must not
    /// greet a person who has been using the app for months with an introduction to it, and a
    /// spot on disk is proof they did not just arrive. Everybody else can still open it from
    /// the menu whenever they like.
    public static func shouldShowAtLaunch(hasSeen: Bool, hasSpots: Bool) -> Bool {
        !hasSeen && !hasSpots
    }
}
