import Foundation
import Testing

@testable import KitbagCore

private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
  return calendar
}()

private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
  calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .distantPast
}

private func decide(
  _ source: DataSource = .weather, byRequest: Bool = false, last: Date? = nil, now: Date = date(10, 18),
  connection: Connection = .wifi, settings: DataUseSettings = DataUseSettings(), mobileBytes: Int = 0
) -> FetchDecision {
  DataUsePolicy.decide(
    source, byRequest: byRequest, lastFetched: last, now: now, connection: connection, settings: settings,
    mobileBytesThisMonth: mobileBytes)
}

@Suite("Data use: when to fetch")
struct DataUsePolicyTests {
  @Test func fetchesAtOnceWhenThereIsNothingYet() {
    #expect(decide() == .fetch)
    #expect(decide(connection: .mobile) == .fetch)
  }

  @Test func waitsTheUsualTimeOnWiFiAndLongerOnMobileData() {
    let now = date(10, 18)
    // Weather: 15 minutes on Wi-Fi, 30 on mobile data, 60 in Low Data Mode.
    #expect(decide(last: now.addingTimeInterval(-14 * 60), now: now) == .tooSoon)
    #expect(decide(last: now.addingTimeInterval(-15 * 60), now: now) == .fetch)
    #expect(decide(last: now.addingTimeInterval(-20 * 60), now: now, connection: .mobile) == .tooSoon)
    #expect(decide(last: now.addingTimeInterval(-30 * 60), now: now, connection: .mobile) == .fetch)
    #expect(decide(last: now.addingTimeInterval(-45 * 60), now: now, connection: .lowData) == .tooSoon)
    #expect(decide(last: now.addingTimeInterval(-60 * 60), now: now, connection: .lowData) == .fetch)
    // Calendars: an hour on Wi-Fi, two on mobile data.
    #expect(decide(.calendars, last: now.addingTimeInterval(-90 * 60), now: now, connection: .mobile) == .tooSoon)
    #expect(decide(.calendars, last: now.addingTimeInterval(-120 * 60), now: now, connection: .mobile) == .fetch)
  }

  @Test func doesNotSlowDownWhenSavingIsOff() {
    var settings = DataUseSettings()
    settings.saveMobileData = false
    let now = date(10, 18)
    #expect(decide(last: now.addingTimeInterval(-15 * 60), now: now, connection: .mobile, settings: settings) == .fetch)
  }

