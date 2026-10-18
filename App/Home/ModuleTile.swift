import SwiftUI
import UIKit

/// An app icon with its name below, like on the iPhone's home screen.
struct ModuleTile: View {
  let module: ModuleID
  let action: () -> Void

  private let iconSize: CGFloat = 64

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        icon
        Text(module.title)
          .font(.caption)
          .foregroundStyle(.primary)
          .lineLimit(1)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private var icon: some View {
    switch module.icon {
    case .guest(let name):
      AppIconImage(image: GuestIcon.load(name), size: iconSize)
    case .symbol(let name, let color):
      SymbolIcon(name: name, color: color, size: iconSize)
    }
  }
}

/// The rounded corners iOS gives an app icon.
private func iconShape(_ size: CGFloat) -> RoundedRectangle {
  RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
}

/// A guest app's icon image.
struct AppIconImage: View {
  let image: UIImage?
  let size: CGFloat

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().scaledToFit()
      } else {
        Color.secondary.opacity(0.2)
      }
    }
    .frame(width: size, height: size)
    .clipShape(iconShape(size))
    .overlay(iconShape(size).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
  }
}

/// The icon of a tool made for Kitbag: a white symbol on a coloured square.
struct SymbolIcon: View {
  let name: String
  let color: Color
  let size: CGFloat

  var body: some View {
    Image(systemName: name)
      .font(.system(size: size * 0.46, weight: .medium))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
      .clipShape(iconShape(size))
      .overlay(iconShape(size).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
  }
}

enum GuestIcon {
  /// The icon that tools/sync_guests.sh copied from a guest into the bundle's GuestIcons folder.
  static func load(_ name: String) -> UIImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "GuestIcons") else {
      return nil
    }
    return UIImage(contentsOfFile: url.path)
  }
}
