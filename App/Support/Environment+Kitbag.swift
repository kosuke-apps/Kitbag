import SwiftUI

extension EnvironmentValues {
  /// Opens a tool, and where in it to start. The home screen sets it, so that a tool can send the person to another one
  /// (a course to its notes, a note to its course).
  @Entry var openModule: (ModuleRoute) -> Void = { _ in }
}
