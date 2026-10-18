import SwiftUI

/// The home screen: today at the top, then the tools as app icons. Tapping one opens it inside Kitbag.
struct HomeView: View {
  @Environment(GuestRuntimes.self) private var guests
  @State private var route: ModuleRoute?

  private let columns = [GridItem(.adaptive(minimum: 84), spacing: 16, alignment: .top)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        TodayView { route = $0 }
        LazyVGrid(columns: columns, spacing: 24) {
          ForEach(ModuleID.allCases) { module in
            ModuleTile(module: module) { route = ModuleRoute(module) }
          }
        }
      }
      .padding(20)
    }
    .fullScreenCover(item: $route) { route in
      ModuleScreen(close: { self.route = nil }) {
        route.module.content(guests: guests, route: route)
      }
    }
  }
}
