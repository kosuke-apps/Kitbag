import KitbagCore
import SwiftUI
import UniformTypeIdentifiers

/// The timetable tool: the term, the week as an A4 page, and the courses as cards, with a menu to export a PDF, to
/// export and import a file, and to add or edit terms.
struct TimetableView: View {
  @Environment(TimetableStore.self) private var store
  @Environment(\.palette) private var palette

  private enum Sheet: Identifiable {
    case course(termID: UUID, courseID: UUID)
    case editCourse(termID: UUID, course: Course, isNew: Bool)
    case term(Timetable, isNew: Bool)

    var id: String {
      switch self {
      case .course(_, let courseID): "course-\(courseID)"
      case .editCourse(_, let course, _): "edit-\(course.id)"
      case .term(let term, _): "term-\(term.id)"
      }
    }
  }

  /// The term being looked at; nil means the one in force today.
  @State private var viewedID: UUID?
  @State private var sheet: Sheet?
  @State private var showingViewer = false
  @State private var showingImporter = false
  @State private var showingFileExporter = false
  @State private var pdf: Data?
  @State private var showingPDFExporter = false
  @State private var importFailed = false

  private var term: Timetable? {
    if let viewedID, let viewed = store.term(id: viewedID) { return viewed }
    return store.terms.isEmpty ? nil : store.timetable
  }

