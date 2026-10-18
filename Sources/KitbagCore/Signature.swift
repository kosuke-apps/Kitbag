import Foundation

/// The dates inside the provisioning profile that a development build carries (`embedded.mobileprovision`). A free Apple
/// ID's profile lasts seven days; after that the app does not open until it is installed again, so the app shows how long
/// is left. The file is a signed envelope with a property list in plain text inside, which is all that is read.
public struct ProvisioningProfile: Equatable, Sendable {
  public var createdAt: Date?
  public var expiresAt: Date?

  public init(createdAt: Date? = nil, expiresAt: Date? = nil) {
    self.createdAt = createdAt
    self.expiresAt = expiresAt
  }

  /// Nil when the data holds no property list (the simulator and the App Store have no profile).
  public init?(data: Data) {
    guard let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), options: .backwards),
      start.lowerBound < end.upperBound,
      let plist = try? PropertyListSerialization.propertyList(
        from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any]
    else { return nil }
    self.init(createdAt: plist["CreationDate"] as? Date, expiresAt: plist["ExpirationDate"] as? Date)
  }
}

/// How long a signature has left, in the units a person thinks in.
public enum SignatureRemaining: Equatable, Sendable {
  case expired
  case hours(Int)
  case days(Int)

  public init(expiresAt: Date, now: Date) {
    let seconds = expiresAt.timeIntervalSince(now)
    if seconds <= 0 {
      self = .expired
    } else if seconds < 24 * 3600 {
      self = .hours(max(1, Int((seconds / 3600).rounded(.up))))
    } else {
      self = .days(Int(seconds / (24 * 3600)))
    }
  }

  public enum Level: Equatable, Sendable {
    /// Plenty of time.
    case ok
    /// Less than two days.
    case soon
    /// Less than a day, or over.
    case urgent
  }

  public var level: Level {
    switch self {
    case .expired, .hours: .urgent
    case .days(let days): days <= 1 ? .soon : .ok
    }
  }
}

/// A reminder that the signature is about to run out.
public struct SigningReminder: Equatable, Sendable {
  public enum Kind: String, Sendable {
    case twoDays
    case oneDay
    case today
  }

  public var kind: Kind
  public var fireDate: Date

  /// The reminders still to come: two days before at 9:00, the evening before at 18:00, and on the day at 8:00 when the
  /// signature lasts until after 10:00.
  public static func plan(expiresAt: Date, now: Date, calendar: Calendar) -> [SigningReminder] {
    let day = calendar.startOfDay(for: expiresAt)
    func at(_ daysBefore: Int, hour: Int) -> Date? {
      calendar.date(byAdding: .day, value: -daysBefore, to: day).flatMap {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0)
      }
    }
    var list: [SigningReminder] = []
    if let fire = at(2, hour: 9) { list.append(SigningReminder(kind: .twoDays, fireDate: fire)) }
    if let fire = at(1, hour: 18) { list.append(SigningReminder(kind: .oneDay, fireDate: fire)) }
    if let fire = at(0, hour: 8), let late = at(0, hour: 10), expiresAt > late {
      list.append(SigningReminder(kind: .today, fireDate: fire))
    }
    return list.filter { $0.fireDate > now && $0.fireDate < expiresAt }
  }
}

extension DeadlineBook {
  /// The reminders to have scheduled at `now`: not done, still to come, soonest first, and no more than `limit` because
  /// iOS keeps at most 64 pending notifications for an app.
  public func reminderPlan(now: Date, calendar: Calendar, limit: Int) -> [(deadline: Deadline, fireDate: Date)] {
    deadlines
      .compactMap { deadline -> (deadline: Deadline, fireDate: Date)? in
        guard !deadline.isDone, let fire = deadline.reminderDate(calendar: calendar), fire > now else { return nil }
        return (deadline, fire)
      }
      .sorted { $0.fireDate < $1.fireDate }
      .prefix(limit)
      .map { $0 }
  }
}
