import Foundation
import XCTest

@testable import WordAtlas

@MainActor
final class PersistenceBoundaryTests: XCTestCase {
    func testInvalidIncomingBatchCannotPoisonSavedHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let valid = LearningEvent(
            id: "valid", wordID: "library", sessionID: "one", date: date,
            rating: 3, correct: true, isNew: true, duration: 2)
        let invalid = LearningEvent(
            id: "invalid", wordID: "library", sessionID: "two", date: date.addingTimeInterval(600),
            rating: 99, correct: false, isNew: false, duration: 2)
        let favorite = LearningOperation(
            id: "rejected-favorite", date: date,
            payload: .favorite(FavoriteChange(wordID: "forest", isFavorite: true)))
        do {
            let store = try AppStore(storageDirectory: directory)
            try store.merge([LearningOperation(id: valid.id, date: valid.date, payload: .review(valid))])
            let previous = store.cards
            XCTAssertThrowsError(
                try store.merge([
                    favorite, LearningOperation(id: invalid.id, date: invalid.date, payload: .review(invalid)),
                ]))
            XCTAssertEqual(store.cards, previous)
            XCTAssertEqual(store.exportedOperations().map(\.id), ["valid"])
            XCTAssertFalse(store.favorites.contains("forest"))
        }
        let reopened = try AppStore(storageDirectory: directory)
        XCTAssertEqual(reopened.reviewEvents.map(\.id), ["valid"])
        XCTAssertFalse(reopened.favorites.contains("forest"))
        reopened.toggleFavorite("library")
        XCTAssertNil(reopened.errorMessage)
        XCTAssertTrue(reopened.favorites.contains("library"))
    }

    func testNotificationObservationUnregistersWhenReleased() {
        let center = NotificationCenter()
        let name = Notification.Name("WordAtlasObservationTest")
        let received = expectation(description: "One notification before token release")
        received.assertForOverFulfill = true
        var observation: NotificationObservation? = NotificationObservation(
            token: center.addObserver(
                forName: name, object: nil, queue: nil
            ) { _ in received.fulfill() }, center: center)
        XCTAssertNotNil(observation)
        center.post(name: name, object: nil)
        observation = nil
        center.post(name: name, object: nil)
        wait(for: [received], timeout: 1)
    }
}

final class LearningStatisticsTests: XCTestCase {
    func testLocalDaysAndStreakSpanDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        let dates = try ["2026-10-31T20:00:00Z", "2026-11-01T20:00:00Z", "2026-11-02T20:00:00Z"].map {
            try XCTUnwrap(formatter.date(from: $0))
        }
        let events = dates.enumerated().map { index, date in
            LearningEvent(
                id: "event-\(index)", wordID: "library", sessionID: "session-\(index)", date: date,
                rating: 3, correct: true, isNew: index == 0, duration: 2)
        }
        let statistics = LearningStatistics(events: events.reversed())
        let activity = statistics.activity(days: 3, endingOn: dates[2], calendar: calendar)
        XCTAssertEqual(statistics.streak(through: dates[2], calendar: calendar), 3)
        XCTAssertEqual(activity.map(\.reviewed), [1, 1, 1])
        XCTAssertEqual(activity.map(\.newWords), [1, 0, 0])
        XCTAssertEqual(activity[2].date.timeIntervalSince(activity[1].date), 25 * 3600)
        XCTAssertEqual(statistics.newWordCount(on: dates[2], calendar: calendar), 0)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: dates[2]))
        XCTAssertEqual(statistics.streak(through: tomorrow, calendar: calendar), 3)
    }
}

final class AppConfigurationTests: XCTestCase {
    func testCloudFlagAcceptsPropertyListAndXCConfigRepresentations() {
        XCTAssertTrue(AppConfiguration(info: ["WordAtlasCloudEnabled": true], arguments: []).cloudEnabled)
        XCTAssertTrue(AppConfiguration(info: ["WordAtlasCloudEnabled": " YES "], arguments: []).cloudEnabled)
        XCTAssertFalse(AppConfiguration(info: ["WordAtlasCloudEnabled": "NO"], arguments: []).cloudEnabled)
        XCTAssertFalse(AppConfiguration(info: [:], arguments: []).cloudEnabled)
        XCTAssertFalse(AppConfiguration(info: ["WordAtlasCloudEnabled": "$(UNSET)"], arguments: []).cloudEnabled)
    }

    func testUITestingConfigurationUsesMemoryOnEveryStartupAttempt() {
        let configuration = AppConfiguration(info: [:], arguments: ["WordAtlas", "--ui-testing", "--skip-onboarding"])
        #if DEBUG
        XCTAssertTrue(configuration.usesInMemoryStore)
        XCTAssertTrue(configuration.skipsOnboarding)
        #else
        XCTAssertFalse(configuration.usesInMemoryStore)
        XCTAssertFalse(configuration.skipsOnboarding)
        #endif
    }
}
