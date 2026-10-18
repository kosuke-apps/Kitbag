import Foundation
import Testing

@testable import KitbagCore

@Suite("HomeLayout")
struct HomeLayoutTests {
  private let known = ["a", "b", "c", "d"]

  @Test func keepsTheDefaultOrderWhenNothingWasChosen() {
    #expect(HomeLayout().ordered(known: known) == known)
    #expect(HomeLayout().visible(known: known) == known)
  }

  @Test func followsTheChosenOrderAndAppendsNewItems() {
    let layout = HomeLayout(order: ["c", "a"])
    #expect(layout.ordered(known: known) == ["c", "a", "b", "d"])
  }

  @Test func dropsItemsThatNoLongerExistAndDuplicates() {
    let layout = HomeLayout(order: ["gone", "b", "b", "a"])
    #expect(layout.ordered(known: known) == ["b", "a", "c", "d"])
  }

  @Test func hidesItemsWithoutLosingTheirPlace() {
    var layout = HomeLayout(order: ["d", "c", "b", "a"])
    layout.setHidden("c", true, known: known)
    #expect(layout.visible(known: known) == ["d", "b", "a"])
    #expect(layout.ordered(known: known) == ["d", "c", "b", "a"])
    #expect(layout.isHidden("c"))
    layout.setHidden("c", false, known: known)
    #expect(layout.visible(known: known) == ["d", "c", "b", "a"])
  }

  @Test func movesLikeAList() {
    var layout = HomeLayout()
    layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 3, known: known)
    #expect(layout.ordered(known: known) == ["b", "c", "a", "d"])
    layout.move(fromOffsets: IndexSet(integer: 3), toOffset: 0, known: known)
    #expect(layout.ordered(known: known) == ["d", "b", "c", "a"])
    layout.move(fromOffsets: IndexSet(integer: 1), toOffset: 4, known: known)
    #expect(layout.ordered(known: known) == ["d", "c", "a", "b"])
  }

  @Test func movesSeveralItemsAtOnce() {
    var layout = HomeLayout()
    layout.move(fromOffsets: IndexSet([0, 1]), toOffset: 4, known: known)
    #expect(layout.ordered(known: known) == ["c", "d", "a", "b"])
  }

  @Test func roundTripsThroughJSON() throws {
    var layout = HomeLayout(order: ["b", "a"])
    layout.setHidden("a", true, known: known)
    let data = try JSONEncoder().encode(layout)
    #expect(try JSONDecoder().decode(HomeLayout.self, from: data) == layout)
  }
}
