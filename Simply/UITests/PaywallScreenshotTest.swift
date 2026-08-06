import StoreKitTest
import XCTest

/// Drives the app to the Support card and captures the pay-what-you-want
/// tiers rendered from the local StoreKit catalog. Doubles as the source of
/// the App Store review screenshot for the subscription products:
/// /tmp/simply-paywall.png.
final class PaywallScreenshotTest: XCTestCase {

    func testSupportCardShowsTiers() throws {
        // Local StoreKit environment for the target app, from the same
        // catalog the Simply scheme uses for manual runs.
        let session = try SKTestSession(contentsOf: Bundle(
            for: Self.self).url(forResource: "Premium", withExtension: "storekit")!)
        session.resetToDefaultState()
        session.disableDialogs = true

        let app = XCUIApplication()
        // Registered-defaults launch arguments skip onboarding.
        app.launchArguments += [
            "-profile.onboarded", "YES",
            "-profile.name", "Tester",
            "-profile.appearance", "light",
            "-previewTiers",
        ]
        app.launch()

        let avatar = app.buttons["Your profile"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 15), "home never appeared")
        avatar.tap()

        let price = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '$11.99'")).firstMatch
        var swipes = 0
        while (!price.exists || !price.isHittable) && swipes < 20 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(price.waitForExistence(timeout: 10), "tier prices did not render")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '$47.99'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Restore purchases"].exists)

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(
            to: URL(fileURLWithPath: "/tmp/simply-paywall.png"))
    }
}
