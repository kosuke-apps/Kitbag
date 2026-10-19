import KitbagCore
import Network
import Observation

/// What kind of connection the phone is on, for the choices about data: Wi-Fi, mobile data (a personal hotspot counts, as
/// iOS calls both "expensive"), or Low Data Mode on any connection ("constrained"). `connection` is read when something
/// is about to be fetched, straight from the network monitor, so it is never older than the last change.
@MainActor
@Observable
final class NetworkCondition {
  static let shared = NetworkCondition()

  /// What the connection was at the last change, for a screen to show and redraw on.
  private(set) var shown: Connection = .wifi
  private(set) var isOnline = true

  @ObservationIgnored private let monitor = NWPathMonitor()
  @ObservationIgnored private var started = false

  /// Starts watching the connection; harmless to call again.
  func start() {
    guard !started else { return }
    started = true
    monitor.pathUpdateHandler = { [weak self] path in
      let connection = Self.connection(of: path)
      let online = path.status == .satisfied
      Task { @MainActor in
        self?.shown = connection
        self?.isOnline = online
      }
    }
    monitor.start(queue: DispatchQueue(label: "dev.kosuke.kitbag.network"))
  }

  /// The connection now.
  var connection: Connection { Self.connection(of: monitor.currentPath) }

  nonisolated private static func connection(of path: NWPath) -> Connection {
    if path.isConstrained { return .lowData }
    return path.isExpensive ? .mobile : .wifi
  }
}
