import KitbagCore
import SwiftUI

/// The calendar tool: a month page with the day's classes and deadlines under it, or the list of what is coming up.
struct CalendarView: View {
  @Environment(DeadlineStore.self) private var deadlines

  private enum Mode: Hashable {
    case month
    case upcoming
  }

  @State private var mode: Mode = .month
  @State private var month: MonthGrid
  @State private var selected: LocalDate
  @State private var editing: Deadline?
  @State private var showingDone = false

  /// Opens on `initialDay` (today when nil).
  init(initialDay: LocalDate? = nil) {
    let day = initialDay ?? LocalDate(Date(), calendar: .current)
    _selected = State(initialValue: day)
    _month = State(initialValue: MonthGrid(containing: day, calendar: .current))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 8) {
        Picker(selection: $mode) {
          Text("Month", tableName: "Calendar").tag(Mode.month)
          Text("Upcoming", tableName: "Calendar").tag(Mode.upcoming)
        } label: {
          Text("View", tableName: "Calendar")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        switch mode {
        case .month: monthContent
        case .upcoming: upcomingContent
        }
      }
      .overlay(alignment: .bottomTrailing) { addButton }
      .navigationTitle(Text("Calendar", tableName: "Calendar"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: goToToday) { Text("Today", tableName: "Calendar") }
        }
      }
    }
    .sheet(item: $editing) { deadline in
      DeadlineEditor(deadline: deadline, isNew: !deadlines.book.deadlines.contains { $0.id == deadline.id })
    }
  }

  // MARK: Month

  private var monthContent: some View {
    ScrollView {
      VStack(spacing: 14) {
        notices
        MonthHeader(
          month: month, previous: { move(by: -1) }, next: { move(by: 1) })
        MonthGridView(month: month, selected: $selected, book: deadlines.book)
        DayAgenda(day: selected) { editing = $0 }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 96)
    }
  }

  // MARK: Upcoming

  private struct DeadlineGroup: Identifiable {
    let bucket: DeadlineBucket
    let deadlines: [Deadline]
    var id: DeadlineBucket { bucket }
  }

  private var upcomingContent: some View {
    let calendar = Calendar.current
    let now = Date()
    let groups = deadlines.book.grouped(now: now, calendar: calendar).map {
      DeadlineGroup(bucket: $0.bucket, deadlines: $0.deadlines)
    }
    let done = deadlines.book.done(calendar: calendar)
    return List {
      if groups.isEmpty && done.isEmpty {
        ContentUnavailableView {
          Label {
            Text("No deadlines", tableName: "Calendar")
          } icon: {
            Image(systemName: "checkmark.circle")
          }
        } description: {
          Text("Add an exam or an assignment with the + button.", tableName: "Calendar")
        }
        .listRowBackground(Color.clear)
      }
      ForEach(groups) { group in
        Section {
          ForEach(group.deadlines) { item in
            DeadlineRow(deadline: item, showsDate: true) { editing = item }
              .swipeActions { deleteButton(item) }
          }
        } header: {
          Text(group.bucket.title)
        }
      }
      if !done.isEmpty {
        Section {
          if showingDone {
            ForEach(done) { item in
              DeadlineRow(deadline: item, showsDate: true) { editing = item }
                .swipeActions { deleteButton(item) }
            }
          }
        } header: {
          Button {
            withAnimation { showingDone.toggle() }
          } label: {
            HStack {
              Text("Done", tableName: "Calendar")
              Image(systemName: showingDone ? "chevron.down" : "chevron.right").font(.caption2)
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
    .listStyle(.insetGrouped)
    .contentMargins(.bottom, 80, for: .scrollContent)
  }

  private func deleteButton(_ item: Deadline) -> some View {
    Button(role: .destructive) {
      deadlines.remove(id: item.id)
    } label: {
      Label {
        Text("Delete", tableName: "Calendar")
      } icon: {
        Image(systemName: "trash")
      }
    }
  }

  // MARK: Parts

  @ViewBuilder private var notices: some View {
    if deadlines.setAsideUnreadableFile {
      notice(
        Text(
          "The saved deadlines could not be read. They were kept as a separate file and a new list was started.",
          tableName: "Calendar"))
    }
    if deadlines.saveFailed {
      notice(Text("The deadlines could not be saved.", tableName: "Calendar"))
    }
  }

  private func notice(_ message: Text) -> some View {
    HStack(alignment: .top) {
      message.font(.footnote)
      Spacer(minLength: 8)
      Button {
        deadlines.dismissNotices()
      } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
      }
      .accessibilityLabel(Text("Dismiss", tableName: "Calendar"))
    }
    .padding(10)
    .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
  }

  /// A round button at the bottom right, within reach of the thumb.
  private var addButton: some View {
    Button {
      editing = Deadline(title: "", date: mode == .month ? selected : LocalDate(Date(), calendar: .current))
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 56, height: 56)
        .background(Color.accentColor, in: Circle())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
    .accessibilityLabel(Text("Add a deadline", tableName: "Calendar"))
    .padding(20)
  }

  private func move(by months: Int) {
    month = month.shifted(by: months, calendar: .current)
    if !month.contains(selected) { selected = month.month }
  }

  private func goToToday() {
    let today = LocalDate(Date(), calendar: .current)
    selected = today
    month = MonthGrid(containing: today, calendar: .current)
  }
}
