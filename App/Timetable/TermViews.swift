import KitbagCore
import SwiftUI

extension Season {
  var title: LocalizedStringResource {
    switch self {
    case .spring: LocalizedStringResource("Spring", table: "Timetable")
    case .summer: LocalizedStringResource("Summer", table: "Timetable")
    case .fall: LocalizedStringResource("Fall", table: "Timetable")
    case .winter: LocalizedStringResource("Winter", table: "Timetable")
    }
  }

  /// The season a month belongs to in the American academic year.
  static func of(month: Int) -> Season {
    switch month {
    case 1...5: .spring
    case 6...8: .summer
    default: .fall
    }
  }

  /// Plausible first and last days of classes, to start from; they are meant to be edited.
  func defaultDates(year: Int) -> (start: LocalDate, end: LocalDate) {
    switch self {
    case .spring: (LocalDate(year: year, month: 1, day: 20), LocalDate(year: year, month: 5, day: 10))
    case .summer: (LocalDate(year: year, month: 6, day: 1), LocalDate(year: year, month: 8, day: 15))
    case .fall: (LocalDate(year: year, month: 9, day: 1), LocalDate(year: year, month: 12, day: 20))
    case .winter: (LocalDate(year: year, month: 1, day: 5), LocalDate(year: year, month: 2, day: 28))
    }
  }
}

extension Timetable {
  /// `2026 Fall`, or the heading when there is no year and season, or a plain word.
  var termName: String {
    if let year, let season { return "\(year) \(String(localized: season.title))" }
    return title.isEmpty ? String(localized: "Untitled term", table: "Timetable") : title
  }

  /// The heading of the printed page: the one that was written, or one made from the term's name.
  var pageHeading: String {
    title.isEmpty ? String(localized: "\(termName) Timetable", table: "Timetable") : title
  }

  /// `Sep 2 – Dec 9, 2026`, or nil when the term has no dates.
  func dateRangeText(calendar: Calendar = .current) -> String? {
    guard let startDate, let endDate else {
      return (startDate ?? endDate).map { $0.date(calendar: calendar).formatted(.dateTime.year().month().day()) }
    }
    let start = startDate.date(calendar: calendar)
    let end = endDate.date(calendar: calendar)
    let sameYear = startDate.year == endDate.year
    let first = start.formatted(
      sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.year().month(.abbreviated).day())
    return "\(first) – \(end.formatted(.dateTime.year().month(.abbreviated).day()))"
  }
}

/// The term at the top of the timetable: its name (a menu to switch terms), its dates, how far along it is, and totals.
struct TermHeader: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.titleDesign) private var design
  @Environment(\.palette) private var palette

  let term: Timetable
  let select: (UUID) -> Void
  let newTerm: () -> Void
  let editTerm: () -> Void

  var body: some View {
    let calendar = Calendar.current
    let today = LocalDate(Date(), calendar: calendar)
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Menu {
          ForEach(store.terms) { other in
            Button {
              select(other.id)
            } label: {
              if other.id == term.id {
                Label(other.termName, systemImage: "checkmark")
              } else {
                Text(other.termName)
              }
            }
          }
          Divider()
          Button(action: newTerm) {
            Label {
              Text("New term…", tableName: "Timetable")
            } icon: {
              Image(systemName: "plus")
            }
          }
          Button(action: editTerm) {
            Label {
              Text("Edit this term…", tableName: "Timetable")
            } icon: {
              Image(systemName: "pencil")
            }
          }
        } label: {
          HStack(spacing: 6) {
            Text(term.termName).font(.system(size: 28, weight: .semibold, design: design))
            Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
          }
          .foregroundStyle(.primary)
        }
        Spacer()
        if term.id == store.timetable.id {
          Text("Current", tableName: "Timetable")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(palette.accent.opacity(0.16), in: Capsule())
            .foregroundStyle(palette.accent)
        }
      }
      if let range = term.dateRangeText(calendar: calendar) {
        HStack(spacing: 6) {
          Label(range, systemImage: "calendar")
          if let week = term.weekNumber(on: today, calendar: calendar), let total = term.totalWeeks(calendar: calendar),
            term.contains(today)
          {
            Text("·")
            Text("Week \(week) of \(total)", tableName: "Timetable")
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        if let start = term.startDate, let end = term.endDate, end > start, term.contains(today) {
          let total = Double(end.days(since: start, calendar: calendar))
          let done = Double(today.days(since: start, calendar: calendar))
          GeometryReader { proxy in
            ZStack(alignment: .leading) {
              Capsule().fill(Color.primary.opacity(0.1))
              Capsule().fill(palette.accent).frame(width: proxy.size.width * min(max(done / total, 0), 1))
            }
          }
          .frame(height: 4)
          .accessibilityHidden(true)
        }
      } else {
        Button(action: editTerm) {
          Label {
            Text("Set the dates of the term", tableName: "Timetable")
          } icon: {
            Image(systemName: "calendar.badge.plus")
          }
          .font(.subheadline)
        }
      }
      Text(summaryText).font(.footnote).foregroundStyle(.secondary)
    }
    .themedCard()
  }

  private var summaryText: String {
    let courses = term.courses.count
    let credits = term.totalCredits
    let creditText = credits == credits.rounded() ? "\(Int(credits))" : String(format: "%.1f", credits)
    return credits > 0
      ? String(localized: "Courses: \(courses) · Credits: \(creditText)", table: "Timetable")
      : String(localized: "Courses: \(courses)", table: "Timetable")
  }
}

