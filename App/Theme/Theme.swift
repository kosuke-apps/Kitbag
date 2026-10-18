import SwiftUI
import UIKit

extension Color {
  /// A colour from a hex number such as `0x8C2F39`.
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: opacity)
  }
}

/// The colours of a theme in one appearance (light or dark).
struct Palette {
  var backgroundTop: Color
  var backgroundBottom: Color
  var card: Color
  var cardStroke: Color
  var accent: Color
  var shadow: Color
  /// A tint for the small headings above a section.
  var heading: Color
}

enum ThemeID: String, CaseIterable, Identifiable {
  case ivory
  case slate
  case midnight
  case forest
  case system

  var id: String { rawValue }
}

/// A look for the whole app: colours for light and dark, the typeface of titles, and whether the theme insists on one
/// appearance (a theme that is a dark navy does not make sense in light mode).
struct KitbagTheme {
  let id: ThemeID
  let name: LocalizedStringResource
  let light: Palette
  let dark: Palette
  let design: Font.Design
  let forcedScheme: ColorScheme?

  func palette(for scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }

  static func theme(_ id: ThemeID) -> KitbagTheme {
    switch id {
    case .ivory: ivory
    case .slate: slate
    case .midnight: midnight
    case .forest: forest
    case .system: system
    }
  }

  /// Warm paper and a burgundy accent, with serif titles: a library.
  static let ivory = KitbagTheme(
    id: .ivory, name: LocalizedStringResource("Ivory", table: "Settings"),
    light: Palette(
      backgroundTop: Color(hex: 0xFBF7EF), backgroundBottom: Color(hex: 0xF0E7D6),
      card: Color(hex: 0xFFFFFF, opacity: 0.82),
      cardStroke: Color(hex: 0xDCCDB1, opacity: 0.7), accent: Color(hex: 0x8C2F39),
      shadow: Color(hex: 0x5A4524, opacity: 0.10),
      heading: Color(hex: 0x8A7A5C)),
    dark: Palette(
      backgroundTop: Color(hex: 0x1D1A16), backgroundBottom: Color(hex: 0x272119),
      card: Color(hex: 0xFFFFFF, opacity: 0.06),
      cardStroke: Color(hex: 0xFFFFFF, opacity: 0.10), accent: Color(hex: 0xDDA66B),
      shadow: Color(hex: 0x000000, opacity: 0.35),
      heading: Color(hex: 0xB59F79)),
    design: .serif, forcedScheme: nil)

  /// Cool grey-blue and an indigo accent, with rounded titles: modern and calm.
  static let slate = KitbagTheme(
    id: .slate, name: LocalizedStringResource("Slate", table: "Settings"),
    light: Palette(
      backgroundTop: Color(hex: 0xF4F6FA), backgroundBottom: Color(hex: 0xE4E9F2),
      card: Color(hex: 0xFFFFFF, opacity: 0.9),
      cardStroke: Color(hex: 0xD3DAE8, opacity: 0.8), accent: Color(hex: 0x3B5BDB),
      shadow: Color(hex: 0x1F2A44, opacity: 0.08),
      heading: Color(hex: 0x6B7690)),
    dark: Palette(
      backgroundTop: Color(hex: 0x11141B), backgroundBottom: Color(hex: 0x1A202C),
      card: Color(hex: 0xFFFFFF, opacity: 0.06),
      cardStroke: Color(hex: 0xFFFFFF, opacity: 0.09), accent: Color(hex: 0x819CFF),
      shadow: Color(hex: 0x000000, opacity: 0.35),
      heading: Color(hex: 0x8D97AE)),
    design: .rounded, forcedScheme: nil)

  /// Deep navy with a gold accent and serif titles: the evening library.
  static let midnight = KitbagTheme(
    id: .midnight, name: LocalizedStringResource("Midnight", table: "Settings"),
    light: midnightPalette, dark: midnightPalette, design: .serif, forcedScheme: .dark)

  private static let midnightPalette = Palette(
    backgroundTop: Color(hex: 0x0A0F1F), backgroundBottom: Color(hex: 0x1A2748),
    card: Color(hex: 0xFFFFFF, opacity: 0.07),
    cardStroke: Color(hex: 0xFFFFFF, opacity: 0.13), accent: Color(hex: 0xE3C27E),
    shadow: Color(hex: 0x000000, opacity: 0.4),
    heading: Color(hex: 0x9FB0D6))

  /// Deep green with a soft mint accent.
  static let forest = KitbagTheme(
    id: .forest, name: LocalizedStringResource("Forest", table: "Settings"),
    light: forestPalette, dark: forestPalette, design: .rounded, forcedScheme: .dark)

  private static let forestPalette = Palette(
    backgroundTop: Color(hex: 0x0B1D18), backgroundBottom: Color(hex: 0x17372E),
    card: Color(hex: 0xFFFFFF, opacity: 0.07),
    cardStroke: Color(hex: 0xFFFFFF, opacity: 0.12), accent: Color(hex: 0x9ED9AE),
    shadow: Color(hex: 0x000000, opacity: 0.4),
    heading: Color(hex: 0x8FB5A2))

  /// The plain system look.
  static let system = KitbagTheme(
    id: .system, name: LocalizedStringResource("System", table: "Settings"),
    light: Palette(
      backgroundTop: Color(uiColor: .systemGroupedBackground),
      backgroundBottom: Color(uiColor: .systemGroupedBackground),
      card: Color(uiColor: .secondarySystemGroupedBackground), cardStroke: Color.clear, accent: Color.blue,
      shadow: Color.clear, heading: Color.secondary),
    dark: Palette(
      backgroundTop: Color(uiColor: .systemGroupedBackground),
      backgroundBottom: Color(uiColor: .systemGroupedBackground),
      card: Color(uiColor: .secondarySystemGroupedBackground), cardStroke: Color.clear, accent: Color.blue,
      shadow: Color.clear, heading: Color.secondary),
    design: .default, forcedScheme: nil)
}

extension EnvironmentValues {
  @Entry var palette: Palette = KitbagTheme.system.light
  @Entry var titleDesign: Font.Design = .default
}

/// The theme's background: a soft vertical gradient behind everything.
struct ThemedBackground: View {
  @Environment(\.palette) private var palette

  var body: some View {
    LinearGradient(colors: [palette.backgroundTop, palette.backgroundBottom], startPoint: .top, endPoint: .bottom)
      .ignoresSafeArea()
  }
}

/// A surface for a group of content: a translucent card with a hairline edge and a soft shadow.
struct ThemedCard: ViewModifier {
  @Environment(\.palette) private var palette
  var padding: CGFloat = 16
  var radius: CGFloat = 20

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(palette.card, in: shape)
      .overlay(shape.strokeBorder(palette.cardStroke, lineWidth: 0.75))
      .shadow(color: palette.shadow, radius: 14, y: 5)
  }
}

extension View {
  /// Puts the theme's gradient behind a tool's screen.
  func themedScreen() -> some View {
    background { ThemedBackground() }
  }

  func themedCard(padding: CGFloat = 16, radius: CGFloat = 20) -> some View {
    modifier(ThemedCard(padding: padding, radius: radius))
  }
}

/// A small heading above a section: capitals, spaced out, in the theme's heading colour.
struct SectionHeading: View {
  @Environment(\.palette) private var palette
  let text: Text

  init(_ text: Text) { self.text = text }

  var body: some View {
    text
      .font(.caption.weight(.semibold))
      .textCase(.uppercase)
      .tracking(1.1)
      .foregroundStyle(palette.heading)
      .accessibilityAddTraits(.isHeader)
  }
}
