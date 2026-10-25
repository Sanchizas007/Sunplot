import SwiftUI
import SpotKit

@main
struct SunspotApp: App {
    @State private var location: LocationProvider
    @State private var store: SpotStore
    @State private var purchases: Purchases
    @State private var alerts: SunAlerts
    @State private var introduction: IntroductionFlow

    init() {
        // Before anything reads the archive: `SpotStore` loads it the moment it is built, so
        // a screenshot run's seed written any later would be a file nobody opens. Does
        // nothing unless the screenshot script asked for it, and does not exist in a release.
        Demo.prepareIfRequested()

        let store = SpotStore()
        _location = State(initialValue: LocationProvider())
        _store = State(initialValue: store)
        _purchases = State(initialValue: Purchases())
        _alerts = State(initialValue: SunAlerts())
        // Decided here, once the archive has been read: somebody who already has spots is not
        // somebody who has just arrived.
        _introduction = State(initialValue: IntroductionFlow(hasSpots: !store.spots.isEmpty))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(store)
                .environment(purchases)
                .environment(alerts)
                .environment(introduction)
        }
    }
}

/// The four screens, named so something other than a finger can choose between them.
enum MainTab: Hashable {
    case today, map, sky, year

    /// Which tab a screenshot run is asking for. Everything it reaches from Today — the
    /// planting list, the comparison, the paywall — starts on Today.
    init(demoScreen: Demo.Screen?) {
        switch demoScreen {
        case .map: self = .map
        case .sky: self = .sky
        case .year: self = .year
        default: self = .today
        }
    }
}

private struct RootView: View {
    @Environment(LocationProvider.self) private var location
    @Environment(SpotStore.self) private var store
    @Environment(Purchases.self) private var purchases
    @Environment(SunAlerts.self) private var alerts
    @Environment(IntroductionFlow.self) private var introduction

    @State private var tab = MainTab(demoScreen: Demo.screen)

    @Environment(\.scenePhase) private var scenePhase

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            tabs
                // Everything behind the tour is out of reach, to a finger and to VoiceOver alike.
                .accessibilityHidden(introduction.isPresented)

            if introduction.isPresented {
                IntroductionView(startPage: introduction.startPage, isFirstRun: introduction.isFirstRun) {
                    finishIntroduction()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // The tour fills the screen edge to edge, and a status bar on top of a night sky is
        // dark text on dark paint in light mode.
        .statusBarHidden(introduction.isPresented)
    }

    /// Closes the tour, and on the first run goes on to ask where the person is — the question
    /// the tour exists to prepare them for. A beat after the fade, so the system dialog does not
    /// arrive on top of a page that is still leaving.
    private func finishIntroduction() {
        let wasFirstRun = introduction.isFirstRun
        withAnimation(.easeInOut(duration: 0.45)) { introduction.finish() }
        guard wasFirstRun else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            location.start()
        }
    }

    private var tabs: some View {
        // The classic tab API rather than iOS 18's `Tab`: this app has no reason to shut
        // out a phone that is two years old, and plenty of the people it is for are using one.
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(MainTab.today)
            SpotMapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(MainTab.map)
            SkyView()
                .tabItem { Label("Sky", systemImage: "camera.viewfinder") }
                .tag(MainTab.sky)
            YearView()
                .tabItem { Label("Year", systemImage: "calendar") }
                .tag(MainTab.year)
        }
        .task {
            // A screenshot run has its spots already, and the app only ever asks the device
            // where it is in order to place the first one. Starting location services anyway
            // puts the "in use" arrow in the status bar of every frame in the store listing,
            // which reads as tracking to somebody deciding whether to download a garden app.
            // On a first run the tour starts it, once it has explained why.
            if !Demo.isRunning && !introduction.isFirstRun { location.start() }
            purchases.startListening()
            await purchases.load()
            await alerts.reschedule(for: store.spots)
        }
        .demoState()
        // Warnings are handed to the system a week at a time and nothing refills them on its
        // own. Without this they run out quietly on the eighth day — and a spot that has been
        // moved or retraced since goes on announcing a sun that no longer arrives then. The
        // task above covers a cold launch; this covers coming back to an app that never quit.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await alerts.reschedule(for: store.spots) }
        }
        .onReceive(tick) { store.clockTicked(to: $0) }
        .onChange(of: location.state) { _, state in
            if case let .located(latitude, longitude) = state {
                store.adoptDeviceLocation(latitude: latitude, longitude: longitude)
            }
        }
    }
}
