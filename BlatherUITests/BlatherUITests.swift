import XCTest

final class BlatherUITests: XCTestCase {
    private var dataDir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDir = FileManager.default.temporaryDirectory.appendingPathComponent("blather-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dataDir {
            try? FileManager.default.removeItem(at: dataDir)
        }
    }

    @MainActor
    func testLaunchShowsCompose() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Compose"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["sidebar-compose"].waitForExistence(timeout: 5)
            || app.buttons["Compose"].exists
            || app.staticTexts["Compose"].exists)
    }

    @MainActor
    func testComposePublishPartialFailureAndRetry() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Compose"].waitForExistence(timeout: 8))

        let editor = app.textViews["post-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("ui test post \(Int(Date().timeIntervalSince1970))")

        for id in [
            "destination-mock-x",
            "destination-mock-x-2",
            "destination-mock-bluesky",
            "destination-mock-instagram",
        ] {
            let toggle = app.descendants(matching: .any)[id]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Missing destination control \(id)")
            toggle.click()
        }

        let publish = app.buttons["publish"]
        XCTAssertTrue(publish.waitForExistence(timeout: 5))
        XCTAssertTrue(publish.isEnabled)
        publish.click()

        let progress = app.staticTexts["publish-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["publish-progress-mock-instagram"].waitForExistence(timeout: 10))

        let done = app.buttons["publish-progress-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        done.click()

        let results = app.staticTexts["publish-results"]
        XCTAssertTrue(results.waitForExistence(timeout: 10))

        let historyItem = app.descendants(matching: .any)["sidebar-history"]
        if historyItem.waitForExistence(timeout: 5) {
            historyItem.click()
        } else {
            app.buttons["History"].click()
        }

        let retry = app.buttons["retry-mock-instagram"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.click()

        let retryDone = app.buttons["publish-progress-done"]
        XCTAssertTrue(retryDone.waitForExistence(timeout: 10))
        let retryEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: retryDone
        )
        XCTAssertEqual(XCTWaiter.wait(for: [retryEnabled], timeout: 15), .completed)
        retryDone.click()
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-mockProviders"]
        app.launchEnvironment = [
            "BLATHER_DATA_DIR": dataDir.path,
            "BLATHER_MOCK_PROVIDERS": "1",
        ]
        app.launch()
        return app
    }
}
