import XCTest

final class StoreScreens: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "ru.mise.courier")

    func testDemoScreens() throws {
        continueAfterFailure = false
        app.launch()
        let demo = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Демо")).first
        XCTAssertTrue(demo.waitForExistence(timeout: 20))
        demo.tap()
        let start = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Войти в демо")).first
        XCTAssertTrue(start.waitForExistence(timeout: 60))
        start.tap()
        let history = app.buttons["История"]
        XCTAssertTrue(history.waitForExistence(timeout: 150))
        let week = app.buttons["7 дней"]
        history.tap()
        XCTAssertTrue(week.waitForExistence(timeout: 20))
        week.tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Демо-Химки"))
        XCTAssertTrue(rows.first.waitForExistence(timeout: 45))
        let loaded = NSPredicate { _, _ in
            !self.app.staticTexts["Загружаю…"].exists && !self.app.staticTexts["Доставленных заказов нет"].exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 45), .completed)
        try save("02-history")
        let open = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Открытые")).first
        open.tap()
        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Готовые заказы доставки")).first
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        try save("01-orders")
        let logout = app.buttons["Выйти"]
        if logout.exists {
            logout.tap()
            let yes = app.alerts.buttons["Да"]
            if yes.waitForExistence(timeout: 4) { yes.tap() }
        }
    }

    private func save(_ name: String) throws {
        let dir = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }
}
