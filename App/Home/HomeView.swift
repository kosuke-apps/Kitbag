import SwiftUI

/// The home screen: today at the top, then the tools as app icons. Tapping one opens it inside Kitbag.
struct HomeView: View {
  @Environment(GuestRuntimes.self) private var guests
  @Environment(LayoutStore.self) private var layout
  @State private var route: ModuleRoute?
  /// A backup file that was opened in Kitbag (AirDrop, Files); the person is asked before it is restored.
  @State private var backupToRestore: URL?

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
        SigningFooter { route = ModuleRoute(.settings) }
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 40)
    }
    .themedScreen()
    .onOpenURL { url in
      if url.isFileURL {
        // A backup sent to Kitbag. Close any open tool first, so that the question can be shown.
        route = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { backupToRestore = url }
        return
      }
      // kitbag://timetable, kitbag://calendar: the widgets open a tool this way.
      guard url.scheme == "kitbag", let host = url.host, let module = ModuleID(rawValue: host) else { return }
      route = ModuleRoute(module)
    }
    .restoreBackup($backupToRestore)
    .fullScreenCover(item: $route) { route in
      ModuleScreen(placement: route.module.homeButtonPlacement, close: { self.route = nil }) {
        route.module.content(guests: guests, route: route)
      }
      .environment(\.openModule) { self.route = $0 }
    }
  }
}
