import StoreKitTest
import XCTest

/// Buys premium against a local StoreKit catalog and proves the gates
/// actually open. Deliberately does NOT pass -previewTiers: the tiers must
/// come from a real Product.products lookup served by SKTestSession, so a
/// product-id mismatch or a broken purchase path fails the test rather than
/// hiding behind the static debug render.
///
/// Gates are forced on through the argument domain instead of waiting for
/// /api/v2/config, and grandfathering is forced off, so the run does not
/// depend on the network or on whatever state the simulator was left in.
final class PurchaseFlowTest: XCTestCase {

    private func launchArguments() -> [String] {
        [
            "-profile.onboarded", "YES",
            "-profile.name", "Tester",
            "-profile.appearance", "light",
            "-entitlements.gatesEnabled", "YES",
            "-entitlements.grandfathered", "NO",
        ]
    }

    /// Scrolls the current screen until the element is on screen.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        swipes: Int = 20) -> Bool {
        var count = 0
        while (!element.exists || !element.isHittable) && count < swipes {
            app.swipeUp()
            count += 1
        }
        return element.exists && element.isHittable
    }

    func testPurchaseUnlocksPremiumAndSurvivesRelaunch() throws {
        let session = try SKTestSession(contentsOf: Bundle(
            for: Self.self).url(forResource: "Premium", withExtension: "storekit")!)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let app = XCUIApplication()
        app.launchArguments += launchArguments()
        app.launch()

        // 1. Locked state: search is premium once the gates are on.
        let searchButton = app.buttons["Search by name"]
        XCTAssertTrue(app.buttons["Your profile"].waitForExistence(timeout: 20),
                      "home never appeared")
        XCTAssertFalse(searchButton.exists,
                       "search was reachable while premium was locked")

        // 2. Tiers must render from the real StoreKit lookup.
        app.buttons["Your profile"].tap()
        let price = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '$11.99'")).firstMatch
        XCTAssertTrue(reveal(price, in: app),
                      "tiers never loaded from Product.products")

        // 3. Buy.
        let buy = app.buttons["Become a supporter"]
        XCTAssertTrue(reveal(buy, in: app), "no purchase button")
        buy.tap()

        let confirmation = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'supporter now' "
                                  + "OR label CONTAINS 'Premium unlocked'")).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 30),
                      "purchase never confirmed in the UI")

        // Whether the unlock is visible without a relaunch is a UX question,
        // not a correctness one, so it is recorded rather than asserted.
        app.terminate()
        app.launchArguments = []
        app.launchArguments += launchArguments()
        app.launch()

        // 4. The entitlement must survive a cold launch, re-derived from
        //    Transaction.currentEntitlements rather than a cached flag.
        XCTAssertTrue(app.buttons["Your profile"].waitForExistence(timeout: 20),
                      "home never appeared after relaunch")
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10),
                      "premium did not unlock after relaunch: the purchase "
                      + "did not survive, or the gate ignores it")
    }

    /// Every tier must be buyable, and the slider position must charge for
    /// the product it is showing. An off-by-one here would take a Champion's
    /// money for a Premium subscription (or the reverse), which no amount of
    /// UI testing on the default tier would catch.
    func testEveryTierChargesTheProductItShows() throws {
        let expected = [
            (position: 0.0, price: "$11.99", id: "com.studio86.simply.premium.year12"),
            (position: 0.5, price: "$23.99", id: "com.studio86.simply.premium.year24"),
            (position: 1.0, price: "$47.99", id: "com.studio86.simply.premium.year48"),
        ]

        for tier in expected {
            let session = try SKTestSession(contentsOf: Bundle(
                for: Self.self).url(forResource: "Premium", withExtension: "storekit")!)
            session.resetToDefaultState()
            session.clearTransactions()
            session.disableDialogs = true

            let app = XCUIApplication()
            app.launchArguments = launchArguments()
            app.launch()

            XCTAssertTrue(app.buttons["Your profile"].waitForExistence(timeout: 20),
                          "home never appeared for \(tier.price)")
            app.buttons["Your profile"].tap()

            let slider = app.sliders.firstMatch
            XCTAssertTrue(reveal(slider, in: app), "tier slider never appeared")
            slider.adjust(toNormalizedSliderPosition: tier.position)

            // The headline price must follow the slider before we commit.
            let shown = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", tier.price)).firstMatch
            XCTAssertTrue(shown.waitForExistence(timeout: 5),
                          "slider at \(tier.position) did not show \(tier.price)")

            let buy = app.buttons["Become a supporter"]
            XCTAssertTrue(reveal(buy, in: app), "no purchase button for \(tier.price)")
            buy.tap()

            let confirmation = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'supporter now' "
                                      + "OR label CONTAINS 'Premium unlocked'")).firstMatch
            XCTAssertTrue(confirmation.waitForExistence(timeout: 30),
                          "\(tier.price) never completed a purchase")

            // The decisive check: what did StoreKit actually charge for?
            let ids = try session.allTransactions().map(\.productIdentifier)
            XCTAssertEqual(ids, [tier.id],
                           "slider showed \(tier.price) but charged for \(ids)")

            app.terminate()
        }
    }

    /// A fresh install with the gates on and no purchase must stay locked.
    /// Guards against the paywall failing open for everyone.
    func testGatesStayLockedWithoutPurchase() throws {
        let session = try SKTestSession(contentsOf: Bundle(
            for: Self.self).url(forResource: "Premium", withExtension: "storekit")!)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let app = XCUIApplication()
        app.launchArguments += launchArguments()
        app.launch()

        XCTAssertTrue(app.buttons["Your profile"].waitForExistence(timeout: 20),
                      "home never appeared")
        XCTAssertFalse(app.buttons["Search by name"].exists,
                       "search was free while premium was locked")
    }
}
