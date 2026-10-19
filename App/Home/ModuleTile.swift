import SwiftUI
import UIKit

/// An app icon with its name below, like on the iPhone's home screen.
struct ModuleTile: View {
  let module: ModuleID
  var iconSize: CGFloat = 64
  var font: Font = .caption
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        ToolIconView(module: module, size: iconSize)
        Text(module.title)
          .font(font)
          .foregroundStyle(.primary)
          .lineLimit(1)
      }
    }
    .buttonStyle(.plain)
  }
}

/// A tool as a card: its icon and its name side by side, two to a row.
struct ModuleTileCard: View {
  let module: ModuleID
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ToolIconView(module: module, size: 40)
        Text(module.title)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .themedCard(padding: 12, radius: 18)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A tool as a row of a list: a small icon, its name in serif and an arrow, with a thin rule underneath.
struct ModuleRow: View {
  @Environment(\.palette) private var palette
  let module: ModuleID
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        ToolIconView(module: module, size: 34)
        Text(module.title)
          .font(.system(.body, design: .serif))
          .foregroundStyle(.primary)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(palette.heading)
      }
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) { Rectangle().fill(palette.cardStroke).frame(height: 1) }
  }
}

/// A tool's icon at a size: an image taken from a guest app, or a symbol on a coloured square.
struct ToolIconView: View {
  let module: ModuleID
  let size: CGFloat

  var body: some View {
    switch module.icon {
    case .guest(let name):
      AppIconImage(image: GuestIcon.load(name), size: size)
    case .symbol(let name, let color):
      SymbolIcon(name: name, color: color, size: size)
    }
  }
}

/// The tools on the home screen, laid out the way the style says.
struct ToolsView: View {
  @Environment(LayoutStore.self) private var layout
  @Environment(\.kitbagStyle) private var style
  let open: (ModuleID) -> Void

  var body: some View {
    switch style.toolsLayout {
    case .icons:
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 16, alignment: .top)], spacing: 24) {
        ForEach(layout.visibleTools) { module in ModuleTile(module: module) { open(module) } }
      }
    case .smallIcons:
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4), spacing: 14) {
        ForEach(layout.visibleTools) { module in
          ModuleTile(module: module, iconSize: 54, font: .caption2) { open(module) }
        }
      }
    case .tiles:
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
        ForEach(layout.visibleTools) { module in ModuleTileCard(module: module) { open(module) } }
      }
    case .list:
      VStack(spacing: 0) {
        ForEach(layout.visibleTools) { module in ModuleRow(module: module) { open(module) } }
      }
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
