import KitbagCore
import SwiftUI

/// A small line at the bottom of the home screen: when this build's signature runs out and how long is left, down to the
/// minute. A free Apple ID's builds stop opening after seven days, so this is worth a glance, but it stays quiet until it
/// is close. Tapping it opens the details in Settings. Nothing is shown in the simulator or for a build without a profile.
struct SigningFooter: View {
  let open: () -> Void

  var body: some View {
    if let expires = SigningStatus.expiresAt {
      // The minute is enough: the text changes by minutes.
      TimelineView(.everyMinute) { context in
        let remaining = SignatureRemaining(expiresAt: expires, now: context.date)
        Button(action: open) {
          VStack(spacing: 3) {
            HStack(spacing: 5) {
              if remaining.level != .ok { Image(systemName: "exclamationmark.triangle.fill") }
              text(for: remaining, expires: expires)
            }
            if remaining != .expired {
              Text("\(SigningStatus.left(from: context.date, to: expires)) left", tableName: "Settings")
            }
            if remaining.level == .urgent {
              Text("Connect your iPhone to your Mac and install Kitbag again.", tableName: "Settings")
            }
          }
          .font(.caption2)
          .foregroundStyle(color(for: remaining.level))
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
      }
    }
  }

  @ViewBuilder private func text(for remaining: SignatureRemaining, expires: Date) -> some View {
    let when = expires.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute().locale(LanguageStore.shared.locale))
    if remaining == .expired {
      Text("Signature expired \(when)", tableName: "Settings")
    } else {
      Text("Signature expires \(when)", tableName: "Settings")
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
