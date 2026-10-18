import SwiftUI

/// The home screen: today at the top, then the tools as app icons. Tapping one opens it inside Kitbag.
struct HomeView: View {
  @Environment(GuestRuntimes.self) private var guests
  @Environment(LayoutStore.self) private var layout
  @State private var route: ModuleRoute?

  private let columns = [GridItem(.adaptive(minimum: 84), spacing: 16, alignment: .top)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 30) {
        TodayView { route = $0 }
        LazyVGrid(columns: columns, spacing: 24) {
          ForEach(layout.visibleTools) { module in
            ModuleTile(module: module) { route = ModuleRoute(module) }
          }
        }
        SigningFooter()
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 40)
    }
    .themedScreen()
    .fullScreenCover(item: $route) { route in
      ModuleScreen(placement: route.module.homeButtonPlacement, close: { self.route = nil }) {
        route.module.content(guests: guests, route: route)
      }
      .environment(\.openModule) { self.route = $0 }
    }
  }
}
