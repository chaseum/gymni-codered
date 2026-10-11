import XCTest

extension XCUIApplication {
    /// Launches, then waits for the boot animation to slide away so the first tap reaches Today.
    func launchPastIntro() {
        launch()
        _ = buttons["Gym&I. Tap to continue."].waitForNonExistence(timeout: 5)
    }
}
