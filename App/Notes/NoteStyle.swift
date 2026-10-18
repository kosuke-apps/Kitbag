import SwiftUI
import UIKit

extension Color {
  /// The yellow of a sticky note, and a deep amber in dark mode.
  static let stickyNote = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.36, green: 0.31, blue: 0.12, alpha: 1) : UIColor(red: 1.0, green: 0.96, blue: 0.76, alpha: 1)
    })
}
