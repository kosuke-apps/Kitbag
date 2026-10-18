import Foundation
import KitbagCore

/// When this build's signature runs out. A build signed with a free Apple ID stops opening after seven days; the date is
/// in the provisioning profile inside the app. The simulator and the App Store have no profile, so nothing is shown there.
enum SigningStatus {
  /// The expiry date, or nil when the build carries no profile.
  static var expiresAt: Date? {
    #if DEBUG
      // For checking the screens in the simulator: launch with `-kitbagFakeExpiry 2026-10-24T21:54:00Z`.
      if let text = UserDefaults.standard.string(forKey: "kitbagFakeExpiry"),
        let date = ISO8601DateFormatter().date(from: text)
      {
        return date
      }
    #endif
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return ProvisioningProfile(data: data)?.expiresAt
  }
}
