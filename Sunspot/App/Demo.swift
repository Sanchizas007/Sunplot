import Foundation
import SwiftUI
import SolarCore
import SpotKit

/// Puts the app into one fixed, known state so the App Store screenshots can be shot without
/// touching the screen.
///
/// A set taken by hand drifts. A different spot every time, a skyline traced halfway in one
/// frame and not at all in the next, a figure nobody can reproduce a month later when the
/// store asks for a fresh set because a screen changed. Seeding the same garden every time
/// makes the whole folder disposable: delete it, run the script, get the same frames back.
///
/// Everything here is `#if DEBUG` and every part of it additionally waits to be asked for on
/// the command line. A release build carries none of the data, and a debug build launched
/// normally behaves as if this file were not here.
enum Demo {

    // MARK: - What was asked for

    /// The screen a screenshot run wants in front when the app opens.
    enum Screen: String {
        /// The four tabs.
        case today, map, sky, year
        /// Today as somebody who has not paid sees it — the one state the rest of the run
        /// cannot show, because everything else is shot with the purchase made.
        case todayLocked = "today-locked"
        /// Things reached from Today, which the run cannot tap its way to.
        case plants, compare, paywall
    }

    /// True while the app is being driven by the screenshot script.
    static var isRunning: Bool {
        #if DEBUG
        return arguments.contains("-SunspotDemoData")
        #else
        return false
        #endif
    }

    /// The screen to open on, or nil when nobody asked.
    static var screen: Screen? {
        #if DEBUG
        guard isRunning else { return nil }
        guard let index = arguments.firstIndex(of: "-SunspotDemoScreen"),
              index + 1 < arguments.count
        else { return .today }
        return Screen(rawValue: arguments[index + 1]) ?? .today
        #else
        return nil
        #endif
    }

    /// What the paywall is worth showing off, and what it is worth hiding.
    ///
    /// Every frame but one is shot with the purchase made, because a store listing shows the
    /// app rather than the shop. The paywall itself is the exception: it is shot locked, for
    /// the review screenshot the in-app purchase needs, and at the price the configuration
    /// file actually sells it for rather than one invented here.
    static var pretendedPurchase: PretendedPurchase? {
        #if DEBUG
        guard let screen else { return nil }
        return screen == .paywall || screen == .todayLocked
            ? .locked(price: "$5.99")
            : .unlocked
        #else
        return nil
        #endif
    }

    enum PretendedPurchase: Equatable {
        case unlocked
        case locked(price: String)
    }

    /// The moment every frame is shot at, in minutes after local midnight.
    ///
    /// Frozen on purpose. A run started at four in the morning would otherwise show a sun
    /// below the horizon and a day already spent, and the same run at noon would not — two
    /// sets that do not match, and neither of them saying anything about the app.
    static let momentOfDay = 13 * 60 + 30

    /// Where the Sky screen's camera is pointing for its frame, in degrees from true north,
    /// and how far above the horizontal.
    ///
    /// Just west of south, because that is where the sun stands in the early afternoon at
    /// every latitude this app is aimed at — and tipped up far enough that the sun sits in
    /// the top half of the frame with the traced skyline still in the bottom of it.
    static let skyBearing: Double = 190
    static let skyPitch: Double = 28

    // MARK: - Seeding

    /// Writes the demo garden into the shared container, before anything has read it.
    ///
    /// Called from the app's `init` rather than from a view: `SpotStore` loads the archive
    /// the moment it is built, and a seed written after that would be a file nobody opens.
    static func prepareIfRequested() {
        #if DEBUG
        guard isRunning else { return }
        let spots = spots()
        if let archive = try? SpotArchive() {
            try? archive.save(spots)
        }
        SharedSelection.record(selectedID: spots.first?.id)
        Unlock.record(isUnlocked: pretendedPurchase == .unlocked)
        #endif
    }

