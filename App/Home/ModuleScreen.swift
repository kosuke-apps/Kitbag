import SwiftUI

/// A tool shown full screen, with the house button at the top right that returns to the home screen.
struct ModuleScreen<Content: View>: View {
  let close: () -> Void
  @ViewBuilder var content: Content

  var body: some View {
    content
      .overlay(alignment: .topTrailing) {
        HomeButton(action: close)
      }
  }
}

/// A round house button, in the same shape as the round buttons a tool draws on its map. The glyph takes the accent
/// colour so that it stands out without shouting.
struct HomeButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "house.fill")
        .font(.system(size: 18, weight: .semibold))
        .frame(width: 44, height: 44)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .contentShape(Circle())
    }
    .accessibilityLabel(Text("Home", tableName: "Shell"))
    .padding(.trailing, 14)
    .padding(.top, 1)
  }
}
