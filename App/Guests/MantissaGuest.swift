import SwiftUI
import UIKit

// Mantissa's own sources, built unchanged as the MantissaGuest module (project.yml).
@testable import MantissaGuest

/// What Mantissa's `@main` (`MantissaApp`) creates: its model. If a new Mantissa release changes that file, this has to
/// follow it (docs/guests.md).
@MainActor
final class MantissaRuntime {
  let model = AppModel()
}

/// Mantissa's window content: what `MantissaApp.body` puts in its `WindowGroup`.
struct MantissaGuestView: View {
  let runtime: MantissaRuntime

  private static let accent = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.42, blue: 0.49, alpha: 1)
        : UIColor(red: 0.816, green: 0.227, blue: 0.306, alpha: 1)
    })

  var body: some View {
    CalculatorScreen()
      .environment(runtime.model)
      .environment(\.locale, runtime.model.language.locale ?? Locale.current)
      // Mantissa's AccentColor asset (not carried over), so that its keys and highlights keep their rose. The code reads
      // `Color.accentColor`, which follows `accentColor(_:)`; `tint(_:)` alone leaves it at the system blue.
      .accentColor(Self.accent)
      .tint(Self.accent)
  }
}