    /// Tells the screenshot script the screen is up, and what today's figure says here.
    ///
    /// Two things the script cannot work out for itself. Watching the pixels is not enough —
    /// under load the launch screen gets captured instead of the app — and the headline above
    /// the frame has to carry the same number as the screen inside it, in a language whose
    /// hours are not written the English way. The app knows both, so the app says both.
    static func report(hours: String) {
        #if DEBUG
        guard isRunning else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sunplot-shot.json")
        let payload: [String: String] = ["ready": "yes", "hours": hours]
        try? JSONSerialization.data(withJSONObject: payload).write(to: url)
        #endif
    }

    #if DEBUG

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Fixed rather than random, so the widget's saved selection still names a spot that
    /// exists after the app is reinstalled between languages.
    private static let ids = [
        UUID(uuidString: "5C0DE000-0000-4000-A000-000000000001")!,
        UUID(uuidString: "5C0DE000-0000-4000-A000-000000000002")!,
        UUID(uuidString: "5C0DE000-0000-4000-A000-000000000003")!
    ]

    /// The three spots every frame is shot with: a garden bed that does well, a border by the
    /// house that does half as well, and a balcony that does not.
    ///
    /// Three rather than one, because half of what is being sold is the answer to "which of
    /// these is better", and a comparison of one spot is not a comparison. The figures they
    /// produce today are seven hours fifty, five and a half, and three and a quarter — far
    /// enough apart to be read at a glance, and none of them invented: they come out of the
    /// same engine as everybody else's, from the skylines below.
    static func spots() -> [Spot] {
        let place = place()
        let names = names()
        let skylines = [gardenSkyline, borderSkyline, balconySkyline]
        // Only the first is warned about. Three notifications for one garden is what makes
        // people turn all of them off.
        let alerts: [Int?] = [20, nil, nil]

        return (0..<3).map { index in
            Spot(
                id: ids[index],
                name: names[index],
                coordinate: place.spots[index],
                horizon: HorizonProfile(samples: skylines[index]),
                timeZone: place.timeZone,
                alertMinutesBefore: alerts[index]
            )
        }
    }

    /// Builds a skyline the way a traced one actually looks.
    ///
    /// Two parts. The envelope is the coarse shape — hedge, tree, terrace, house — given every
    /// ten degrees. The detail on top is what a real trace picks up and a dozen numbers cannot:
    /// the gable of each house in the row opposite, a chimney, the lumps of a tree crown. It is
    /// sampled every degree and a half, which is the resolution a finger sweep produces.
    ///
    /// This is not decoration. A profile of thirty-six points draws as a smooth ridge, and the
    /// Sky screen fills that ridge in where there is no camera — so a coarse profile makes the
    /// one screen that sells the whole idea look like a black slab instead of roofs and trees.
    /// The hours barely move: seven fifty-two against seven fifty-one.
    private static func skyline(
        envelope: [Int], detail: (Double) -> Double
    ) -> [HorizonProfile.Sample] {
        stride(from: 0.0, to: 360.0, by: 1.5).map { azimuth in
            HorizonProfile.Sample(
                azimuth: azimuth,
                elevation: max(0, interpolate(envelope, at: azimuth) + detail(azimuth))
            )
        }
    }

    /// The coarse shape between its ten-degree points.
    private static func interpolate(_ values: [Int], at azimuth: Double) -> Double {
        let step = 360.0 / Double(values.count)
        let index = Int(azimuth / step) % values.count
        let next = (index + 1) % values.count
        let t = (azimuth - Double(index) * step) / step
        return Double(values[index]) * (1 - t) + Double(values[next]) * t
    }

    /// A row of pitched roofs: ridge, eaves, ridge, across a stretch of horizon.
    private static func roofline(
        _ azimuth: Double, from: Double, to: Double, width: Double, height: Double
    ) -> Double {
        guard azimuth >= from, azimuth <= to else { return 0 }
        let phase = (azimuth - from).truncatingRemainder(dividingBy: width) / width
        return height * (1 - abs(phase - 0.5) * 2)
    }

    /// One chimney, four degrees wide, because every terrace has them and they are the detail
    /// that makes a silhouette read as a street rather than a hill.
    private static func chimney(_ azimuth: Double, at bearing: Double, height: Double) -> Double {
        abs(azimuth - bearing) <= 2 ? height : 0
    }

