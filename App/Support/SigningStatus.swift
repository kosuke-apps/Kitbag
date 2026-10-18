import Foundation
import KitbagCore

/// When this build's signature runs out. A build signed with a free Apple ID stops opening after seven days; the date is
/// in the provisioning profile inside the app. The simulator and the App Store have no profile, so nothing is shown there.
enum SigningStatus {
  /// The profile this build carries, or nil when it has none.
  static var profile: ProvisioningProfile? {
    #if DEBUG
      // For checking the screens in the simulator: launch with `-kitbagFakeExpiry 2026-10-24T21:54:00Z`.
      if let text = UserDefaults.standard.string(forKey: "kitbagFakeExpiry"),
        let date = ISO8601DateFormatter().date(from: text)
      {
        return ProvisioningProfile(
          createdAt: date.addingTimeInterval(-7 * 86400), expiresAt: date,
          name: "iOS Team Provisioning Profile: dev.kosuke.kitbag", teamName: "Example Person")
      }
    #endif
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return ProvisioningProfile(data: data)
  }

  static var expiresAt: Date? { profile?.expiresAt }

  /// "6d 23h 41m" or "6日 23時間 41分", in the language chosen for Kitbag, for the time between two moments.
  static func left(from start: Date, to end: Date) -> String {
    var calendar = Calendar.current
    calendar.locale = LanguageStore.shared.locale
    let formatter = DateComponentsFormatter()
    formatter.calendar = calendar
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 3
    formatter.zeroFormattingBehavior = .dropLeading
    return formatter.string(from: start, to: max(start, end)) ?? ""
  }
}
