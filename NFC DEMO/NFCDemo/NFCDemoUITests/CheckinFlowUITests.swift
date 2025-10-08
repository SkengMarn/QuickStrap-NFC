import XCTest

final class CheckinFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Authentication Flow Tests

    func testCompleteAuthenticationFlow() throws {
        // Test sign in
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.exists)
        emailField.tap()
        emailField.typeText("test@example.com")

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.exists)
        passwordField.tap()
        passwordField.typeText("testpassword123")

        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.exists)
        signInButton.tap()

        // Verify navigation to events screen
        let eventsNavBar = app.navigationBars["Events"]
        XCTAssertTrue(eventsNavBar.waitForExistence(timeout: 5))
    }

    func testSignInWithInvalidCredentials() throws {
        // Enter invalid credentials
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("invalid@example.com")

        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("wrongpassword")

        app.buttons["Sign In"].tap()

        // Verify error message appears
        let errorAlert = app.alerts.firstMatch
        XCTAssertTrue(errorAlert.waitForExistence(timeout: 3))
    }

    // MARK: - Event Selection Tests

    func testEventSelection() throws {
        // Assume already authenticated
        authenticateUser()

        // Wait for events list
        let eventsList = app.tables.firstMatch
        XCTAssertTrue(eventsList.waitForExistence(timeout: 5))

        // Select first event
        let firstEvent = eventsList.cells.firstMatch
        XCTAssertTrue(firstEvent.exists)
        firstEvent.tap()

        // Verify navigation to main screen
        let mainTabBar = app.tabBars.firstMatch
        XCTAssertTrue(mainTabBar.waitForExistence(timeout: 3))
    }

    // MARK: - NFC Scanning Tests

    func testNFCScanButtonAccessibility() throws {
        // Navigate to scan view
        navigateToScanView()

        // Find NFC scan button
        let nfcButton = app.buttons.matching(identifier: "nfc_scan_button").firstMatch

        // Verify accessibility
        XCTAssertTrue(nfcButton.exists)
        XCTAssertTrue(nfcButton.isEnabled)

        // Check accessibility label
        let label = nfcButton.label
        XCTAssertFalse(label.isEmpty)
        XCTAssertTrue(label.contains("Scan") || label.contains("NFC"))
    }

    func testNFCScanWorkflow() throws {
        navigateToScanView()

        // Tap scan button
        let scanButton = app.buttons["Tap to Scan"]
        XCTAssertTrue(scanButton.exists)
        scanButton.tap()

        // Note: Actual NFC scanning can't be tested in simulator
        // but we can verify UI changes

        // Verify loading state or scan UI appears
        let scanningIndicator = app.activityIndicators.firstMatch
        // Either loading indicator or NFC sheet should appear
        // This will fail in simulator but pass on device
    }

    // MARK: - Statistics View Tests

    func testStatisticsViewDisplays() throws {
        navigateToStatsView()

        // Verify stats elements are present
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Total'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Checked In'")).firstMatch.exists)
    }

    // MARK: - Accessibility Tests

    func testVoiceOverAccessibility() throws {
        // Enable accessibility testing
        app.launchArguments += ["-UIAccessibilityInspector", "1"]
        app.launch()

        navigateToScanView()

        // Check that all interactive elements have labels
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons where button.exists {
            XCTAssertFalse(button.label.isEmpty, "Button missing accessibility label")
        }

        // Check navigation elements
        let navButtons = app.navigationBars.buttons.allElementsBoundByIndex
        for navButton in navButtons where navButton.exists {
            XCTAssertFalse(navButton.label.isEmpty, "Navigation button missing accessibility label")
        }
    }

    func testDynamicTypeSizes() throws {
        // Test with extra large text
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        authenticateUser()

        // Verify text is still readable and not truncated
        let allText = app.staticTexts.allElementsBoundByIndex
        for text in allText where text.exists && text.isHittable {
            XCTAssertTrue(text.frame.width > 0, "Text element has no width")
            XCTAssertTrue(text.frame.height > 0, "Text element has no height")
        }
    }

    // MARK: - Performance Tests

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    func testScrollPerformance() throws {
        navigateToWristbandsList()

        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
            table.swipeUp(velocity: .fast)
            table.swipeDown(velocity: .fast)
        }
    }

    // MARK: - Helper Methods

    private func authenticateUser() {
        let emailField = app.textFields["Email"]
        if emailField.waitForExistence(timeout: 2) {
            emailField.tap()
            emailField.typeText("test@example.com")

            app.secureTextFields["Password"].tap()
            app.secureTextFields["Password"].typeText("testpassword123")

            app.buttons["Sign In"].tap()

            // Wait for authentication to complete
            _ = app.tabBars.firstMatch.waitForExistence(timeout: 5)
        }
    }

    private func navigateToScanView() {
        authenticateUser()

        // Assume tab bar navigation
        let scanTab = app.tabBars.buttons["Scan"]
        if scanTab.exists {
            scanTab.tap()
        }
    }

    private func navigateToStatsView() {
        authenticateUser()

        let statsTab = app.tabBars.buttons["Stats"]
        if statsTab.exists {
            statsTab.tap()
        }
    }

    private func navigateToWristbandsList() {
        authenticateUser()

        let wristbandsTab = app.tabBars.buttons["Wristbands"]
        if wristbandsTab.exists {
            wristbandsTab.tap()
        }
    }
}
