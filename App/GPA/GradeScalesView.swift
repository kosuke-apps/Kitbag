import KitbagCore
import SwiftUI

/// The grading systems: the built-in ones for reading, and the person's own to write and change.
struct GradeScalesView: View {
  @Environment(GradeScaleStore.self) private var store
  @Environment(\.palette) private var palette
  @State private var editing: GradeScale?

  var body: some View {
    List {
      Section {
        ForEach(store.custom) { scale in
          Button {
            editing = scale
          } label: {
            row(scale)
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button(role: .destructive) {
              store.remove(id: scale.id)
            } label: {
              Label {
                Text("Delete", tableName: "GPA")
              } icon: {
                Image(systemName: "trash")
              }
            }
          }
        }
        Menu {
          Button {
            editing = GradeScale(id: "custom-\(UUID().uuidString)", name: "", grades: [.init(label: "", points: nil)])
          } label: {
            Text("From scratch", tableName: "GPA")
          }
          ForEach(GradeScale.all) { base in
            Button {
              editing = GradeScale(id: "custom-\(UUID().uuidString)", name: base.displayName, grades: base.grades)
            } label: {
              Text("Copy of \(base.displayName)", tableName: "GPA")
            }
          }
        } label: {
          Label {
            Text("Add a grade scale", tableName: "GPA")
          } icon: {
            Image(systemName: "plus")
          }
        }
      } header: {
        Text("Yours", tableName: "GPA")
      } footer: {
        Text(
          "Write the grades your school gives and the points each is worth. A grade with no points is not part of the GPA.",
          tableName: "GPA")
      }
      .listRowBackground(palette.card)

      Section {
        ForEach(GradeScale.all) { scale in row(scale) }
      } header: {
        Text("Built in", tableName: "GPA")
      }
      .listRowBackground(palette.card)
    }
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("Grade scales", tableName: "GPA"))
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { scale in
      GradeScaleEditor(scale: scale)
    }
  }

  private func row(_ scale: GradeScale) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(scale.displayName).font(.body)
      Text(
        scale.grades.map { grade in grade.points.map { "\(grade.label) \(format($0))" } ?? grade.label }.joined(
          separator: "  ")
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(2)
    }
  }

  private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}

/// Writes one grading system: its name and its grades, each with points (or none) and whether it earns the credits.
private struct GradeScaleEditor: View {
  @Environment(GradeScaleStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  struct Row: Identifiable {
    var id = UUID()
    var label: String
    var points: String
    var earnsCredit: Bool
  }

  let scale: GradeScale
  @State private var name: String
  @State private var rows: [Row]

  init(scale: GradeScale) {
    self.scale = scale
    _name = State(initialValue: scale.name ?? "")
    _rows = State(
      initialValue: scale.grades.map {
        Row(
          label: $0.label, points: $0.points.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "",
          earnsCredit: $0.earnsCredit)
      })
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(text: $name) {
            Text("Name", tableName: "GPA")
          }
        }
        Section {
          ForEach($rows) { $row in
            HStack(spacing: 10) {
              TextField(text: $row.label) {
                Text("Grade", tableName: "GPA")
              }
              .textInputAutocapitalization(.characters)
              .frame(maxWidth: .infinity, alignment: .leading)
              TextField(text: $row.points, prompt: Text("–")) {
                Text("Points", tableName: "GPA")
              }
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .frame(width: 70)
              if Double(row.points.replacingOccurrences(of: ",", with: ".")) == nil {
                Toggle(isOn: $row.earnsCredit) {
                  Text("Earns credit", tableName: "GPA")
                }
                .labelsHidden()
                .accessibilityLabel(Text("Earns credit", tableName: "GPA"))
              }
            }
          }
          .onDelete { rows.remove(atOffsets: $0) }
          Button {
            rows.append(Row(label: "", points: "", earnsCredit: false))
          } label: {
            Label {
              Text("Add a grade", tableName: "GPA")
            } icon: {
              Image(systemName: "plus")
            }
          }
        } header: {
          Text("Grades, best first", tableName: "GPA")
        } footer: {
          Text(
            "Points count in the GPA. A grade with no points (pass, satisfactory, incomplete) is left out of it; its switch says whether it earns the credits.",
            tableName: "GPA")
        }
      }
      .navigationTitle(Text("Grade scale", tableName: "GPA"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel", tableName: "GPA")
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            save()
          } label: {
            Text("Save", tableName: "GPA")
          }
          .disabled(!isValid)
        }
      }
    }
  }

  private var cleaned: [GradeScale.Grade] {
    rows.compactMap { row in
      let label = row.label.trimmingCharacters(in: .whitespaces)
      guard !label.isEmpty else { return nil }
      let points = Double(row.points.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
      return GradeScale.Grade(label: label, points: points, earnsCredit: points == nil ? row.earnsCredit : nil)
    }
  }

  private var isValid: Bool {
    let grades = cleaned
    return !name.trimmingCharacters(in: .whitespaces).isEmpty && !grades.isEmpty
      && Set(grades.map(\.label)).count == grades.count
  }

  private func save() {
    store.upsert(GradeScale(id: scale.id, name: name.trimmingCharacters(in: .whitespaces), grades: cleaned))
    dismiss()
  }
}
