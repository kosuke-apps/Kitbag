import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }

  var title: LocalizedStringResource {
    switch self {
    case .system: LocalizedStringResource("System", table: "Settings")
    case .light: LocalizedStringResource("Light", table: "Settings")
    case .dark: LocalizedStringResource("Dark", table: "Settings")
    }
  }
}

/// The chosen theme and appearance, kept in UserDefaults.
@MainActor
@Observable
final class ThemeStore {
  var themeID: ThemeID {
    didSet { defaults.set(themeID.rawValue, forKey: "kitbag.theme") }
  }
  var appearance: AppearanceMode {
    didSet { defaults.set(appearance.rawValue, forKey: "kitbag.appearance") }
  }
  /// The look apart from the colours (`Style.swift`).
  var styleID: StyleID {
    didSet { defaults.set(styleID.rawValue, forKey: "kitbag.style") }
  }

  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    themeID = ThemeID(rawValue: defaults.string(forKey: "kitbag.theme") ?? "") ?? .ivory
    appearance = AppearanceMode(rawValue: defaults.string(forKey: "kitbag.appearance") ?? "") ?? .system
    styleID = StyleID(rawValue: defaults.string(forKey: "kitbag.style") ?? "") ?? .classic
  }

  /// Reads the choices again, after a backup was restored.
  func reload() {
    themeID = ThemeID(rawValue: defaults.string(forKey: "kitbag.theme") ?? "") ?? .ivory
    appearance = AppearanceMode(rawValue: defaults.string(forKey: "kitbag.appearance") ?? "") ?? .system
    styleID = StyleID(rawValue: defaults.string(forKey: "kitbag.style") ?? "") ?? .classic
  }

  var theme: KitbagTheme { .theme(themeID) }
  var style: KitbagStyle { .style(styleID) }

  /// The scheme to force: the theme's own (a dark theme), or else the person's choice; nil follows the system.
  var preferredScheme: ColorScheme? { theme.forcedScheme ?? appearance.colorScheme }
}

/// Applies the chosen theme to everything inside: colours, the accent, the typeface of titles and the scheme.
struct ThemeRoot<Content: View>: View {
  @Environment(ThemeStore.self) private var store
  @ViewBuilder var content: Content

  var body: some View {
    ThemeEnvironment(theme: store.theme, style: store.style) { content }
      .background { WindowAppearance(scheme: store.preferredScheme) }
  }
}

/// Reads the colour scheme that is in effect (the window's, see `WindowAppearance`) and hands down the matching palette.
private struct ThemeEnvironment<Content: View>: View {
  @Environment(\.colorScheme) private var scheme
  let theme: KitbagTheme
  let style: KitbagStyle
  @ViewBuilder var content: Content

  var body: some View {
    let palette = theme.palette(for: scheme)
    content
      .environment(\.palette, palette)
      .environment(\.titleDesign, theme.design)
      .environment(\.kitbagStyle, style)
      .tint(palette.accent)
  }
}
