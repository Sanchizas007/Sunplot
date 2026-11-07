import Foundation

/// When the app may tell RevenueCat anything at all.
///
/// RevenueCat is a bystander. The store decides who has paid, on the phone and offline;
/// RevenueCat is only told, so that the owner's charts fill in and an Apple Ads campaign can be
/// credited with the install. Whether to tell it is decided here, in one small rule, so that the
/// two ways of getting it wrong — reporting from a test or a screenshot run, and reporting with
/// something that is not the public key — are each caught by a test and not by a stranger turning
/// up in the owner's customer list.
public enum PurchaseReporting {

    /// A public SDK key for an App Store app, or nothing.
    ///
    /// `appl_` is what RevenueCat gives an iOS app. Anything else is turned away, and the case
    /// that matters most is the secret kind (`sk_`), which can read and change the whole project
    /// and must never end up inside a binary that is handed to everybody. A build setting that was
    /// never filled in reaches the bundle as an empty string, or as the literal `$(RC_PUBLIC_API_KEY)`
    /// when the expansion was missed; neither is a key.
    public static func isPublicKey(_ key: String?) -> Bool {
        guard let key, key.hasPrefix("appl_"), key.count > 12 else { return false }
        return key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// Whether this launch reports: it has a real key, and nothing is driving it automatically.
    ///
    /// A screenshot run or a test run is the app being exercised, not used. Counted, it would put
    /// a customer in the charts for every frame of every language, on every run.
    public static func shouldReport(key: String?, isAutomatedRun: Bool) -> Bool {
        isPublicKey(key) && !isAutomatedRun
    }

    /// Whether this process is the app hosting a test run.
    ///
    /// The unit tests run inside the app, so the app really does start up around them and would
    /// otherwise configure RevenueCat from whatever key the build carries.
    public static var isTestRun: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
