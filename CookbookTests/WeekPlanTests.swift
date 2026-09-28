import XCTest

final class WeekPlanTests: XCTestCase {

    /// Fixed calendar so the tests don't drift with the runner's locale.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 1  // Sunday, so Sat/Sun bracket the Friday close
        return c
    }()

    /// 2026-09-28 is a Monday; that week's Friday is 2026-10-02.
    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale
        return f.date(from: iso)!
    }

    // MARK: - weekClose

    func testWeekClose_onFridayIsThatSameDay() {
        let close = WeekPlan.weekClose(onOrBefore: date("2026-10-02 18:00"), calendar: calendar)
        XCTAssertEqual(close, date("2026-10-02 00:00"))
    }

    func testWeekClose_onSaturdayIsTheFridayJustPast() {
        let close = WeekPlan.weekClose(onOrBefore: date("2026-10-03 09:00"), calendar: calendar)
        XCTAssertEqual(close, date("2026-10-02 00:00"))
    }

    func testWeekClose_onSundayIsStillThatFriday() {
        let close = WeekPlan.weekClose(onOrBefore: date("2026-10-04 09:00"), calendar: calendar)
        XCTAssertEqual(close, date("2026-10-02 00:00"))
    }

    func testWeekClose_midweekReachesBackToThePreviousFriday() {
        let close = WeekPlan.weekClose(onOrBefore: date("2026-09-30 12:00"), calendar: calendar)
        XCTAssertEqual(close, date("2026-09-25 00:00"))
    }

    // MARK: - isReviewDue

    func testReviewNotDueMidweek() {
        XCTAssertFalse(WeekPlan.isReviewDue(now: date("2026-09-30 12:00"), lastHandled: nil, calendar: calendar))
    }

    func testReviewDueOnFriday() {
        XCTAssertTrue(WeekPlan.isReviewDue(now: date("2026-10-02 08:00"), lastHandled: nil, calendar: calendar))
    }

    func testReviewStillDueOnTheWeekend() {
        XCTAssertTrue(WeekPlan.isReviewDue(now: date("2026-10-04 10:00"), lastHandled: nil, calendar: calendar))
    }

    func testReviewNotDueTwiceInTheSameWeek() {
        let handled = date("2026-10-02 00:00")
        XCTAssertFalse(WeekPlan.isReviewDue(now: date("2026-10-03 10:00"), lastHandled: handled, calendar: calendar))
    }

    func testReviewDueAgainTheFollowingWeek() {
        let handled = date("2026-10-02 00:00")
        XCTAssertTrue(WeekPlan.isReviewDue(now: date("2026-10-09 08:00"), lastHandled: handled, calendar: calendar))
    }

    func testReviewNotDueOnMondayEvenWithAnUnhandledPlan() {
        XCTAssertFalse(WeekPlan.isReviewDue(now: date("2026-10-05 09:00"), lastHandled: nil, calendar: calendar))
    }

    func testReviewNotDueEarlyInTheNewWeek() {
        let handled = date("2026-10-02 00:00")
        XCTAssertFalse(WeekPlan.isReviewDue(now: date("2026-10-06 08:00"), lastHandled: handled, calendar: calendar))
    }
}
