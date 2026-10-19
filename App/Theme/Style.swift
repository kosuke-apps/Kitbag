import SwiftUI

/// The look of Kitbag apart from its colours: how the cards are drawn, how today is laid out, how the tools are listed.
/// A theme (`KitbagTheme`) says which colours; a style says which shapes. Any style goes with any theme.
enum StyleID: String, CaseIterable, Identifiable {
  /// Rounded cards with a soft shadow, stacked: the look Kitbag started with.
  case classic
  /// Frosted, rounder cards that let the background through.
  case glass
  /// Tiles of different sizes side by side, like a dashboard of widgets.
  case bento
  /// Print-like: sharp corners, hairlines, serif headings, no boxes around the day.
  case editorial
  /// Close together and small, to fit more on one screen.
  case compact

  var id: String { rawValue }
}

/// How the Today part of the home screen is arranged.
enum TodayLayout {
  case stack, bento, editorial, compact
}

/// How the tools below it are listed.
enum ToolsLayout {
  /// App icons with a name underneath, as on the iPhone's home screen.
  case icons
  /// The same, smaller and four to a row.
  case smallIcons
  /// Two to a row, each a card with the icon and the name side by side.
  case tiles
  /// One to a row, like a table of contents.
  case list
}

/// How the date at the top of the home screen is drawn.
enum DateHeaderStyle {
  case large, editorial, compact
}

struct KitbagStyle {
  let id: StyleID
  let name: LocalizedStringResource
  let summary: LocalizedStringResource
  /// What a card's corner radius and padding are multiplied by (every call site names its own, for its size).
  let radiusScale: CGFloat
  let paddingScale: CGFloat
  /// How strong a card's shadow is: 0 for none, 1 for the usual one.
  let shadowScale: CGFloat
  /// The width of a card's edge line.
  let strokeWidth: CGFloat
  /// A card is frosted glass rather than a flat tint.
  let usesMaterial: Bool
  let todayLayout: TodayLayout
  let toolsLayout: ToolsLayout
  let header: DateHeaderStyle
  /// The space between the parts of Today.
  let sectionSpacing: CGFloat

  static func style(_ id: StyleID) -> KitbagStyle {
    switch id {
    case .classic: classic
    case .glass: glass
    case .bento: bento
    case .editorial: editorial
    case .compact: compact
    }
  }

  static let classic = KitbagStyle(
    id: .classic, name: LocalizedStringResource("Classic", table: "Settings"),
    summary: LocalizedStringResource(
      "Rounded cards with a soft shadow, one under another.", table: "Settings"),
    radiusScale: 1, paddingScale: 1, shadowScale: 1, strokeWidth: 0.75, usesMaterial: false,
    todayLayout: .stack, toolsLayout: .icons, header: .large, sectionSpacing: 18)

  static let glass = KitbagStyle(
    id: .glass, name: LocalizedStringResource("Glass", table: "Settings"),
    summary: LocalizedStringResource(
      "Frosted, rounder cards that let the colours behind them show through.", table: "Settings"),
    radiusScale: 1.45, paddingScale: 1.1, shadowScale: 1.25, strokeWidth: 1, usesMaterial: true,
    todayLayout: .stack, toolsLayout: .icons, header: .large, sectionSpacing: 20)

  static let bento = KitbagStyle(
    id: .bento, name: LocalizedStringResource("Bento", table: "Settings"),
    summary: LocalizedStringResource(
      "Tiles of different sizes side by side: the weather next to the next class, tools as tiles.", table: "Settings"),
    radiusScale: 1.2, paddingScale: 1, shadowScale: 0.7, strokeWidth: 0.75, usesMaterial: false,
    todayLayout: .bento, toolsLayout: .tiles, header: .large, sectionSpacing: 12)

  static let editorial = KitbagStyle(
    id: .editorial, name: LocalizedStringResource("Editorial", table: "Settings"),
    summary: LocalizedStringResource(
      "Like a printed page: sharp corners, thin rules, big serif headings and no boxes around the day.",
      table: "Settings"),
    radiusScale: 0.25, paddingScale: 1, shadowScale: 0, strokeWidth: 1, usesMaterial: false,
    todayLayout: .editorial, toolsLayout: .list, header: .editorial, sectionSpacing: 0)

  static let compact = KitbagStyle(
    id: .compact, name: LocalizedStringResource("Compact", table: "Settings"),
    summary: LocalizedStringResource(
      "Small and close together, to see the whole day without scrolling.", table: "Settings"),
    radiusScale: 0.7, paddingScale: 0.7, shadowScale: 0.5, strokeWidth: 0.5, usesMaterial: false,
    todayLayout: .compact, toolsLayout: .smallIcons, header: .compact, sectionSpacing: 10)
}

extension EnvironmentValues {
  @Entry var kitbagStyle: KitbagStyle = .classic
}
