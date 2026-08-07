import XCTest

@MainActor
final class AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCommonTasksExposeVoiceControlCompatibleElements() throws {
        let home = launch(arguments: ["--preview-settings"])

        XCTAssertTrue(home.buttons["Play together"].isHittable)
        XCTAssertTrue(home.buttons["Join with a code"].isHittable)
        XCTAssertTrue(home.buttons["daily-table-card"].isHittable)
        try auditVoiceControlCompatibility(in: home)

        home.buttons["Join with a code"].tap()
        let partyCode = home.textFields["Party code"]
        XCTAssertTrue(partyCode.waitForExistence(timeout: 2))
        try auditVoiceControlCompatibility(in: home)
        partyCode.typeText("ABCD-EFGH")
        XCTAssertTrue(home.buttons["Join"].isHittable)
        home.buttons["Cancel"].tap()

        openSettings(in: home)
        let languageSettings = home.descendants(matching: .any)
            .matching(identifier: "language-settings-link")
            .firstMatch
        XCTAssertTrue(languageSettings.isHittable)
        XCTAssertTrue(home.switches["sound-effects-toggle"].isHittable)
        XCTAssertTrue(home.switches["daily-reminder-toggle"].isHittable)
        XCTAssertTrue(home.buttons["Log out of Mini Match"].isHittable)
        try auditVoiceControlCompatibility(in: home)
        home.terminate()

        let signedOutHome = launch(arguments: ["--preview-signed-out"])
        XCTAssertTrue(signedOutHome.buttons["Continue with Apple"].waitForExistence(timeout: 5))
        try auditVoiceControlCompatibility(in: signedOutHome)
        signedOutHome.terminate()

        let lobby = launch(arguments: ["--preview-lobby"])
        XCTAssertTrue(lobby.staticTexts["Friday Mini Match"].waitForExistence(timeout: 5))
        XCTAssertTrue(lobby.buttons["Leave"].isHittable)

        let startRound = lobby.buttons["Start round"]
        scrollUntilHittable(startRound, in: lobby)
        XCTAssertTrue(startRound.isHittable)
        startRound.tap()

        let numberField = lobby.textFields["Your number"]
        XCTAssertTrue(numberField.waitForExistence(timeout: 5))
        scrollUntilHittable(numberField, in: lobby)
        XCTAssertTrue(numberField.isHittable)
        numberField.tap()
        numberField.typeText("2")
        let lockNumber = lobby.buttons["Lock my number"]
        scrollUntilHittable(lockNumber, in: lobby)
        XCTAssertTrue(lockNumber.isHittable)
        try auditVoiceControlCompatibility(in: lobby)
        lobby.terminate()

