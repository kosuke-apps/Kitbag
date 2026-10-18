import SwiftUI
import WidgetKit

@main
struct KitbagWidgets: WidgetBundle {
  var body: some Widget {
    TimetableWidget()
    DeadlinesWidget()
  }
}

/// Puts Kitbag's theme on a widget: the palette and title typeface for the views, and the theme's gradient behind. A
/// theme that is always dark stays dark on a light home screen.
struct ThemedWidgetModifier: ViewModifier {
  @Environment(\.colorScheme) private var systemScheme
  let theme: KitbagTheme
  /// Replaces the theme's gradient (the small timetable widget takes the colour of its course).
  var background: AnyShapeStyle?

  func body(content: Content) -> some View {
    let scheme = theme.forcedScheme ?? systemScheme
    let palette = theme.palette(for: scheme)
    content
      .environment(\.palette, palette)
      .environment(\.titleDesign, theme.design)
      .environment(\.colorScheme, scheme)
      .containerBackground(for: .widget) {
        if let background {
          Rectangle().fill(background)
        } else {
          LinearGradient(
            colors: [palette.backgroundTop, palette.backgroundBottom], startPoint: .top, endPoint: .bottom)
        }
      }
  }
}

extension View {
  func themedWidget(_ id: ThemeID, background: AnyShapeStyle? = nil) -> some View {
    modifier(ThemedWidgetModifier(theme: .theme(id), background: background))
  }
}
