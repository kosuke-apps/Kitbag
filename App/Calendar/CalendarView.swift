import KitbagCore
import SwiftUI
import UniformTypeIdentifiers

/// The calendar tool: a month page with the day's classes and deadlines under it, or the list of what is coming up.
struct CalendarView: View {
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(TimetableStore.self) private var timetable
  @Environment(SubscriptionStore.self) private var subscriptions
  @Environment(NotificationPreferencesStore.self) private var notificationPreferences
  @Environment(\.palette) private var palette

  private enum Mode: Hashable {
    case month
    case upcoming
  }

  @State private var mode: Mode = .month
  @State private var month: MonthGrid
  @State private var selected: LocalDate
  @State private var editing: Deadline?
  @State private var showingDone = false
  @State private var showingImporter = false
  @State private var preview: ImportPreview?
  @State private var showingSubscriptions = false
  @State private var exportDocument = ExportDocument(data: Data())
  @State private var exportType = UTType.calendarEvent
  @State private var exportName = "Deadlines"
  @State private var showingExporter = false
  @State private var message: Text?
  @State private var externalCounts: [LocalDate: Int] = [:]

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
      .themedScreen()
      .overlay(alignment: .bottomTrailing) { addButton }
      .navigationTitle(Text("Calendar", tableName: "Calendar"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarLeading) {
          Button(action: goToToday) { Text("Today", tableName: "Calendar") }
          transferMenu
        }
      }
    }
    .sheet(item: $editing) { deadline in
      DeadlineEditor(deadline: deadline, isNew: !deadlines.book.deadlines.contains { $0.id == deadline.id })
    }
    .sheet(item: $preview) { preview in ImportPreviewSheet(candidates: preview.candidates) }
    .sheet(isPresented: $showingSubscriptions) { SubscriptionsView() }
    .fileImporter(
      isPresented: $showingImporter,
      allowedContentTypes: [.calendarEvent, .json, UTType(filenameExtension: "ics") ?? .calendarEvent]
    ) { result in
      if let url = try? result.get() {
        handleImport(url)
      } else {
        message = Text("Could not read that file.", tableName: "Calendar")
      }
    }
    .fileExporter(
      isPresented: $showingExporter, document: exportDocument, contentType: exportType, defaultFilename: exportName
    ) { _ in }
    .alert(
      Text("Calendar", tableName: "Calendar"),
      isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    ) {
      Button {
      } label: {
        Text("OK", tableName: "Calendar")
      }
    } message: {
      if let message { message }
    }
    .task(id: externalKey) { externalCounts = counts() }
    .task { await subscriptions.refreshStale() }
  }

  // MARK: Month

  private var monthContent: some View {
    ScrollView {
      VStack(spacing: 14) {
        notices
        MonthHeader(
          month: month, previous: { move(by: -1) }, next: { move(by: 1) })
        MonthGridView(month: month, selected: $selected, book: deadlines.book, externalCounts: externalCounts)
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
        .listRowBackground(palette.card)
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
    .scrollContentBackground(.hidden)
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

  // MARK: Files and subscriptions

  private var transferMenu: some View {
    Menu {
      Button {
        showingImporter = true
      } label: {
        Label {
          Text("Import a file…", tableName: "Calendar")
        } icon: {
          Image(systemName: "square.and.arrow.down")
        }
      }
      Menu {
        Button {
          exportDeadlines()
        } label: {
          Text("Deadlines (.ics)", tableName: "Calendar")
        }
        Button {
          exportClasses()
        } label: {
          Text("Classes of this term (.ics)", tableName: "Calendar")
        }
        Button {
          exportJSON()
        } label: {
          Text("Deadlines (Kitbag file)", tableName: "Calendar")
        }
      } label: {
        Label {
          Text("Export…", tableName: "Calendar")
        } icon: {
          Image(systemName: "square.and.arrow.up")
        }
      }
      Divider()
      Button {
        showingSubscriptions = true
      } label: {
        Label {
          Text("Subscriptions…", tableName: "Calendar")
        } icon: {
          Image(systemName: "antenna.radiowaves.left.and.right")
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel(Text("Calendar options", tableName: "Calendar"))
  }

  private func handleImport(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else {
      message = Text("Could not read that file.", tableName: "Calendar")
      return
    }
    if url.pathExtension.lowercased() == "json" {
      guard let book = try? DeadlineBook(fileData: data) else {
        message = Text("Could not read that file.", tableName: "Calendar")
        return
      }
      deadlines.importDeadlines(book.deadlines) { timetable.course(id: $0)?.code }
      message = Text("Imported \(book.deadlines.count) deadlines.", tableName: "Calendar")
      return
    }
    let events = ICalendar.parse(String(decoding: data, as: UTF8.self), defaultTimeZone: .current)
    guard !events.isEmpty else {
      message = Text("There are no events in that file.", tableName: "Calendar")
      return
    }
    let now = Date()
    let window = DateInterval(start: now.addingTimeInterval(-60 * 86400), end: now.addingTimeInterval(400 * 86400))
    let candidates = DeadlineImport.deadlines(
      from: events, courses: timetable.timetable.courses, existing: deadlines.book.deadlines, calendar: .current,
      window: window, defaultAlerts: { notificationPreferences.preferences.alerts(for: $0) })
    if candidates.isEmpty {
      message = Text("There is nothing in that file within the coming year.", tableName: "Calendar")
    } else {
      preview = ImportPreview(candidates: candidates)
    }
  }

  private func exportDeadlines() {
    let text = ICSWriter.deadlines(
      deadlines.book.deadlines, courseCode: { timetable.course(id: $0)?.code }, calendar: .current,
      allDayTime: notificationPreferences.preferences.allDayTime)
    present(Data(text.utf8), .calendarEvent, "Deadlines")
  }

  private func exportClasses() {
    let term = timetable.timetable
    present(Data(ICSWriter.classes(of: term, calendar: .current).utf8), .calendarEvent, term.termName)
  }

  private func exportJSON() {
    guard let data = try? deadlines.book.fileData() else { return }
    present(data, .json, "Deadlines")
  }

  private func present(_ data: Data, _ type: UTType, _ name: String) {
    exportDocument = ExportDocument(data: data)
    exportType = type
    exportName = name
    showingExporter = true
  }

  /// Changes when the month shown or a subscription's events change, so that the dots are worked out again.
  private var externalKey: String {
    "\(month.month.text)|"
      + subscriptions.subscriptions.map { "\($0.id)\($0.lastFetched?.timeIntervalSince1970 ?? 0)" }.joined()
  }

  private func counts() -> [LocalDate: Int] {
    guard let first = month.weeks.first?.first, let last = month.weeks.last?.last else { return [:] }
    return subscriptions.counts(from: first, to: last, calendar: .current)
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
