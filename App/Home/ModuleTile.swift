import SwiftUI
import UIKit

/// An app icon with its name below, like on the iPhone's home screen.
struct ModuleTile: View {
  let module: ModuleID
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        AppIconImage(image: module.guestIconName.flatMap(GuestIcon.load), size: 64)
        Text(module.title)
          .font(.caption)
          .foregroundStyle(.primary)
          .lineLimit(1)
      }
    }
    .buttonStyle(.plain)
  }
}

/// An icon image with the rounded corners iOS gives an app icon.
struct AppIconImage: View {
  let image: UIImage?
  let size: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
    Group {
      if let image {
        Image(uiImage: image).resizable().scaledToFit()
      } else {
        Color.secondary.opacity(0.2)
      }
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    .overlay(shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
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
