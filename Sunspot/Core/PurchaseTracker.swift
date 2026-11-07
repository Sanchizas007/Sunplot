import Foundation
import StoreKit
import RevenueCat
import SpotKit

/// RevenueCat watches; it never decides.
///
/// Who has paid is answered by StoreKit 2 on the phone, from the device's own receipt, so the
/// app behaves the same with RevenueCat, without it, or while its servers are down. This only
/// tells RevenueCat what happened — a purchase was made, one was restored — and, once per
/// install, hands it Apple's AdServices token so that it can say which Apple Ads campaign
/// brought the person. The token says nothing about who they are; the advertising identifier is
/// never read and no tracking prompt is shown.
///
/// What goes out is exactly what the privacy manifest, the App Privacy answers and the privacy
/// policy on the site say it is: the purchase, and the ad campaign. Never a location, a spot or
/// a skyline. If either is ever taken out, take it out of all four places.
///
/// The only file that imports RevenueCat. Its `Purchases` is written out in full below because
/// the app has a type of the same name, and that is the one the rest of the code means.
@MainActor
enum PurchaseTracker {

    /// A screenshot run or a test run is the app being exercised, not used, and must not add
    /// people to the owner's charts.
    private static var isAutomatedRun: Bool {
        Demo.isRunning || PurchaseReporting.isTestRun
    }

    /// Starts RevenueCat in observer mode, if this build carries a key and this is a real run.
    /// Safe to call more than once.
    static func start() {
        let key = Bundle.main.object(forInfoDictionaryKey: "RCPublicAPIKey") as? String
        guard let key,
              PurchaseReporting.shouldReport(key: key, isAutomatedRun: isAutomatedRun),
              !RevenueCat.Purchases.isConfigured
        else { return }

        RevenueCat.Purchases.logLevel = .warn
        // `.myApp`: the app completes its own purchases, RevenueCat only observes them.
        RevenueCat.Purchases.configure(
            withAPIKey: key,
            appUserID: nil,
            purchasesAreCompletedBy: .myApp,
            storeKitVersion: .storeKit2
        )
        RevenueCat.Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()
    }

    /// Tells RevenueCat about a purchase the app has just completed. Failing quietly is right:
    /// the person has paid and is already unlocked, and RevenueCat hears about it from Apple's
    /// server notifications as well.
    static func record(_ result: Product.PurchaseResult) async {
        guard RevenueCat.Purchases.isConfigured else { return }
        _ = try? await RevenueCat.Purchases.shared.recordPurchase(result)
    }

    /// Tells RevenueCat the person asked to restore, so that what the store holds for their
    /// Apple Account is sent along.
    static func restored() async {
        guard RevenueCat.Purchases.isConfigured else { return }
        _ = try? await RevenueCat.Purchases.shared.syncPurchases()
    }
}
