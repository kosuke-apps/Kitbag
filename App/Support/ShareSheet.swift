import SwiftUI
import UIKit

/// The system share sheet for a file (AirDrop, Save to Files, Mail), presented from whatever is on top. A SwiftUI
/// `fileExporter` cannot be shown from under a full-screen cover, two of them on one view make only the last work, and a
/// share sheet wrapped in a SwiftUI sheet closes again at once; presenting it from the top view controller avoids all three.
@MainActor
enum ShareSheet {
  static func present(_ url: URL) {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var top = scene?.keyWindow?.rootViewController else { return }
    while let presented = top.presentedViewController { top = presented }
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    controller.popoverPresentationController?.sourceView = top.view
    top.present(controller, animated: true)
  }

  /// Writes `data` to a file called `name` in a fresh temporary folder (so the share sheet shows the real name) and shares it.
  /// Returns false when the file could not be written.
  @discardableResult
  static func present(data: Data, name: String) -> Bool {
    removeOldFolders()
    let folder = FileManager.default.temporaryDirectory.appending(path: "KitbagShare-\(UUID().uuidString)")
    let safe = name.map { "/:\\".contains($0) ? "-" : $0 }
    let url = folder.appending(path: String(safe))
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: url)
    } catch {
      return false
    }
    present(url)
    return true
  }

  /// The folders of earlier shares are left behind for the system to clear; take away the ones from before today, which
  /// are certainly not on screen any more.
  private static func removeOldFolders() {
    let manager = FileManager.default
    let cutoff = Date().addingTimeInterval(-24 * 3600)
    let folders =
      (try? manager.contentsOfDirectory(
        at: manager.temporaryDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    for folder in folders where folder.lastPathComponent.hasPrefix("KitbagShare-") {
      let modified =
        (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      if modified < cutoff { try? manager.removeItem(at: folder) }
    }
  }
}