        let result = launch(arguments: ["--preview-result"])
        let resultHeading = result.staticTexts["This round"]
        XCTAssertTrue(resultHeading.waitForExistence(timeout: 5))
        scrollUntilHittable(resultHeading, in: result)
        try auditVoiceControlCompatibility(in: result)
    }

    func testResultShowsTableWinCount() {
        let result = launch(arguments: ["--preview-result"])
        let row = result.descendants(matching: .any)
            .matching(identifier: "result-row-liam")
            .firstMatch

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Liam, win count 5, selected 5, Winner")
    }

    func testDailyTableExposesPrivateSubmittedStateAndYesterdayResult() throws {
        let daily = launch(arguments: ["--preview-daily"])

        XCTAssertTrue(daily.staticTexts["Daily Table"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: "daily-previous-result", in: daily).exists)
        XCTAssertTrue(element(identifier: "daily-today-card", in: daily).exists)
        XCTAssertTrue(daily.staticTexts["Winning number: 3"].exists)
        XCTAssertTrue(daily.staticTexts["You won!"].exists)
        XCTAssertTrue(daily.staticTexts["Locked for today"].exists)
        XCTAssertFalse(daily.textFields["Your daily number"].exists)
        try auditVoiceControlCompatibility(in: daily)

        let leaderboard = daily.buttons["daily-wins-link"]
        scrollUntilHittable(leaderboard, in: daily)
        XCTAssertTrue(leaderboard.isHittable)
        leaderboard.tap()
        XCTAssertTrue(daily.staticTexts["Daily Wins"].waitForExistence(timeout: 5))
    }

    func testCommonScreensPassSufficientContrastAuditInLightAppearance() throws {
        try withAppearance(.light) {
            try auditCommonScreens(appearance: .light)
        }
    }

    func testCommonScreensPassSufficientContrastAuditInDarkInterface() throws {
        try withAppearance(.dark) {
            try auditCommonScreens(appearance: .dark)
        }
    }

    private func auditCommonScreens(appearance: XCUIDevice.Appearance) throws {
        continueAfterFailure = true
        defer { continueAfterFailure = false }

        let home = launch(arguments: ["--preview-settings"])
        XCTAssertTrue(home.buttons["Play together"].waitForExistence(timeout: 5))
        let appearanceIdentifier = appearance == .dark
            ? "brand-header-dark"
            : "brand-header-light"
        XCTAssertTrue(element(identifier: appearanceIdentifier, in: home).exists)
        try auditContrast(in: home, screen: "Home", appearance: appearance)

        openSettings(in: home)
        try auditContrast(in: home, screen: "Settings", appearance: appearance)
        home.terminate()

        let signedOutHome = launch(arguments: ["--preview-signed-out"])
        XCTAssertTrue(signedOutHome.buttons["Continue with Apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: appearanceIdentifier, in: signedOutHome).exists)
        try auditContrast(
            in: signedOutHome,
            screen: "Signed-out-home",
            appearance: appearance
        )
        signedOutHome.terminate()

        let lobby = launch(arguments: ["--preview-lobby"])
        XCTAssertTrue(lobby.staticTexts["Friday Mini Match"].waitForExistence(timeout: 5))
        try auditContrast(in: lobby, screen: "Lobby", appearance: appearance)

        let startRound = lobby.buttons["Start round"]
        scrollUntilHittable(startRound, in: lobby)
        XCTAssertTrue(startRound.isHittable)
        startRound.tap()
        let numberField = lobby.textFields["Your number"]
        XCTAssertTrue(numberField.waitForExistence(timeout: 5))
        scrollUntilHittable(numberField, in: lobby)
        try auditContrast(in: lobby, screen: "Active-round", appearance: appearance)
        lobby.terminate()

        let result = launch(arguments: ["--preview-result"])
        let resultHeading = result.staticTexts["This round"]
        XCTAssertTrue(resultHeading.waitForExistence(timeout: 5))
        scrollUntilHittable(resultHeading, in: result)
        try auditContrast(in: result, screen: "Result", appearance: appearance)
        result.terminate()

        let daily = launch(arguments: ["--preview-daily"])
        XCTAssertTrue(daily.staticTexts["Daily Table"].waitForExistence(timeout: 5))
        try auditContrast(in: daily, screen: "Daily-table", appearance: appearance)
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        let launchArguments = arguments + [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launchArguments = launchArguments
        app.launch()
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let profile = app.buttons["Profile for Maya"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Game settings"].waitForExistence(timeout: 2))
    }

    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func withAppearance(
        _ appearance: XCUIDevice.Appearance,
        operation: () throws -> Void
    ) rethrows {
        let device = XCUIDevice.shared
        let originalAppearance = device.appearance
        device.appearance = appearance
        defer { device.appearance = originalAppearance }
        try operation()
    }

    private func auditVoiceControlCompatibility(in app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .trait,
        ]) { issue in
            self.isDecorative(issue.element)
                || self.isSystemKeyboardPrediction(issue)
        }
    }

    private func auditContrast(
        in app: XCUIApplication,
        screen: String,
        appearance: XCUIDevice.Appearance
    ) throws {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(screen)-\(appearance == .dark ? "dark" : "light")"
        attachment.lifetime = .keepAlways
        add(attachment)

        try app.performAccessibilityAudit(for: .contrast) { issue in
            self.isDecorative(issue.element)
        }
    }

    private func isDecorative(_ element: XCUIElement?) -> Bool {
        guard let identifier = element?.identifier else { return false }
        return identifier == "decorative-home-number"
            || identifier == "decorative-player-avatar"
    }

    private func isSystemKeyboardPrediction(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.detailedDescription.contains("TUIPredictionViewCell")
    }
}
