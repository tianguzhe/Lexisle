import XCTest

@MainActor
final class WordAtlasUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-onboarding"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testBrowseFavoriteAndStudyJourney() throws {
        let start = app.buttons["开始今日学习"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        capture("01-Today")

        navigate("图鉴")
        let search = app.textFields["atlasSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("library\n")
        let library = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "library")).firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        capture("02-Atlas-Search")
        library.tap()

        let favorite = app.buttons["favoriteWord"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        XCTAssertEqual(favorite.label, "收藏单词")
        favorite.tap()
        XCTAssertEqual(favorite.label, "取消收藏")
        capture("03-Word-Detail")
        let close = app.buttons["关闭词条"]
        if close.exists { close.tap() }

        navigate("收藏")
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        XCTAssertEqual(favorite.label, "取消收藏")
        favorite.tap()
        XCTAssertEqual(favorite.label, "收藏单词")
        if close.exists { close.tap() }

        navigate("今日")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let allTopics = app.buttons["showAllTopics"]
        scrollTo(allTopics, in: app.scrollViews.firstMatch, maximumSwipes: 6)
        capture("08-Today-Topics")
        allTopics.tap()
        XCTAssertTrue(app.buttons["关闭主题列表"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "19 个主题")).firstMatch.exists)
        XCTAssertTrue(app.buttons["topic-education"].exists)
        capture("06-Topic-Library")
        let history = app.buttons["topic-history"]
        scrollTo(history, in: app.scrollViews.firstMatch, maximumSwipes: 12)
        history.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let searchValue = search.value as? String ?? ""
        XCTAssertTrue(
            searchValue.isEmpty || searchValue == search.placeholderValue,
            "Selecting a topic must clear the previous library search")
        XCTAssertTrue(app.buttons["历史"].exists)
        XCTAssertFalse(app.staticTexts["0 个词条"].exists)
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "history，")).firstMatch.waitForExistence(
                timeout: 5))
        capture("07-History-Topic")

        navigate("今日")
        let todayScroll = app.scrollViews.firstMatch
        for _ in 0..<6 where !start.isHittable { todayScroll.swipeDown() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        let intro = app.buttons["认识了，继续"]
        XCTAssertTrue(intro.waitForExistence(timeout: 10))
        capture("04-Study-Introduction")
        for _ in 0..<5 {
            XCTAssertTrue(intro.waitForExistence(timeout: 5))
            intro.tap()
        }
        let answer = app.buttons["answerOption0"]
        XCTAssertTrue(answer.waitForExistence(timeout: 15))
        answer.tap()
        let next = app.buttons["继续"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        capture("05-Study-Feedback")
        next.tap()
        let leave = app.buttons["保存进度并退出学习"]
        XCTAssertTrue(leave.exists)
        leave.tap()
        XCTAssertTrue(app.buttons["继续学习"].waitForExistence(timeout: 5))
    }

    private func navigate(_ title: String) {
        let candidates = app.buttons.matching(NSPredicate(format: "label == %@", title))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 5))
        guard let button = candidates.allElementsBoundByIndex.first(where: \.isHittable) else {
            XCTFail("Navigation control \(title) is covered or unavailable")
            return
        }
        button.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollTo(_ element: XCUIElement, in scrollView: XCUIElement, maximumSwipes: Int) {
        for _ in 0..<maximumSwipes where !element.isHittable { scrollView.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected control to become visible after bounded scrolling")
    }
}
