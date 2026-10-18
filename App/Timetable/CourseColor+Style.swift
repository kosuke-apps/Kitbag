import KitbagCore
import SwiftUI
import UIKit

extension CourseColor {
  /// The colour of a block: a light pastel like a printed timetable's, and a muted deep tone in dark mode.
  var blockColor: Color {
    let hexes = hexes
    return Color(
      uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: hexes.dark) : UIColor(hex: hexes.light) })
  }

  private var hexes: (light: UInt32, dark: UInt32) {
    switch self {
    case .lavender: (0xE0D6F0, 0x4A3F63)
    case .periwinkle: (0xDAE1F1, 0x3A4668)
    case .mint: (0xE2EFDB, 0x3B5640)
    case .rose: (0xF1D0D0, 0x683D3D)
    case .peach: (0xF7E4D6, 0x6A4B35)
    case .butter: (0xF8F0C8, 0x62592B)
    case .sky: (0xD5EAF6, 0x2F5169)
    case .sage: (0xD6E8E2, 0x30574F)
    }
  }
}

extension UIColor {
  fileprivate convenience init(hex: UInt32) {
    self.init(
      red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1)
  }
}