    /// A hedge is never a straight line. Kept strictly positive: a wobble that dips would open
    /// a sliver of midwinter sun through the one direction that is supposed to be shut.
    private static func hedge(_ azimuth: Double) -> Double {
        0.4 * (1 + sin(azimuth / 6))
    }

    /// A back garden: next door's tree to the east, a terrace of houses across the south that
    /// the midsummer sun clears and the December sun never does, our own house to the west.
    private static let gardenSkyline = skyline(
        envelope: [4, 4, 5, 6, 8, 12, 18, 24, 26, 28, 25, 20,
                   16, 15, 15, 16, 16, 16, 16, 16, 16, 18, 22, 26,
                   30, 32, 32, 30, 26, 20, 14, 10, 7, 5, 4, 4]
    ) { azimuth in
        var detail = roofline(azimuth, from: 128, to: 232, width: 14, height: 2.6)
        detail += chimney(azimuth, at: 172, height: 3.4)
        detail += roofline(azimuth, from: 236, to: 296, width: 20, height: 2.0)
        detail += chimney(azimuth, at: 260, height: 4.0)
        if (62...134).contains(azimuth) {
            detail += 3.0 * sin((azimuth - 62) / 72 * .pi * 3)
        }
        return detail + hedge(azimuth)
    }

    /// The border on the other side of the same garden, tight against the wall. Everything
    /// stands a little higher from here, which is the whole point of the app: a few metres is
    /// the difference between seven hours fifty and five and a half.
    private static let borderSkyline = skyline(
        envelope: [8, 8, 11, 16, 22, 28, 34, 38, 40, 40, 38, 34,
                   32, 31, 30, 30, 31, 31, 32, 33, 35, 37, 39, 41,
                   42, 42, 42, 40, 35, 29, 22, 17, 13, 10, 8, 8]
    ) { azimuth in
        var detail = roofline(azimuth, from: 120, to: 240, width: 16, height: 3.0)
        detail += chimney(azimuth, at: 188, height: 3.6)
        detail += roofline(azimuth, from: 240, to: 300, width: 20, height: 2.2)
        if (50...130).contains(azimuth) {
            detail += 3.5 * sin((azimuth - 50) / 80 * .pi * 2)
        }
        return detail + hedge(azimuth)
    }

    /// A recessed balcony: walls either side and a slot of sky facing south. A few hours in the
    /// middle of the day and nothing at either end — and, being up above the rooftops, the only
    /// one of the three that still sees the sun in December. The walls are smooth; the roofs
    /// visible through the slot are not.
    private static let balconySkyline = skyline(
        envelope: [50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50,
                   50, 48, 40, 24, 12, 10, 12, 22, 38, 50, 50, 50,
                   50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50]
    ) { azimuth in
        roofline(azimuth, from: 146, to: 208, width: 15, height: 2.4)
            + chimney(azimuth, at: 176, height: 3.0)
    }

    /// Where the demo garden is. Residential rather than a city centre, so the map frame
    /// shows gardens and rooftops instead of a railway station, and northern enough that the
    /// app is answering a question worth asking.
    private struct Place {
        let spots: [GeoCoordinate]
        let timeZone: TimeZone
    }

