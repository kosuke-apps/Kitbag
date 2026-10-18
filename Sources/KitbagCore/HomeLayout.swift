import Foundation

/// Which items of a list are shown and in what order, for the tools on the home screen and for the parts of the Today
/// section. The saved order may be out of date (a tool was added, or one was removed), so it is merged with the items
/// that exist now: new ones are appended, unknown ones dropped.
public struct HomeLayout: Hashable, Codable, Sendable {
  /// The order the person chose, as item ids. May miss new items and may name items that no longer exist.
  public var order: [String]
  /// The items the person hid.
  public var hidden: Set<String>

  public init(order: [String] = [], hidden: Set<String> = []) {
    self.order = order
    self.hidden = hidden
  }

  /// Every existing item in the chosen order, with the new ones at the end.
  public func ordered(known: [String]) -> [String] {
    let present = Set(known)
    var seen = Set<String>()
    var result = order.filter { present.contains($0) && seen.insert($0).inserted }
    result += known.filter { seen.insert($0).inserted }
    return result
  }

  /// The items to show: in the chosen order, without the hidden ones.
  public func visible(known: [String]) -> [String] {
    ordered(known: known).filter { !hidden.contains($0) }
  }

  public func isHidden(_ id: String) -> Bool { hidden.contains(id) }

  public mutating func setHidden(_ id: String, _ isHidden: Bool, known: [String]) {
    order = ordered(known: known)
    if isHidden { hidden.insert(id) } else { hidden.remove(id) }
  }

  /// Moves items like `List.onMove` does, within the full (shown and hidden) order.
  public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, known: [String]) {
    var items = ordered(known: known)
    let moving = source.sorted().map { items[$0] }
    let removedBefore = source.filter { $0 < destination }.count
    for index in source.sorted(by: >) { items.remove(at: index) }
    items.insert(contentsOf: moving, at: destination - removedBefore)
    order = items
  }
}
