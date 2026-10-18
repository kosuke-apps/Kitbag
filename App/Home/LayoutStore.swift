import KitbagCore
import Observation
import SwiftUI

/// The parts of the Today section that can be shown, hidden and reordered.
enum TodaySection: String, CaseIterable, Identifiable {
  case weather
  case nextClass
  case todaysClasses
  case dueSoon
  case pinnedNotes

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .weather: LocalizedStringResource("Weather", table: "Settings")
    case .nextClass: LocalizedStringResource("Next class", table: "Settings")
    case .todaysClasses: LocalizedStringResource("Today's classes", table: "Settings")
    case .dueSoon: LocalizedStringResource("Due soon", table: "Settings")
    case .pinnedNotes: LocalizedStringResource("Pinned notes", table: "Settings")
    }
  }

  var symbol: String {
    switch self {
    case .weather: "cloud.sun"
    case .nextClass: "clock"
    case .todaysClasses: "list.bullet"
    case .dueSoon: "exclamationmark.circle"
    case .pinnedNotes: "pin"
    }
  }
}

/// Which tools and which parts of Today are shown, and in what order. Kept in UserDefaults.
@MainActor
@Observable
final class LayoutStore {
  private(set) var tools: HomeLayout
  private(set) var sections: HomeLayout
  @ObservationIgnored private let defaults: UserDefaults

  private let toolIDs = ModuleID.allCases.map(\.rawValue)
  private let sectionIDs = TodaySection.allCases.map(\.rawValue)

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    tools = Self.load("kitbag.layout.tools", from: defaults)
    sections = Self.load("kitbag.layout.sections", from: defaults)
  }

  private static func load(_ key: String, from defaults: UserDefaults) -> HomeLayout {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(HomeLayout.self, from: $0) } ?? HomeLayout()
  }

  private func save(_ layout: HomeLayout, key: String) {
    if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: key) }
  }

  // MARK: Tools

  /// Every tool in the chosen order, shown or not, for the settings list.
  var orderedTools: [ModuleID] {
    tools.ordered(known: toolIDs).compactMap(ModuleID.init(rawValue:))
  }

  /// The tools on the home screen. Settings is always there, so that it can always be reached.
  var visibleTools: [ModuleID] {
    var visible = tools.visible(known: toolIDs).compactMap(ModuleID.init(rawValue:))
    if !visible.contains(.settings) { visible.append(.settings) }
    return visible
  }

  func isHidden(_ tool: ModuleID) -> Bool { tool != .settings && tools.isHidden(tool.rawValue) }

  func setHidden(_ tool: ModuleID, _ hidden: Bool) {
    guard tool != .settings else { return }
    tools.setHidden(tool.rawValue, hidden, known: toolIDs)
    save(tools, key: "kitbag.layout.tools")
  }

  func moveTools(from source: IndexSet, to destination: Int) {
    tools.move(fromOffsets: source, toOffset: destination, known: toolIDs)
    save(tools, key: "kitbag.layout.tools")
  }

  // MARK: Today

  var orderedSections: [TodaySection] {
    sections.ordered(known: sectionIDs).compactMap(TodaySection.init(rawValue:))
  }

  var visibleSections: [TodaySection] {
    sections.visible(known: sectionIDs).compactMap(TodaySection.init(rawValue:))
  }

  func isHidden(_ section: TodaySection) -> Bool { sections.isHidden(section.rawValue) }

  func setHidden(_ section: TodaySection, _ hidden: Bool) {
    sections.setHidden(section.rawValue, hidden, known: sectionIDs)
    save(sections, key: "kitbag.layout.sections")
  }

  func moveSections(from source: IndexSet, to destination: Int) {
    sections.move(fromOffsets: source, toOffset: destination, known: sectionIDs)
    save(sections, key: "kitbag.layout.sections")
  }
}
