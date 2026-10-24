import KitbagCore
import SwiftUI
import UIKit

// Mantissa's own sources, built unchanged as the MantissaGuest module (project.yml).
@testable import MantissaGuest

/// What Mantissa's `@main` (`MantissaApp`) creates: its model. If a new Mantissa release changes that file, this has to
/// follow it (docs/guests.md).
@MainActor
final class MantissaRuntime {
  let model = AppModel()

  /// Makes Mantissa speak the language chosen for the whole of Kitbag (it has a setting of its own, which this overwrites).
  func setLanguage(_ choice: LanguageChoice) {
    let language: AppLanguage
    switch choice {
    case .system: language = .system
    case .english: language = .english
    case .japanese: language = .japanese
    }
    if model.language != language { model.language = language }
  }
}

/// Mantissa's window content: what `MantissaApp.body` puts in its `WindowGroup`.
struct MantissaGuestView: View {
  let runtime: MantissaRuntime

  private static let accent = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.310, green: 0.820, blue: 0.773, alpha: 1)
        : UIColor(red: 0.043, green: 0.498, blue: 0.471, alpha: 1)
    })

  var body: some View {
    CalculatorScreen()
      .environment(runtime.model)
      .environment(\.locale, runtime.model.language.locale ?? Locale.current)
      // Mantissa's AccentColor asset (not carried over), so that its keys and highlights keep their colour (as of v0.24.0: 0B7F78, and 4FD1C5 in dark mode). The code reads
      // `Color.accentColor`, which follows `accentColor(_:)`; `tint(_:)` alone leaves it at the system blue.
      .accentColor(Self.accent)
      .tint(Self.accent)
  }
}
