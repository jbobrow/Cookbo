import Foundation

/// Bookkeeping for the This Week plan.
///
/// The plan is reviewed at the close of each week — Friday — so the prompt
/// lands while weekend shopping and prep are being planned rather than after
/// the new week has already started. The window stays open through the
/// weekend, so someone who doesn't open the app until Sunday still gets asked.
enum WeekPlan {

    /// How long after Friday the review stays on offer: Friday, Saturday, Sunday.
    static let reviewWindowDays = 2

    /// The most recent Friday at or before `date`, at midnight.
    ///
    /// Deliberately not "the Friday of the calendar week", because when a week
    /// starts on Sunday that Friday is still days away and Sunday would fall
    /// through the gap.
    static func weekClose(onOrBefore date: Date, calendar: Calendar = .current) -> Date? {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<7 {
            if calendar.component(.weekday, from: day) == 6 { return day }  // 6 == Friday
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
            day = previous
        }
        return nil
    }

    /// Whether to ask about the plan: we're in the Friday-to-Sunday window and
    /// haven't already cleared or rolled over for that Friday.
    static func isReviewDue(now: Date = Date(), lastHandled: Date?, calendar: Calendar = .current) -> Bool {
        guard let close = weekClose(onOrBefore: now, calendar: calendar) else { return false }

        let daysSinceClose = calendar.dateComponents(
            [.day],
            from: close,
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        guard daysSinceClose <= reviewWindowDays else { return false }

        guard let lastHandled else { return true }
        return lastHandled < close
    }
}

/// Persisted alongside the cookbook so the review state syncs with the recipes.
struct WeekPlanState: Codable {
    /// The week-closing Friday we last cleared or rolled over for.
    var lastHandled: Date?
}