    private static func place() -> Place {
        switch language() {
        case "de":
            // Frohnau, a garden suburb of large plots. Two earlier tries put the pin beside a
            // motorway junction and then on a shopping street, both of which photograph as
            // exactly the sort of place nobody keeps a vegetable bed.
            Place(spots: [GeoCoordinate(latitude: 52.6335, longitude: 13.2790),
                          GeoCoordinate(latitude: 52.6332, longitude: 13.2797),
                          GeoCoordinate(latitude: 52.6340, longitude: 13.2801)],
                  timeZone: TimeZone(identifier: "Europe/Berlin") ?? .current)
        case "fr":
            // The park quarter of Maisons-Laffitte: villas on large plots, laid out in the
            // nineteenth century and still without a shop in it. Le Vésinet was tried first
            // and the pin landed on its high street, between a Monoprix and an optician.
            Place(spots: [GeoCoordinate(latitude: 48.9552, longitude: 2.1424),
                          GeoCoordinate(latitude: 48.9549, longitude: 2.1431),
                          GeoCoordinate(latitude: 48.9557, longitude: 2.1435)],
                  timeZone: TimeZone(identifier: "Europe/Paris") ?? .current)
        // The rest: a garden quarter in a city where that language is spoken, so the map in
        // the frame shows streets and roofs somebody there recognises rather than a London
        // suburb with English street names. All of them are real residential blocks with
        // plots big enough for a bed; the figures come out of the same engine either way.
        case "es":
            Place(spots: [GeoCoordinate(latitude: 40.4352, longitude: -3.8125),   // Pozuelo de Alarcón, Madrid
                          GeoCoordinate(latitude: 40.4349, longitude: -3.8118),
                          GeoCoordinate(latitude: 40.4357, longitude: -3.8114)],
                  timeZone: TimeZone(identifier: "Europe/Madrid") ?? .current)
        case "it":
            Place(spots: [GeoCoordinate(latitude: 45.5205, longitude: 9.1830),    // Bresso, Milan
                          GeoCoordinate(latitude: 45.5202, longitude: 9.1837),
                          GeoCoordinate(latitude: 45.5210, longitude: 9.1841)],
                  timeZone: TimeZone(identifier: "Europe/Rome") ?? .current)
        case "nl":
            Place(spots: [GeoCoordinate(latitude: 52.2797, longitude: 5.1600),    // Bussum, Het Gooi
                          GeoCoordinate(latitude: 52.2794, longitude: 5.1607),
                          GeoCoordinate(latitude: 52.2802, longitude: 5.1611)],
                  timeZone: TimeZone(identifier: "Europe/Amsterdam") ?? .current)
        case "pl":
            Place(spots: [GeoCoordinate(latitude: 52.1700, longitude: 21.0900),   // Wilanów, Warsaw
                          GeoCoordinate(latitude: 52.1697, longitude: 21.0907),
                          GeoCoordinate(latitude: 52.1705, longitude: 21.0911)],
                  timeZone: TimeZone(identifier: "Europe/Warsaw") ?? .current)
        case "pt-BR":
            Place(spots: [GeoCoordinate(latitude: -23.5440, longitude: -46.7010), // Alto de Pinheiros, São Paulo
                          GeoCoordinate(latitude: -23.5443, longitude: -46.7003),
                          GeoCoordinate(latitude: -23.5435, longitude: -46.6999)],
                  timeZone: TimeZone(identifier: "America/Sao_Paulo") ?? .current)
        case "ru":
            Place(spots: [GeoCoordinate(latitude: 55.6490, longitude: 37.3340),   // Peredelkino, Moscow
                          GeoCoordinate(latitude: 55.6487, longitude: 37.3347),
                          GeoCoordinate(latitude: 55.6495, longitude: 37.3351)],
                  timeZone: TimeZone(identifier: "Europe/Moscow") ?? .current)
        case "tr":
            Place(spots: [GeoCoordinate(latitude: 41.1200, longitude: 29.0900),   // Beykoz, Istanbul
                          GeoCoordinate(latitude: 41.1197, longitude: 29.0907),
                          GeoCoordinate(latitude: 41.1205, longitude: 29.0911)],
                  timeZone: TimeZone(identifier: "Europe/Istanbul") ?? .current)
        case "ja":
            Place(spots: [GeoCoordinate(latitude: 35.6420, longitude: 139.6390),  // Setagaya, Tokyo
                          GeoCoordinate(latitude: 35.6417, longitude: 139.6397),
                          GeoCoordinate(latitude: 35.6425, longitude: 139.6401)],
                  timeZone: TimeZone(identifier: "Asia/Tokyo") ?? .current)
        case "ko":
            Place(spots: [GeoCoordinate(latitude: 37.6060, longitude: 126.9680),  // Pyeongchang-dong, Seoul
                          GeoCoordinate(latitude: 37.6057, longitude: 126.9687),
                          GeoCoordinate(latitude: 37.6065, longitude: 126.9691)],
                  timeZone: TimeZone(identifier: "Asia/Seoul") ?? .current)
        case "zh-Hans":
            Place(spots: [GeoCoordinate(latitude: 31.1500, longitude: 121.1100),  // Qingpu, Shanghai
                          GeoCoordinate(latitude: 31.1497, longitude: 121.1107),
                          GeoCoordinate(latitude: 31.1505, longitude: 121.1111)],
                  timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current)
        case "zh-Hant":
            Place(spots: [GeoCoordinate(latitude: 25.1180, longitude: 121.5300),  // Tianmu, Taipei
                          GeoCoordinate(latitude: 25.1177, longitude: 121.5307),
                          GeoCoordinate(latitude: 25.1185, longitude: 121.5311)],
                  timeZone: TimeZone(identifier: "Asia/Taipei") ?? .current)
        default:
            Place(spots: [GeoCoordinate(latitude: 51.5590, longitude: -0.1720),
                          GeoCoordinate(latitude: 51.5587, longitude: -0.1713),
                          GeoCoordinate(latitude: 51.5595, longitude: -0.1709)],
                  timeZone: TimeZone(identifier: "Europe/London") ?? .current)
        }
    }

