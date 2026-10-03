import XCTest

final class WikiTourUITests: XCTestCase {
    @MainActor
    func testBookmarkPersistsAndCanBeRemoved() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--detail", "--ui-testing", "--reset-saved"]
        app.launch()
        let bookmark = app.buttons["bookmarkPlace"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        XCTAssertEqual(bookmark.label, "Save place")
        XCTAssertEqual(bookmark.frame.maxX, app.frame.maxX - 10, accuracy: 1)
        XCTAssertFalse(app.buttons["Close place"].exists)
        capture(app, name: "Place card")
        app.buttons["Sheet size"].tap()
        capture(app, name: "Expanded place introduction spacing")
        app.buttons["Sheet size"].tap()
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Remove saved place")
        capture(app, name: "Solid saved bookmark")
        dismissPlace(app)
        app.buttons["savedWalks"].tap()
        XCTAssertTrue(app.staticTexts["0 saved walks"].waitForExistence(timeout: 5))
        app.buttons["savedPlaces"].tap()
        XCTAssertTrue(app.staticTexts["Saved places"].waitForExistence(timeout: 5))
        capture(app, name: "Saved places")
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "14th Regiment Armory").firstMatch.exists)
        app.terminate()
        app.launchArguments = ["--preview", "--detail", "--ui-testing"]
        app.launch()
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        XCTAssertEqual(bookmark.label, "Remove saved place")
        bookmark.tap()
        XCTAssertEqual(bookmark.label, "Save place")
        dismissPlace(app)
        app.buttons["savedWalks"].tap()
        XCTAssertTrue(app.staticTexts["0 saved walks"].waitForExistence(timeout: 5))
        app.buttons["savedPlaces"].tap()
        XCTAssertTrue(app.staticTexts["A walk of your own"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWalkingTourBackNextKeepGoingAndClear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ui-testing", "--reset-saved", "--saved-preview"]
        app.launch()
        app.buttons["savedWalks"].tap()
        app.buttons["savedPlaces"].tap()
        let start = app.buttons["startWalking"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let title = app.staticTexts["currentStopTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "14th Regiment Armory")
        capture(app, name: "Walking tour")
        XCTAssertFalse(app.buttons["← Back"].isEnabled)
        app.buttons["nextStop"].tap()
        XCTAssertEqual(title.label, "Grand Prospect Hall")
        XCTAssertFalse(app.staticTexts["No photo available"].exists)
        capture(app, name: "Emoji-only photo placeholder")
        app.buttons["← Back"].tap()
        XCTAssertEqual(title.label, "14th Regiment Armory")
        app.buttons["nextStop"].tap()
        // The last stop offers more places instead of ending the walk.
        XCTAssertEqual(app.buttons["nextStop"].label, "Keep going →")
        app.buttons["nextStop"].tap()
        let next = app.buttons["nextStop"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(NSPredicate(format: "value BEGINSWITH 'Stop 3 of '").evaluate(with: next), next.value as? String ?? "")
        XCTAssertNotEqual(title.label, "Grand Prospect Hall")
        capture(app, name: "Keep going")
        // The check button ends the walk.
        app.buttons["walkAction"].firstMatch.tap()
        XCTAssertTrue(app.buttons["savedWalks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tourSummary"].exists)
        XCTAssertFalse(app.buttons["Sheet size"].exists)
        app.terminate()
        app.launchArguments = ["--preview", "--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["savedWalks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tourSummary"].exists)
    }

    @MainActor
    func testEdgeToEdgeSheetResizesWithoutOverlappingSummary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ui-testing", "--reset-saved", "--saved-preview"]
        app.launch()
        app.buttons["savedWalks"].tap()
        app.buttons["savedPlaces"].tap()
        let start = app.buttons["startWalking"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.buttons["nextStop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tourSummary"].exists)
        let surface = app.otherElements["edgeToEdgeSheet"].firstMatch
        XCTAssertTrue(surface.exists)
        XCTAssertEqual(surface.frame.minX, app.frame.minX, accuracy: 1)
        XCTAssertEqual(surface.frame.width, app.frame.width, accuracy: 1)
        let handle = app.buttons["Sheet size"]
        XCTAssertTrue(handle.exists)
        handle.tap()
        XCTAssertFalse(app.buttons["nextStop"].exists)
        XCTAssertFalse(app.buttons["tourSummary"].exists)
        capture(app, name: "Collapsed edge-to-edge tour")
        handle.tap()
        XCTAssertTrue(app.buttons["nextStop"].waitForExistence(timeout: 5))
        capture(app, name: "Expanded edge-to-edge tour")

        // Start away from the tiny visual capsule to exercise the enlarged hit area.
        // Repeated real drags catch moving-coordinate feedback and release snap-back.
        for _ in 0..<2 {
            let grab = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            grab.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.94)), withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertTrue(handle.waitForExistence(timeout: 3))
            XCTAssertEqual(handle.value as? String, "Collapsed")
            XCTAssertFalse(app.buttons["tourSummary"].exists)
            let lowerGrab = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            lowerGrab.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertEqual(handle.value as? String, "Expanded")
            XCTAssertTrue(app.buttons["nextStop"].exists)
            XCTAssertEqual(surface.frame.maxY, app.frame.maxY, accuracy: 1)
        }
        capture(app, name: "Tour after repeated drawer drags")
    }

    @MainActor
    func testCheckClearsCurrentRouteAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ui-testing", "--reset-saved", "--saved-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["tourSummary"].waitForExistence(timeout: 10))
        app.buttons["tourSummary"].tap()
        if app.buttons["startWalking"].waitForExistence(timeout: 2) {
            app.buttons["startWalking"].tap()
        }
        XCTAssertTrue(app.buttons["walkAction"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["walkAction"].label, "Clear current route")
        app.buttons["walkAction"].tap()
        XCTAssertFalse(app.buttons["Sheet size"].exists)
        XCTAssertFalse(app.buttons["tourSummary"].exists)
        app.terminate()
        app.launchArguments = ["--preview", "--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["savedWalks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tourSummary"].exists)
    }

    @MainActor
    func testSaveWalkReopenAndToggleHeartAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ui-testing", "--reset-saved", "--saved-preview"]
        app.launch()
        app.buttons["savedWalks"].tap()
        app.buttons["savedPlaces"].tap()
        XCTAssertTrue(app.buttons["startWalking"].waitForExistence(timeout: 10))
        app.buttons["startWalking"].tap()
        XCTAssertTrue(app.staticTexts["currentStopTitle"].waitForExistence(timeout: 5))
        app.buttons["saveWalk"].tap()
        XCTAssertTrue(app.buttons["Unsave walk"].waitForExistence(timeout: 5))
        capture(app, name: "Saved walk detail")
        app.terminate()
        app.launchArguments = ["--preview", "--ui-testing"]
        app.launch()
        app.buttons["savedWalks"].tap()
        XCTAssertTrue(app.staticTexts["1 saved walk"].waitForExistence(timeout: 5))
        capture(app, name: "Saved walks gallery")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'savedWalk-'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["currentStopTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["saveWalk"].label, "Unsave walk")
        app.buttons["saveWalk"].tap()
        XCTAssertEqual(app.buttons["saveWalk"].label, "Save walk")
        XCTAssertTrue(app.staticTexts["currentStopTitle"].exists)
        app.buttons["savedWalks"].tap()
        XCTAssertTrue(app.staticTexts["0 saved walks"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.buttons["savedWalks"].tap()
        XCTAssertTrue(app.staticTexts["0 saved walks"].waitForExistence(timeout: 5))
        app.buttons["savedPlaces"].tap()
        XCTAssertTrue(app.buttons["startWalking"].waitForExistence(timeout: 10))
        app.buttons["startWalking"].tap()
        XCTAssertTrue(app.staticTexts["currentStopTitle"].waitForExistence(timeout: 5))
        app.buttons["saveWalk"].tap()
        XCTAssertEqual(app.buttons["saveWalk"].label, "Unsave walk")
        XCTAssertEqual(app.buttons["walkAction"].label, "Clear current route")
        XCTAssertFalse(app.buttons["Delete walk"].exists)
        app.buttons["saveWalk"].tap()
        XCTAssertEqual(app.buttons["saveWalk"].label, "Save walk")
        app.buttons["walkAction"].tap()
        XCTAssertFalse(app.buttons["tourSummary"].exists)
        app.terminate()
        app.launch()
        app.buttons["savedWalks"].tap()
        XCTAssertTrue(app.staticTexts["0 saved walks"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCollapsedTourBarCoversBottomSafeArea() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ui-testing", "--reset-saved", "--saved-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["tourSummary"].waitForExistence(timeout: 10))
        let panel = app.otherElements["mapBottomPanel"].firstMatch
        XCTAssertTrue(panel.exists)
        XCTAssertEqual(panel.frame.minX, app.frame.minX, accuracy: 1)
        XCTAssertEqual(panel.frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, app.frame.maxY, accuracy: 1)
        capture(app, name: "Tour summary covers bottom safe area")
    }

    @MainActor
    private func dismissPlace(_ app: XCUIApplication) {
        let handle = app.buttons["Sheet size"]
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertTrue(app.buttons["bookmarkPlace"].waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
