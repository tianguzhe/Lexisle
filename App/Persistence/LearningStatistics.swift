import Foundation

/// Calendar-dependent statistics stay separate from storage and scheduling.
struct LearningStatistics {
    private let events: [LearningEvent]
    private let firstReviews: [LearningEvent]

    init(events: [LearningEvent]) {
        self.events = events
        var firstByWord: [String: LearningEvent] = [:]
        for event in events {
            if let first = firstByWord[event.wordID], first.date <= event.date { continue }
            firstByWord[event.wordID] = event
        }
        firstReviews = Array(firstByWord.values)
    }

    func reviews(on date: Date = Date(), calendar: Calendar = .current) -> [LearningEvent] {
        events.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func newWordCount(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        firstReviews.filter { $0.date <= date && calendar.isDate($0.date, inSameDayAs: date) }.count
    }

    func streak(through date: Date = Date(), calendar: Calendar = .current) -> Int {
        let activeDays = Set(events.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: date)
        if !activeDays.contains(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while activeDays.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    func activity(days: Int, endingOn date: Date = Date(), calendar: Calendar = .current) -> [ActivityDay] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: date)
        let reviewsByDay = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        let firstReviewsByDay = Dictionary(grouping: firstReviews) { calendar.startOfDay(for: $0.date) }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - days + 1, to: today) else { return nil }
            let reviews = reviewsByDay[day] ?? []
            return ActivityDay(
                date: day,
                reviewed: reviews.count,
                correct: reviews.filter(\.correct).count,
                newWords: firstReviewsByDay[day]?.count ?? 0
            )
        }
    }
}
