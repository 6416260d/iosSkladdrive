import XCTest

final class StoreScreens: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "ru.mise.courier")

    private func button(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func label(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func require(_ element: XCUIElement, _ description: String, timeout: TimeInterval = 45) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(description). Visible buttons: \(app.buttons.allElementsBoundByIndex.prefix(12).map { $0.label })")
    }

    func testDemoScreens() throws {
        continueAfterFailure = false
        app.launch()
        let demo = button("Демо")
        require(demo, "Demo workspace selector")
        demo.tap()
        let start = button("Войти в демо")
        require(start, "Demo sign-in")
        start.tap()
        let order = button("Забрать в доставку")
        require(order, "Seeded order in the new workspace", timeout: 180)
        try save("01-orders")
        let history = button("История")
        require(history, "Delivery history")
        history.tap()
        let week = button("7 дней")
        require(week, "History date range")
        week.tap()
        require(label("Доставлено:"), "Historical deliveries have loaded")
        try save("02-history")
        let logout = button("Выйти")
        if logout.exists {
            logout.tap()
            let yes = app.alerts.buttons["Да"]
            if yes.waitForExistence(timeout: 5) { yes.tap() }
        }
    }

    private func save(_ name: String) throws {
        let dir = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
    }
}
