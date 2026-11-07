import Testing
@testable import SpotKit

/// What the app is allowed to report to RevenueCat, and from which runs. Both mistakes are
/// quiet ones: a key that is not the public key does nothing visible until it is the secret one,
/// and a test run that reports does nothing visible except fill the owner's charts with people
/// who never existed.
struct PurchaseReportingTests {

    private let publicKey = "appl_AbCdEfGhIjKlMnOpQrStUvWxYz"

    @Test("The key RevenueCat gives an iOS app is accepted")
    func publicKeyIsAccepted() {
        #expect(PurchaseReporting.isPublicKey(publicKey))
    }

    @Test("No key, an empty one and an unexpanded build setting are not keys")
    func missingKeyIsNotAKey() {
        #expect(!PurchaseReporting.isPublicKey(nil))
        #expect(!PurchaseReporting.isPublicKey(""))
        #expect(!PurchaseReporting.isPublicKey("   "))
        #expect(!PurchaseReporting.isPublicKey("$(RC_PUBLIC_API_KEY)"))
        #expect(!PurchaseReporting.isPublicKey("appl_"))
    }

    @Test("A secret key, or any other kind, is never taken for the public one")
    func otherKeysAreTurnedAway() {
        #expect(!PurchaseReporting.isPublicKey("sk_AbCdEfGhIjKlMnOpQrStUvWxYz"))
        #expect(!PurchaseReporting.isPublicKey("goog_AbCdEfGhIjKlMnOpQrStUvWxYz"))
        #expect(!PurchaseReporting.isPublicKey("test_AbCdEfGhIjKlMnOpQrStUvWxYz"))
        #expect(!PurchaseReporting.isPublicKey("appl_AbCdEfGhIj KlMnOp"))
        #expect(!PurchaseReporting.isPublicKey("appl_AbCdEfGhIjKlMnOp\n"))
    }

    @Test("A real run with a key reports")
    func realRunReports() {
        #expect(PurchaseReporting.shouldReport(key: publicKey, isAutomatedRun: false))
    }

    @Test("A test run or a screenshot run stays silent, even with a key")
    func automatedRunStaysSilent() {
        #expect(!PurchaseReporting.shouldReport(key: publicKey, isAutomatedRun: true))
    }

    @Test("A real run with no key has nobody to report to")
    func noKeyNoReport() {
        #expect(!PurchaseReporting.shouldReport(key: nil, isAutomatedRun: false))
        #expect(!PurchaseReporting.shouldReport(key: "", isAutomatedRun: false))
    }
}
