import KitbagCore
import SwiftUI
import UniformTypeIdentifiers

/// The timetable tool: the week as a grid, the legend under it, and the menu to edit, import and export.
struct TimetableView: View {
  @Environment(TimetableStore.self) private var store

  private enum Sheet: Identifiable {
    case detail(Timetable.Slot)
    case courses
    case editor(Course)

    var id: String {
      switch self {
      case .detail(let slot): "detail-\(slot.id)"
      case .courses: "courses"
      case .editor(let course): "editor-\(course.id)"
      }
    }
  }

  @State private var sheet: Sheet?
  @State private var showingImporter = false
  @State private var showingExporter = false
  @State private var importFailed = false

  var body: some View {
    NavigationStack {
      Group {
        if store.timetable.courses.isEmpty {
          emptyState
        } else {
          content
        }
      }
      .themedScreen()
      .navigationTitle(Text("Timetable", tableName: "Timetable"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { menu }
      }
    }
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .detail(let slot):
        ClassDetailSheet(slot: slot) { self.sheet = .editor(slot.course) }
      case .courses:
        CourseListView()
      case .editor(let course):
        CourseEditor(course: course, isNew: !store.timetable.courses.contains { $0.id == course.id })
      }
    }
    .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
      do {
        try store.importFile(at: try result.get())
      } catch {
        importFailed = true
      }
    }
    .fileExporter(
      isPresented: $showingExporter, document: TimetableDocument(timetable: store.timetable), contentType: .json,
      defaultFilename: "Timetable"
    ) { _ in }
    .alert(Text("Could not read that file.", tableName: "Timetable"), isPresented: $importFailed) {
      Button {
      } label: {
        Text("OK", tableName: "Timetable")
      }
    } message: {
      Text("Choose a timetable file that Kitbag exported.", tableName: "Timetable")
    }
  }

  // MARK: Parts

  private var content: some View {
    ScrollView {
      VStack(spacing: 12) {
        notices
        if !store.timetable.title.isEmpty {
          Text(store.timetable.title)
            .font(.title3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.15))
        }
        TimetableGrid(timetable: store.timetable) { sheet = .detail($0) }
        VStack(alignment: .leading, spacing: 6) {
          Text("Courses", tableName: "Timetable")
            .font(.title3)
            .padding(.horizontal, 4)
            .background(Color.secondary.opacity(0.15))
          TimetableLegend(courses: store.timetable.courses)
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 24)
    }
  }

  @ViewBuilder private var notices: some View {
    if store.setAsideUnreadableFile {
      notice(
        Text(
          "The saved timetable could not be read. It was kept as a separate file and a new timetable was started.",
          tableName: "Timetable"))
    }
    if store.saveFailed {
      notice(Text("The timetable could not be saved.", tableName: "Timetable"))
    }
  }

  private func notice(_ message: Text) -> some View {
    HStack(alignment: .top) {
      message.font(.footnote)
      Spacer(minLength: 8)
      Button {
        store.dismissNotices()
      } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
      }
      .accessibilityLabel(Text("Dismiss", tableName: "Timetable"))
    }
    .padding(10)
    .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label {
        Text("No timetable yet", tableName: "Timetable")
      } icon: {
        Image(systemName: "tablecells")
      }
    } description: {
      Text("Add your courses, or import a timetable file.", tableName: "Timetable")
    } actions: {
      Button {
        sheet = .editor(Course(code: ""))
      } label: {
        Text("Add a course", tableName: "Timetable")
      }
      .buttonStyle(.borderedProminent)
      Button {
        showingImporter = true
      } label: {
        Text("Import a file…", tableName: "Timetable")
      }
    }
  }

  private var menu: some View {
    Menu {
      Button {
        sheet = .courses
      } label: {
        Label {
          Text("Edit courses…", tableName: "Timetable")
        } icon: {
          Image(systemName: "pencil")
        }
      }
      Button {
        showingImporter = true
      } label: {
        Label {
          Text("Import a file…", tableName: "Timetable")
        } icon: {
          Image(systemName: "square.and.arrow.down")
        }
      }
      Button {
        showingExporter = true
      } label: {
        Label {
          Text("Export a file…", tableName: "Timetable")
        } icon: {
          Image(systemName: "square.and.arrow.up")
        }
      }
      .disabled(store.timetable.courses.isEmpty)
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel(Text("Timetable options", tableName: "Timetable"))
  }
}
