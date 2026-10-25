import Foundation
import Testing

@testable import KitbagCore

/// Data saved by Kitbag 0.4.2 and earlier, when the four presets were fixed scales that only existed in the code. From
/// 0.5.0 every scale is the person's own, and a copy of each preset that something refers to is added to theirs (with the
/// same id), so the GPA must come out as it did.
struct GradeScaleMigrationTests {
  /// A `timetables.json` as 0.4.2 wrote it (file version 2). One term names no scale and so uses the one chosen for the
  /// GPA screen; one names a preset by its id; one by an id from the first versions; one names a scale the person wrote.
  private let timetablesJSON = """
    {"version": 2, "timetables": [
      {"id": "11111111-1111-1111-1111-111111111111", "title": "Term A", "year": 2026, "season": "fall",
       "courses": [{"code": "MATH 1", "credits": 3, "grade": "A"}, {"code": "PHYS 1", "credits": 3, "grade": "AB"}]},
      {"id": "22222222-2222-2222-2222-222222222222", "title": "2024 First semester", "gradeScaleID": "japan-aa",
       "gradesOnly": true,
       "courses": [{"code": "X", "credits": 2, "grade": "AA"}, {"code": "Y", "credits": 2, "grade": "B"}]},
      {"id": "33333333-3333-3333-3333-333333333333", "title": "2023 Second semester", "gradeScaleID": "tohoku",
       "gradesOnly": true, "courses": [{"code": "Z", "credits": 4, "grade": "A"}]},
      {"id": "44444444-4444-4444-4444-444444444444", "title": "Abroad", "gradeScaleID": "custom-1",
       "courses": [{"code": "W", "credits": 3, "grade": "2"}, {"code": "V", "credits": 3, "grade": "Pass"}]}
    ]}
    """

  /// `kitbag.customGradeScales` as 0.4.2 wrote it.
  private let customScalesJSON = """
    [{"id": "custom-1", "name": "Abroad", "grades": [
      {"label": "1", "points": 4, "earnsCredit": true}, {"label": "2", "points": 3, "earnsCredit": true},
      {"label": "3", "points": 2, "earnsCredit": true}, {"label": "4", "points": 0, "earnsCredit": false},
      {"label": "Pass", "earnsCredit": true}]}]
    """

  private func library() throws -> TimetableLibrary {
    try TimetableLibrary(fileData: Data(timetablesJSON.utf8))
  }

  private func customScales() throws -> [GradeScale] {
    try JSONDecoder().decode([GradeScale].self, from: Data(customScalesJSON.utf8))
  }

  /// What a term is worked out on, given how an id becomes a scale.
  private func inputs(_ terms: [Timetable], chosen: String?, scale: (String) -> GradeScale) -> [GPA.TermInput] {
    terms.map { term in
      let entries = term.courses.compactMap { course in
        course.credits.map { GPA.Entry(credits: $0, grade: course.grade, mode: course.gpaMode) }
      }
      return GPA.TermInput(
        entries: entries, scale: scale(term.gradeScaleID ?? chosen ?? GradeScale.usAB.id),
        included: term.countsInCumulativeGPA)
    }
  }

  @Test(arguments: [nil, "us-ab", "uw-madison"] as [String?])
  func savedDataOf042GivesTheSameGPAAfterTheCopiesAreAdopted(chosen: String?) throws {
    let terms = try library().ordered
    let own = try customScales()

    // 0.4.2: the four presets were fixed, the person's own came after them.
    let before = inputs(terms, chosen: chosen) { id in
      (GradeScale.presets + own).first { $0.id == GradeScale.canonicalID(id) } ?? GradeScale.usAB
    }

    // 0.5.0: the person's scales, plus a copy of each preset that something refers to, as the app does at launch.
    let inUse = GradeScale.idsInUse(termScaleIDs: terms.map(\.gradeScaleID), chosen: chosen)
    let adopted = GradeScale.presetsToAdopt(inUse: inUse, among: own)
    let mine = own + adopted
    // What the store keeps in UserDefaults and reads at the next launch.
    let reloaded = try JSONDecoder().decode([GradeScale].self, from: try JSONEncoder().encode(mine))
    let after = inputs(terms, chosen: chosen) { GradeScale.scale(id: $0, custom: reloaded) }

    #expect(inUse == ["us-ab", "japan-aa", "custom-1"])
    #expect(adopted.map(\.id) == ["us-ab", "japan-aa"])
    // Every scale that something refers to is among the person's own, so that lists and pickers show it...
    #expect(inUse.allSatisfy { id in reloaded.contains { $0.id == id } })
    // ...and is the preset it was, grade for grade.
    #expect(reloaded.first { $0.id == "japan-aa" }?.grades == GradeScale.japanAA.grades)
    #expect(reloaded.first { $0.id == "us-ab" }?.grades == GradeScale.usAB.grades)

    // Each term's result, and the cumulative one, are the same, and equal to the numbers worked out by hand:
    // Term A on the first preset: 3 x 4.0 + 3 x 3.5 = 22.5 points for 6 credits. The two terms on the AA preset (one by
    // an id from the first versions): 2 x 4 + 2 x 2 = 12 for 4, and 4 x 3 = 12 for 4. The person's own scale: 3 x 3 = 9
    // for 3 credits (the pass has no points). Together 55.5 points for 17 credits.
    for (old, new) in zip(before, after) {
      #expect(GPA.result(of: old.entries, scale: old.scale) == GPA.result(of: new.entries, scale: new.scale))
    }
    let expected = [(22.5, 6.0), (12.0, 4.0), (12.0, 4.0), (9.0, 3.0)]
    for (index, term) in after.enumerated() {
      let result = GPA.result(of: term.entries, scale: term.scale)
      #expect(result?.points == expected[index].0)
      #expect(result?.credits == expected[index].1)
    }
    #expect(GPA.cumulative(before) == GPA.cumulative(after))
    #expect(GPA.cumulative(after) == GPA.Result(credits: 17, points: 55.5))
    // The grades of every course are found on the scale the course's term uses, as the grade picker needs.
    for (term, input) in zip(terms, after) {
      #expect(term.courses.compactMap(\.grade).allSatisfy { input.scale.contains($0) })
    }
  }

  @Test func aSecondLaunchAddsNothingMore() throws {
    let terms = try library().ordered
    let own = try customScales()
    let inUse = GradeScale.idsInUse(termScaleIDs: terms.map(\.gradeScaleID), chosen: nil)
    let mine = own + GradeScale.presetsToAdopt(inUse: inUse, among: own)
    #expect(GradeScale.presetsToAdopt(inUse: inUse, among: mine).isEmpty)
  }

  @Test func aPresetThePersonChangedKeepsTheirChangeAtTheNextLaunch() throws {
    var changed = GradeScale.japanAA
    changed.grades[0].points = 4.3
    let inUse = GradeScale.idsInUse(termScaleIDs: ["japan-aa"], chosen: "japan-aa")
    // The copy is the person's: nothing is added over it, and it is the one that is used.
    #expect(GradeScale.presetsToAdopt(inUse: inUse, among: [changed]).isEmpty)
    #expect(GradeScale.scale(id: "japan-aa", custom: [changed]).points(for: "AA") == 4.3)
  }
}