  var body: some View {
    NavigationStack {
      Group {
        if let term {
          content(term)
        } else {
          emptyState
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
      case .course(let termID, let courseID):
        CourseDetailView(courseID: courseID, termID: termID) { course in
          self.sheet = .editCourse(termID: termID, course: course, isNew: false)
        }
      case .editCourse(let termID, let course, let isNew):
        CourseEditor(course: course, termID: termID, isNew: isNew)
      case .term(let term, let isNew):
        TermEditor(term: term, isNew: isNew) { id in
          viewedID = id
        } deleted: {
          viewedID = nil
        }
      }
    }
    .fullScreenCover(isPresented: $showingViewer) {
      if let term {
        TimetablePageViewer(
          term: term,
          onSelect: { slot in
            showingViewer = false
            DispatchQueue.main.async { sheet = .course(termID: term.id, courseID: slot.course.id) }
          }, exportPDF: { exportPDF(term) })
      }
    }
    .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
      do {
        viewedID = try store.importFile(at: try result.get())
      } catch {
        importFailed = true
      }
    }
    .fileExporter(
      isPresented: $showingFileExporter, document: TimetableDocument(timetable: term ?? Timetable()),
      contentType: .json,
      defaultFilename: term?.termName ?? "Timetable"
    ) { _ in }
    .fileExporter(
      isPresented: $showingPDFExporter, document: PDFFile(data: pdf ?? Data()), contentType: .pdf,
      defaultFilename: term?.termName ?? "Timetable"
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

  // MARK: Content

  private func content(_ term: Timetable) -> some View {
    ScrollView {
      VStack(spacing: 18) {
        notices
        TermHeader(
          term: term, select: { viewedID = $0 },
          newTerm: { sheet = .term(newTerm(), isNew: true) },
          editTerm: { sheet = .term(term, isNew: false) })
        // A term entered only for its grades has no classes to draw.
        if !term.isGradesOnly { pageCard(term) }
        coursesSection(term)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
  }

  /// The week as an A4 page. Tap a class for its course; the button at the corner opens it large, to zoom.
  private func pageCard(_ term: Timetable) -> some View {
    GeometryReader { proxy in
      TimetablePage(
        timetable: term, heading: term.pageHeading, style: .screen,
        size: CGSize(width: proxy.size.width, height: proxy.size.width * 1.4142)
      ) { slot in
        sheet = .course(termID: term.id, courseID: slot.course.id)
      }
    }
    .aspectRatio(1 / 1.4142, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .shadow(color: palette.shadow.opacity(2), radius: 14, y: 6)
    .overlay(alignment: .bottomTrailing) {
      Button {
        showingViewer = true
      } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .font(.footnote.weight(.semibold))
          .padding(8)
          .background(.regularMaterial, in: Circle())
      }
      .padding(10)
      .accessibilityLabel(Text("Open the page large", tableName: "Timetable"))
    }
  }

  private func coursesSection(_ term: Timetable) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SectionHeading(Text("Courses", tableName: "Timetable"))
        Spacer()
        Button {
          sheet = .editCourse(termID: term.id, course: Course(code: "", color: nextColor(in: term)), isNew: true)
        } label: {
          Label {
            Text("Add a course", tableName: "Timetable")
          } icon: {
            Image(systemName: "plus")
          }
          .font(.subheadline.weight(.semibold))
        }
      }
      if term.courses.isEmpty {
        Text("No courses in this term yet.", tableName: "Timetable")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      ForEach(term.courses) { course in
        CourseCard(course: course) { sheet = .course(termID: term.id, courseID: course.id) }
      }
    }
  }

  /// The first colour no course of the term uses yet, so that a new course stands out.
  private func nextColor(in term: Timetable) -> CourseColor {
    let used = Set(term.courses.map(\.color))
    return CourseColor.allCases.first { !used.contains($0) } ?? .lavender
  }

  private func newTerm() -> Timetable {
    let now = Date()
    let year = Calendar.current.component(.year, from: now)
    let season = Season.of(month: Calendar.current.component(.month, from: now))
    let dates = season.defaultDates(year: year)
    return Timetable(year: year, season: season, startDate: dates.start, endDate: dates.end)
  }

  private func exportPDF(_ term: Timetable) {
    pdf = TimetablePDF.data(for: term, heading: term.pageHeading)
    if pdf != nil { showingPDFExporter = true }
  }

  // MARK: Parts

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
      Text("Add a term and its courses, or import a timetable file.", tableName: "Timetable")
    } actions: {
      Button {
        sheet = .term(newTerm(), isNew: true)
      } label: {
        Text("Add a term", tableName: "Timetable")
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
      if let term {
        Button {
          exportPDF(term)
        } label: {
          Label {
            Text("Export PDF…", tableName: "Timetable")
          } icon: {
            Image(systemName: "doc.richtext")
          }
        }
        Button {
          showingFileExporter = true
        } label: {
          Label {
            Text("Export file…", tableName: "Timetable")
          } icon: {
            Image(systemName: "square.and.arrow.up")
          }
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
      Divider()
      Button {
        sheet = .term(newTerm(), isNew: true)
      } label: {
        Label {
          Text("New term…", tableName: "Timetable")
        } icon: {
          Image(systemName: "plus")
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel(Text("Timetable options", tableName: "Timetable"))
  }
}

/// The page, large and zoomable: pinch or use the buttons; tap a class to open its course.
struct TimetablePageViewer: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.palette) private var palette

  let term: Timetable
  let onSelect: (Timetable.Slot) -> Void
  let exportPDF: () -> Void

  @State private var zoom: CGFloat = 1
  @State private var zoomAtGestureStart: CGFloat = 1

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        let width = proxy.size.width
        ScrollView([.horizontal, .vertical]) {
          TimetablePage(
            timetable: term, heading: term.pageHeading, style: .screen,
            size: CGSize(width: width * zoom, height: width * zoom * 1.4142), onSelect: onSelect)
        }
        .scrollBounceBehavior(.basedOnSize)
        .gesture(
          MagnifyGesture()
            .onChanged { zoom = min(max(zoomAtGestureStart * $0.magnification, 1), 4) }
            .onEnded { _ in zoomAtGestureStart = zoom })
      }
      .themedScreen()
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Text("Done", tableName: "Timetable")
          }
        }
        ToolbarItemGroup(placement: .bottomBar) {
          Button {
            setZoom(zoom - 0.5)
          } label: {
            Image(systemName: "minus.magnifyingglass")
          }
          .disabled(zoom <= 1)
          Button {
            setZoom(zoom + 0.5)
          } label: {
            Image(systemName: "plus.magnifyingglass")
          }
          .disabled(zoom >= 4)
          Spacer()
          Button(action: exportPDF) {
            Label {
              Text("Export PDF…", tableName: "Timetable")
            } icon: {
              Image(systemName: "doc.richtext")
            }
          }
        }
      }
    }
  }

  private func setZoom(_ value: CGFloat) {
    zoom = min(max(value, 1), 4)
    zoomAtGestureStart = zoom
  }
}
