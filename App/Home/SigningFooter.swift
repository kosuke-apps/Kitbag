import KitbagCore
import SwiftUI

/// A small line at the bottom of the home screen: how long this build's signature has left. A free Apple ID's builds stop
/// opening after seven days, so this is worth a glance, but it stays quiet until it is close. Nothing is shown in the
/// simulator or for a build without a profile.
struct SigningFooter: View {
  var body: some View {
    if let expires = SigningStatus.expiresAt {
      // The minute is enough: the text changes by hours and days.
      TimelineView(.everyMinute) { context in
        let remaining = SignatureRemaining(expiresAt: expires, now: context.date)
        VStack(spacing: 3) {
          HStack(spacing: 5) {
            if remaining.level != .ok { Image(systemName: "exclamationmark.triangle.fill") }
            text(for: remaining, expires: expires)
          }
          if remaining.level == .urgent {
            Text("Connect your iPhone to your Mac and install Kitbag again.", tableName: "Settings")
          }
        }
        .font(.caption2)
        .foregroundStyle(color(for: remaining.level))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
      }
    }
  }

  @ViewBuilder private func text(for remaining: SignatureRemaining, expires: Date) -> some View {
    let relative = expires.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
    if remaining == .expired {
      Text("Signature expired \(relative)", tableName: "Settings")
    } else {
      Text("Signature expires \(relative)", tableName: "Settings")
    }
  }

  private func color(for level: SignatureRemaining.Level) -> Color {
    switch level {
    case .ok: Color.secondary.opacity(0.7)
    case .soon: .orange
    case .urgent: .red
    }
  }
}
