import SwiftUI
import UIKit

/// Forces the light or dark appearance on the app's window, or hands it back to the system with `nil`.
///
/// SwiftUI's `preferredColorScheme(nil)` does not always return to the system's appearance after a scheme was forced:
/// leaving a dark theme for a light one kept the labels white on a light background. Setting the window's own override
/// goes back reliably, and SwiftUI's `colorScheme` follows the window.
struct WindowAppearance: UIViewRepresentable {
  let scheme: ColorScheme?

  func makeUIView(context: Context) -> Anchor {
    let view = Anchor()
    view.isUserInteractionEnabled = false
    view.style = style
    return view
  }

  func updateUIView(_ view: Anchor, context: Context) {
    view.style = style
  }

  private var style: UIUserInterfaceStyle {
    switch scheme {
    case .light: .light
    case .dark: .dark
    case nil: .unspecified
    @unknown default: .unspecified
    }
  }

  /// A view that is in the window, to reach it.
  final class Anchor: UIView {
    var style: UIUserInterfaceStyle = .unspecified {
      didSet { window?.overrideUserInterfaceStyle = style }
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      window?.overrideUserInterfaceStyle = style
    }
  }
}

enum SystemAppearance {
  /// The appearance the phone is set to, whatever the app forces on its own window.
  static var scheme: ColorScheme {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    return scene?.screen.traitCollection.userInterfaceStyle == .dark ? .dark : .light
  }
}
