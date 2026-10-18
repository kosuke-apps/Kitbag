import Foundation
import Testing

@testable import KitbagCore

private let chicago: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
  return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
  chicago.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
}

@Suite("Signature")
struct SignatureTests {
  @Test func readsTheDatesInsideAProfile() {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
      <key>CreationDate</key><date>2026-10-17T21:54:41Z</date>
      <key>ExpirationDate</key><date>2026-10-24T21:54:41Z</date>
      <key>Name</key><string>iOS Team Provisioning Profile</string>
      </dict></plist>
      """
    var data = Data([0x30, 0x82, 0x01, 0xFF, 0x06, 0x09])  // the start of a signed envelope
    data.append(Data(xml.utf8))
    data.append(Data([0x00, 0x31, 0x82, 0x02]))  // and its signature
    let profile = ProvisioningProfile(data: data)
    let expected = ISO8601DateFormatter().date(from: "2026-10-24T21:54:41Z")
    #expect(profile?.expiresAt == expected)
    #expect(profile?.createdAt == ISO8601DateFormatter().date(from: "2026-10-17T21:54:41Z"))
  }

  @Test func hasNoProfileWithoutAPropertyList() {
    #expect(ProvisioningProfile(data: Data()) == nil)
    #expect(ProvisioningProfile(data: Data("not a profile".utf8)) == nil)
  }

  @Test func countsWhatIsLeft() {
    let now = date(18, 12)
    #expect(SignatureRemaining(expiresAt: date(18, 11), now: now) == .expired)
    #expect(SignatureRemaining(expiresAt: date(18, 12), now: now) == .expired)
    #expect(SignatureRemaining(expiresAt: date(18, 12, 20), now: now) == .hours(1))
    #expect(SignatureRemaining(expiresAt: date(19, 9), now: now) == .hours(21))
    #expect(SignatureRemaining(expiresAt: date(20, 12), now: now) == .days(2))
    #expect(SignatureRemaining(expiresAt: date(24, 21, 54), now: now) == .days(6))
  }

  @Test func warnsInStages() {
    #expect(SignatureRemaining.days(6).level == .ok)
    #expect(SignatureRemaining.days(2).level == .ok)
    #expect(SignatureRemaining.days(1).level == .soon)
    #expect(SignatureRemaining.hours(5).level == .urgent)
    #expect(SignatureRemaining.expired.level == .urgent)
  }

  @Test func plansRemindersBeforeItRunsOut() {
    let expires = date(24, 21, 54)
    let all = SigningReminder.plan(expiresAt: expires, now: date(18, 12), calendar: chicago)
    #expect(all.map(\.kind) == [.twoDays, .oneDay, .today])
    #expect(all.map(\.fireDate) == [date(22, 9), date(23, 18), date(24, 8)])
    let later = SigningReminder.plan(expiresAt: expires, now: date(23, 19), calendar: chicago)
    #expect(later.map(\.kind) == [.today])
    #expect(SigningReminder.plan(expiresAt: expires, now: date(24, 9), calendar: chicago).isEmpty)
  }

  @Test func skipsTheSameDayReminderWhenItRunsOutEarlyInTheMorning() {
    let early = SigningReminder.plan(expiresAt: date(24, 9, 30), now: date(18, 12), calendar: chicago)
    #expect(early.map(\.kind) == [.twoDays, .oneDay])
  }
}

@Suite("Reminder plan")
struct ReminderPlanTests {
  @Test func keepsTheSoonestOpenRemindersUpToTheLimit() {
    let now = date(18, 12)
    func deadline(_ title: String, day: Int, done: Bool = false) -> Deadline {
      Deadline(
        title: title, date: LocalDate(year: 2026, month: 10, day: day), time: TimeOfDay(hour: 12, minute: 0),
        isDone: done,
        reminder: .hourBefore)
    }
    let book = DeadlineBook(deadlines: [
      deadline("late", day: 30), deadline("soon", day: 20), deadline("done", day: 21, done: true),
      deadline("past", day: 10), deadline("middle", day: 25),
    ])
    let plan = book.reminderPlan(now: now, calendar: chicago, limit: 2)
    #expect(plan.map(\.deadline.title) == ["soon", "middle"])
    #expect(plan[0].fireDate == date(20, 11))
    #expect(book.reminderPlan(now: now, calendar: chicago, limit: 10).count == 3)
  }
}
