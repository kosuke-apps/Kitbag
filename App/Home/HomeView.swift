import SwiftUI

/// The home screen: the date pinned at the top, then today below it and the tools as app icons (or tiles, or a list, by
/// the style). Tapping a tool opens it inside Kitbag. Only the part under the date scrolls: it slides beneath the date,
/// which keeps its place.
struct HomeView: View {
  @Environment(GuestRuntimes.self) private var guests
  @Environment(\.kitbagStyle) private var style
  @Environment(DeadlineStore.self) private var deadlines
  @State private var route: ModuleRoute?
  /// A backup file that was opened in Kitbag (AirDrop, Files); the person is asked before it is restored.
  @State private var backupToRestore: URL?
  /// Whether anything has scrolled under the date, which is when the date gets an edge to sit on.
  @State private var scrolledUnder = false
  @State private var restingOffset: CGFloat?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: style.todayLayout == .editorial ? 24 : 30) {
        TodayView { route = $0 }
        ToolsView { route = ModuleRoute($0) }
        SigningFooter { route = ModuleRoute(.settings) }
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 40)
      .background {
        GeometryReader { proxy in
          Color.clear.preference(key: HomeScrollKey.self, value: proxy.frame(in: .named("homeScroll")).minY)
        }
      }
    }
    .coordinateSpace(name: "homeScroll")
    .onPreferenceChange(HomeScrollKey.self) { offset in
      if restingOffset == nil { restingOffset = offset }
      scrolledUnder = offset < (restingOffset ?? offset) - 2
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      TodayHeader { route = $0 }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background {
          Rectangle().fill(.bar).ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .bottom) {
          Divider().opacity(scrolledUnder ? 1 : 0).animation(.easeInOut(duration: 0.15), value: scrolledUnder)
        }
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
    .fullScreenCover(
      item: $route,
      onDismiss: {
        // A reminder set in Headway is waiting by now; give it Headway's icon.
        Task { await deadlines.decorateGuestNotifications() }
      }
    ) { route in
      ModuleScreen(placement: route.module.homeButtonPlacement, close: { self.route = nil }) {
        route.module.content(guests: guests, route: route)
      }
      .environment(\.openModule) { self.route = $0 }
    }
  }
}

/// Where the top of the scrolled content is, so that the date can tell whether something is passing under it.
private struct HomeScrollKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