  @Test func followsAChosenRhythmWhateverTheConnection() {
    var settings = DataUseSettings()
    settings.weatherOnMobile = .everyHour
    settings.weatherOnWiFi = .every3Hours
    let now = date(10, 18)
    #expect(
      decide(last: now.addingTimeInterval(-59 * 60), now: now, connection: .mobile, settings: settings) == .tooSoon)
    #expect(decide(last: now.addingTimeInterval(-60 * 60), now: now, connection: .mobile, settings: settings) == .fetch)
    #expect(decide(last: now.addingTimeInterval(-2 * 3600), now: now, settings: settings) == .tooSoon)
    #expect(decide(last: now.addingTimeInterval(-3 * 3600), now: now, settings: settings) == .fetch)
  }

  @Test func manualMeansOnlyWhenAsked() {
    var settings = DataUseSettings()
    settings.weatherOnMobile = .manual
    #expect(decide(connection: .mobile, settings: settings) == .blocked(.manualOnly))
    #expect(decide(byRequest: true, connection: .mobile, settings: settings) == .fetch)
    // Wi-Fi is not affected.
    #expect(decide(settings: settings) == .fetch)
  }

  @Test func notOnMobileBlocksEvenARequestButNotWiFi() {
    var settings = DataUseSettings()
    settings.weatherOnMobile = .notOnMobile
    #expect(decide(connection: .mobile, settings: settings) == .blocked(.notOnMobile))
    #expect(decide(byRequest: true, connection: .mobile, settings: settings) == .blocked(.notOnMobile))
    #expect(decide(byRequest: true, connection: .lowData, settings: settings) == .blocked(.notOnMobile))
    #expect(decide(byRequest: true, connection: .wifi, settings: settings) == .fetch)
    // A search for a place follows the weather's choice.
    #expect(decide(.places, byRequest: true, connection: .mobile, settings: settings) == .blocked(.notOnMobile))
    #expect(decide(.places, byRequest: true, connection: .wifi, settings: settings) == .fetch)
  }

  @Test func aSavedWiFiChoiceOfNotOnMobileDoesNothingOnWiFi() {
    var settings = DataUseSettings()
    settings.weatherOnWiFi = .notOnMobile
    #expect(decide(settings: settings) == .blocked(.manualOnly))  // never reached from the settings screen
    #expect(decide(byRequest: true, settings: settings) == .fetch)
  }

  @Test func theMonthlyLimitStopsAutomaticUpdatesOnMobileDataOnly() {
    var settings = DataUseSettings()
    settings.monthlyMobileLimit = 10_000_000
    #expect(decide(connection: .mobile, settings: settings, mobileBytes: 9_999_999) == .fetch)
    #expect(decide(connection: .mobile, settings: settings, mobileBytes: 10_000_000) == .blocked(.monthlyLimit))
    #expect(decide(connection: .lowData, settings: settings, mobileBytes: 12_000_000) == .blocked(.monthlyLimit))
    #expect(decide(byRequest: true, connection: .mobile, settings: settings, mobileBytes: 12_000_000) == .fetch)
    #expect(decide(connection: .wifi, settings: settings, mobileBytes: 12_000_000) == .fetch)
  }

  @Test func readsAnOlderSettingsFile() throws {
    let settings = try JSONDecoder().decode(DataUseSettings.self, from: Data(#"{"saveMobileData":false}"#.utf8))
    #expect(!settings.saveMobileData)
    #expect(settings.weatherOnMobile == .automatic)
    #expect(settings.monthlyMobileLimit == nil)
    let full = DataUseSettings(
      limit: 25_000_000, mobile: .manual)
    #expect(try JSONDecoder().decode(DataUseSettings.self, from: JSONEncoder().encode(full)) == full)
  }
}

extension DataUseSettings {
  fileprivate init(limit: Int?, mobile: RefreshChoice) {
    self.init()
    monthlyMobileLimit = limit
    calendarsOnMobile = mobile
  }
}

@Suite("Data use: the meter")
struct DataUsageTests {
  @Test func countsBytesAndRequestsBySourceAndConnection() {
    var usage = DataUsage(since: date(10, 1))
    usage.add(.weather, bytes: 40_000, metered: false, at: date(10, 5), calendar: calendar)
    usage.add(.weather, bytes: 42_000, metered: true, at: date(10, 6), calendar: calendar)
    usage.add(.calendars, bytes: 9_000, metered: true, at: date(10, 6), calendar: calendar)
    let weather = usage.tally(.weather, inMonthOf: date(10, 18), calendar: calendar)
    #expect(weather.wifi == 40_000 && weather.mobile == 42_000 && weather.requests == 2)
    #expect(usage.tally(inMonthOf: date(10, 18), calendar: calendar).total == 91_000)
    #expect(usage.mobileBytes(inMonthOf: date(10, 18), calendar: calendar) == 51_000)
    #expect(usage.averageRequest(.weather) == 41_000)
    #expect(usage.averageRequest(.places) == nil)
  }

  @Test func keepsMonthsApartSoThatALimitStartsAgain() {
    var usage = DataUsage(since: date(9, 1))
    usage.add(.weather, bytes: 5_000_000, metered: true, at: date(9, 30, 23), calendar: calendar)
    usage.add(.weather, bytes: 1_000, metered: true, at: date(10, 1, 0), calendar: calendar)
    #expect(usage.mobileBytes(inMonthOf: date(9, 15), calendar: calendar) == 5_000_000)
    #expect(usage.mobileBytes(inMonthOf: date(10, 15), calendar: calendar) == 1_000)
    #expect(usage.tally().mobile == 5_001_000)
  }

  @Test func countsTheMonthInTheCalendarsTimeZone() {
    // 03:00 UTC on 1 November is still 31 October in Chicago.
    var usage = DataUsage(since: date(10, 1))
    let utcMorning = Date(timeIntervalSince1970: 1_793_502_000)  // 2026-11-01T03:00:00Z
    usage.add(.weather, bytes: 7, metered: false, at: utcMorning, calendar: calendar)
    #expect(DataUsage.monthKey(utcMorning, calendar: calendar) == "2026-10")
    #expect(usage.tally(.weather, inMonthOf: date(10, 31), calendar: calendar).wifi == 7)
  }

  @Test func forgetsMonthsBeyondTheLastThirteen() {
    var usage = DataUsage(since: date(1, 1))
    for offset in 0..<16 {
      let month = calendar.date(byAdding: .month, value: offset, to: date(1, 15)) ?? .distantPast
      usage.add(.weather, bytes: 1, metered: false, at: month, calendar: calendar)
    }
    #expect(usage.tally(.weather).requests == DataUsage.monthsKept)
  }

  @Test func resetsToNothing() {
    var usage = DataUsage(since: date(1, 1))
    usage.add(.weather, bytes: 100, metered: true, at: date(10, 5), calendar: calendar)
    usage.reset(at: date(10, 18))
    #expect(usage.tally().total == 0)
    #expect(usage.since == date(10, 18))
  }

  @Test func roundTripsThroughJSON() throws {
    var usage = DataUsage(since: date(10, 1))
    usage.add(.calendars, bytes: 1234, metered: true, at: date(10, 5), calendar: calendar)
    let back = try JSONDecoder().decode(DataUsage.self, from: JSONEncoder().encode(usage))
    #expect(back == usage)
  }
}
