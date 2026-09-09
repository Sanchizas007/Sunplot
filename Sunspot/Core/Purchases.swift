import StoreKit
import Observation
import SpotKit
import WidgetKit

/// One thing to buy, once, for good.
///
/// No RevenueCat: a single non-consumable is a hundred lines of StoreKit, and a service that
/// takes a percentage of every sale for the rest of the app's life is a strange price to pay
/// for that.
@MainActor
@Observable
final class Purchases {

    /// Outside the actor: it is a constant, and both the paywall and the tests that guard the
    /// configuration file need to name it from wherever they happen to be.
    nonisolated static let productID = "app.sunplot.full"

    enum State: Equatable {
        /// Still asking the store.
        case loading
        /// Not bought, and here is what it costs.
        case locked(price: String)
        /// Bought. Everything is open.
        case unlocked
        /// The store could not be reached. Treated as locked, but said differently — this is
        /// a bad aeroplane connection, not a refusal.
        case unavailable
    }

    private(set) var state: State = .loading {
        didSet {
            guard oldValue != state else { return }
            // The widget cannot ask the App Store from inside its own timeline, so it is told.
            if let known = Self.cachedUnlock(for: state) {
                Unlock.record(isUnlocked: known)
            }
            WidgetRefresh.reload()
        }
    }

    /// What the widget's cached answer should become, or nil when this state is not an answer.
    ///
    /// `.unavailable` is the one that matters. It means the App Store could not be reached,
    /// which is not the same thing as "not bought" — and writing `false` for it takes the
    /// widget away from somebody who has paid, because their train went into a tunnel. The
    /// flag is a cache of the last thing actually known, so a state that knows nothing leaves
    /// it exactly as it was.
    static func cachedUnlock(for state: State) -> Bool? {
        switch state {
        case .unlocked: true
        case .locked: false
        case .loading, .unavailable: nil
        }
    }
    private(set) var isWorking = false
    private(set) var lastError: String?

    var isUnlocked: Bool { state == .unlocked }

    private var product: Product?
    /// Kept out of observation and off the actor. Nothing watches it, and `deinit` belongs to
    /// no actor yet still has to cancel it; a `Task` is `Sendable`, so nothing is being
    /// smuggled past the compiler here.
    @ObservationIgnored
    private nonisolated(unsafe) var updates: Task<Void, Never>?

    /// Begins listening for purchases that arrive without a button being pressed: one
    /// finished on another device, or an interrupted one the system resumes later.
    ///
    /// Deliberately not done in `init`. `Transaction.updates` never ends, and an object that
    /// starts an endless task the moment it is created cannot be built in a test without
    /// leaving that task running behind it — which is exactly how a two-second suite turned
    /// into one that never finished.
    func startListening() {
        // A screenshot run has no store to listen to, and an endless task started for a
        // single frame would outlive it.
        guard Demo.pretendedPurchase == nil, updates == nil else { return }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard case let .verified(transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    func stopListening() {
        updates?.cancel()
        updates = nil
    }

    deinit { updates?.cancel() }

    /// Asks the store what is on sale and whether it has already been bought.
    func load() async {
        // The screenshot run never touches the screen, so it can neither buy this nor be
        // shown a paywall that reached a real store. It is told the answer instead.
        if let pretended = Demo.pretendedPurchase {
            switch pretended {
            case .unlocked: state = .unlocked
            case .locked(let price): state = .locked(price: price)
            }
            return
        }

        await refreshEntitlement()
        guard state != .unlocked else { return }

        do {
            let products = try await Product.products(for: [Self.productID])
            guard let found = products.first else {
                // Both failures below land the person on the same "can't reach the store"
                // message, and from the screen they are indistinguishable — but they mean
                // opposite things. An empty list is the store answering that it has never
                // heard of this product; a thrown error is not reaching the store at all.
                // Worth saying out loud where a developer can read it.
                log("вернулся пустой список: магазин не знает товар \(Self.productID)")
                state = .unavailable
                return
            }
            product = found
            state = .locked(price: found.displayPrice)
            log("товар получен: \(found.id) за \(found.displayPrice)")
        } catch {
            log("запрос к магазину не прошёл: \(error)")
            state = .unavailable
        }
    }

    /// Only in a debug build, and only to the console — nothing is collected or sent.
    private nonisolated func log(_ message: String) {
        #if DEBUG
        print("[Purchases] \(message)")
        #endif
    }

    func buy() async {
        guard let product, !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case let .verified(transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                } else {
                    lastError = String(localized: "That purchase could not be verified. Nothing has been charged.")
                }
            case .userCancelled:
                break
            case .pending:
                // Ask-to-buy and similar: the answer arrives later through Transaction.updates.
                lastError = String(localized: "Waiting for approval. It will unlock as soon as that comes through.")
            @unknown default:
                break
            }
        } catch {
            lastError = String(localized: "The purchase did not go through. Nothing has been charged.")
        }
    }

    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if state != .unlocked {
                lastError = String(localized: "No earlier purchase found on this Apple Account.")
            }
        } catch {
            lastError = String(localized: "Could not reach the store to check. Try again in a moment.")
        }
    }

    /// The single source of truth about whether this is paid for.
    private func refreshEntitlement() async {
        for await entitlement in Transaction.currentEntitlements {
            guard case let .verified(transaction) = entitlement,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil
            else { continue }
            state = .unlocked
            return
        }
        // Not entitled. Leave a known price in place rather than dropping back to loading.
        if case .unlocked = state { state = .loading }
    }
}