/// The form for a term: year and season, the heading of the printed page, its dates, and (for a new one) which term to
/// copy the courses from.
struct TermEditor: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var term: Timetable
  @State private var hasDates: Bool
  @State private var copyFrom: UUID?
  @State private var confirmingDelete = false
  private let isNew: Bool
  private let saved: (UUID) -> Void
  private let deleted: () -> Void

  init(term: Timetable, isNew: Bool, saved: @escaping (UUID) -> Void, deleted: @escaping () -> Void = {}) {
    _term = State(initialValue: term)
    _hasDates = State(initialValue: term.hasDates)
    self.isNew = isNew
    self.saved = saved
    self.deleted = deleted
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Stepper(value: yearBinding, in: 2000...2100) {
            LabeledContent {
              Text(String(yearBinding.wrappedValue))
            } label: {
              Text("Year", tableName: "Timetable")
            }
          }
          Picker(selection: seasonBinding) {
            ForEach(Season.allCases, id: \.self) { season in
              Text(season.title).tag(season)
            }
          } label: {
            Text("Season", tableName: "Timetable")
          }
          TextField(text: $term.title, prompt: Text(term.pageHeading)) {
            Text("Heading of the page", tableName: "Timetable")
          }
        }
        Section {
          Toggle(isOn: $hasDates) {
            Text("Set the dates of the term", tableName: "Timetable")
          }
          if hasDates {
            DatePicker(selection: dateBinding(\.startDate, start: true), displayedComponents: .date) {
              Text("First day of classes", tableName: "Timetable")
            }
            DatePicker(selection: dateBinding(\.endDate, start: false), displayedComponents: .date) {
              Text("Last day of classes", tableName: "Timetable")
            }
            if let start = term.startDate, let end = term.endDate, end < start {
              Text("The last day must not be before the first.", tableName: "Timetable")
                .font(.footnote).foregroundStyle(.red)
            }
          }
        } footer: {
          Text(
            "The dates decide which term is current, the week number, and when classes stop showing.",
            tableName: "Timetable")
        }
        if isNew && !store.terms.isEmpty {
          Section {
            Picker(selection: $copyFrom) {
              Text("Nothing", tableName: "Timetable").tag(UUID?.none)
              ForEach(store.terms) { other in
                Text(other.termName).tag(Optional(other.id))
              }
            } label: {
              Text("Start with the courses of", tableName: "Timetable")
            }
          } footer: {
            Text("The courses are copied without grades; change what differs.", tableName: "Timetable")
          }
        }
        if !isNew {
          Section {
            Button(role: .destructive) {
              confirmingDelete = true
            } label: {
              Text("Delete this term", tableName: "Timetable")
            }
          }
        }
      }
      .navigationTitle(isNew ? Text("New term", tableName: "Timetable") : Text("Edit term", tableName: "Timetable"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel", tableName: "Timetable")
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(action: save) { Text("Save", tableName: "Timetable") }
            .disabled(!canSave)
        }
      }
      .confirmationDialog(
        Text("Delete this term and its courses?", tableName: "Timetable"), isPresented: $confirmingDelete,
        titleVisibility: .visible
      ) {
        Button(role: .destructive) {
          store.deleteTerm(id: term.id)
          deleted()
          dismiss()
        } label: {
          Text("Delete", tableName: "Timetable")
        }
      }
      .onChange(of: hasDates) { _, on in
        if on, term.startDate == nil {
          let dates = (term.season ?? .fall).defaultDates(year: term.year ?? 2026)
          term.startDate = dates.start
          term.endDate = dates.end
        }
      }
    }
  }

  private var canSave: Bool {
    guard hasDates, let start = term.startDate, let end = term.endDate else { return true }
    return end >= start
  }

  private func save() {
    var saved = term
    saved.title = saved.title.trimmingCharacters(in: .whitespaces)
    if !hasDates {
      saved.startDate = nil
      saved.endDate = nil
    }
    if isNew, let copyFrom, let source = store.term(id: copyFrom) {
      saved.courses = TimetableLibrary().continuing(from: source)
    }
    store.upsertTerm(saved)
    self.saved(saved.id)
    dismiss()
  }

  private var yearBinding: Binding<Int> {
    Binding(get: { term.year ?? Calendar.current.component(.year, from: Date()) }, set: { term.year = $0 })
  }

  private var seasonBinding: Binding<Season> {
    Binding(
      get: { term.season ?? Season.of(month: Calendar.current.component(.month, from: Date())) },
      set: { term.season = $0 })
  }

  private func dateBinding(_ keyPath: WritableKeyPath<Timetable, LocalDate?>, start: Bool) -> Binding<Date> {
    Binding(
      get: {
        let defaults = (term.season ?? .fall).defaultDates(year: term.year ?? 2026)
        return (term[keyPath: keyPath] ?? (start ? defaults.start : defaults.end)).date(calendar: .current)
      },
      set: { term[keyPath: keyPath] = LocalDate($0, calendar: .current) })
  }
}