    /// Spot names are the person's own words and so are never translated by the app. In a
    /// screenshot they are ours, and a German frame with an English label in the toolbar
    /// looks exactly like the half-translated app it is trying not to be.
    private static func names() -> [String] {
        switch language() {
        case "de":      ["Beet hinterm Haus", "Streifen an der Wand", "Balkon"]
        case "es":      ["Bancal del fondo", "Arriate del muro", "Balcón"]
        case "fr":      ["Planche du fond", "Bordure du mur", "Balcon"]
        case "it":      ["Aiuola in fondo", "Bordura del muro", "Balcone"]
        case "ja":      ["奥の花壇", "塀ぎわの列", "ベランダ"]
        case "ko":      ["안쪽 화단", "담장 옆 화단", "베란다"]
        case "nl":      ["Bed achterin", "Rand bij de muur", "Balkon"]
        case "pl":      ["Grządka z tyłu", "Pas przy ścianie", "Balkon"]
        case "pt-BR":   ["Canteiro do fundo", "Bordadura do muro", "Varanda"]
        case "ru":      ["Дальняя грядка", "Полоса у стены", "Балкон"]
        case "tr":      ["Arka tarh", "Duvar kenarı", "Balkon"]
        case "zh-Hans": ["后院的地", "墙边一条", "阳台"]
        case "zh-Hant": ["後院的地", "牆邊一條", "陽台"]
        default:        ["Back bed", "Wall border", "Balcony"]
        }
    }

    /// The catalogue the app is actually running in — "pt-BR" and "zh-Hant" included.
    ///
    /// Not `Locale.language.languageCode`, which flattens both Chinese scripts to "zh" and
    /// Brazilian Portuguese to "pt": the demo garden is picked per catalogue, and those three
    /// want different cities.
    private static func language() -> String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    #endif
}

extension Demo.Screen: Identifiable {
    var id: String { rawValue }
}

extension View {
    /// Applies whatever the screenshot script asked for: the frozen moment, and the one
    /// screen a launch argument cannot reach because it is behind a tap.
    ///
    /// One modifier in one place rather than a flag in each screen. Outside a screenshot run
    /// — which is every run anybody but this script will ever do — it does nothing.
    func demoState() -> some View { modifier(DemoState()) }
}

private struct DemoState: ViewModifier {
    @Environment(SpotStore.self) private var store
    @State private var sheet: Demo.Screen?

    func body(content: Content) -> some View {
        content
            .task {
                guard Demo.isRunning else { return }
                // Every frame shot at the same time of day, so the set is one afternoon in
                // one garden rather than a scrapbook.
                store.scrub(toMinuteOfDay: Demo.momentOfDay)
                // Not `.plants`: that one is a push, and Today opens it from its own path.
                switch Demo.screen {
                case .compare, .paywall: sheet = Demo.screen
                default: break
                }
                let minutes = store.spot?.sunDay(on: store.viewedDate).directMinutes ?? 0
                Demo.report(hours: Format.duration(minutes: minutes))
            }
            .sheet(item: $sheet) { screen in
                switch screen {
                case .compare:
                    CompareSpots()
                case .paywall:
                    Paywall()
                default:
                    EmptyView()
                }
            }
    }
}
