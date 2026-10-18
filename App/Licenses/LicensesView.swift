import SwiftUI

/// One piece of other people's work that Kitbag ships or draws on, and where its licence text is.
private struct Credit: Identifiable {
  let id: String
  let name: String
  /// What it is used for.
  let purpose: LocalizedStringResource
  let licence: String
  let copyright: String
  /// The licence text: a file in the app bundle (`name.ext`), or nil when only a link is given.
  let file: (name: String, ext: String?)?
  let link: URL?
}

/// Settings > About > Licences: the licence of everything Kitbag contains, and the data credits. Kitbag and the apps inside
/// it are MIT; the libraries and data under them carry their own terms, which these texts have to come with the app.
struct LicensesView: View {
  @Environment(\.palette) private var palette

  private static let credits: [Credit] = [
    Credit(
      id: "kitbag", name: "Kitbag", purpose: LocalizedStringResource("This app", table: "Licenses"), licence: "MIT",
      copyright: "Copyright (c) 2026 Kosuke Satake", file: ("LICENSE", nil), link: nil),
    Credit(
      id: "headway", name: "Headway",
      purpose: LocalizedStringResource("Live Madison bus map, inside Kitbag", table: "Licenses"),
      licence: "MIT", copyright: "Copyright (c) 2026 Kosuke Satake", file: ("LICENSE", nil), link: nil),
    Credit(
      id: "mantissa", name: "Mantissa",
      purpose: LocalizedStringResource("Exact calculator, inside Kitbag", table: "Licenses"), licence: "MIT",
      copyright: "Copyright (c) 2026 Kosuke Satake", file: ("LICENSE", nil), link: nil),
    Credit(
      id: "maplibre", name: "MapLibre Native",
      purpose: LocalizedStringResource("Draws the map in Headway", table: "Licenses"),
      licence: "BSD 2-Clause",
      copyright: "Copyright (c) 2021 MapLibre contributors, 2018-2021 MapTiler.com, 2014-2020 Mapbox",
      file: ("maplibre-native", "txt"), link: nil),
    Credit(
      id: "protobuf", name: "SwiftProtobuf",
      purpose: LocalizedStringResource("Reads Headway's live feeds", table: "Licenses"),
      licence: "Apache License 2.0", copyright: "Copyright Apple Inc. and the Swift Project authors",
      file: ("apache-2.0", "txt"), link: nil),
    Credit(
      id: "gtfs-realtime", name: "GTFS Realtime",
      purpose: LocalizedStringResource("The definition of Headway's live feeds", table: "Licenses"),
      licence: "Apache License 2.0", copyright: "Copyright 2015 The GTFS Specifications Authors",
      file: ("apache-2.0", "txt"), link: nil),
    Credit(
      id: "zipfoundation", name: "ZIPFoundation",
      purpose: LocalizedStringResource("Opens Headway's timetable archive", table: "Licenses"), licence: "MIT",
      copyright: "Copyright (c) 2017-2025 Thomas Zoechling", file: ("zipfoundation", "txt"), link: nil),
    Credit(
      id: "noto", name: "Noto Sans", purpose: LocalizedStringResource("Map labels in Headway", table: "Licenses"),
      licence: "SIL Open Font License 1.1", copyright: "Copyright 2022 The Noto Project Authors",
      file: ("noto-sans", "txt"), link: nil),
    Credit(
      id: "protomaps", name: "Protomaps basemaps",
      purpose: LocalizedStringResource("Colours and layers of Headway's map", table: "Licenses"),
      licence: "BSD 3-Clause, with CC0 and MIT parts",
      copyright: "Copyright 2019-2023 Protomaps LLC, Kelso Cartography",
      file: ("protomaps-basemaps", "txt"), link: nil),
  ]

  var body: some View {
    List {
      Section {
        Link(destination: URL(string: "https://open-meteo.com/")!) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "Open-Meteo").foregroundStyle(.primary)
            Text(
              "Weather data by Open-Meteo.com, under CC BY 4.0. Free for non-commercial use.", tableName: "Licenses"
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
        }
        Link(destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!) {
          Text("Creative Commons Attribution 4.0", tableName: "Licenses")
        }
        Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "OpenStreetMap").foregroundStyle(.primary)
            Text(
              "Map data © OpenStreetMap contributors, Open Database Licence 1.0 (in Headway).", tableName: "Licenses"
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "City of Madison, Metro Transit")
          Text(
            "Bus timetables and live positions in Headway: data provided under license granted by City of Madison, WI, Metro Transit. Headway and Kitbag are independent of the City and Metro Transit.",
            tableName: "Licenses"
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
      } header: {
        Text("Data", tableName: "Licenses")
      }
      .listRowBackground(palette.card)

      Section {
        ForEach(Self.credits) { credit in
          NavigationLink {
            LicenseText(
              title: credit.name, licence: credit.licence, copyright: credit.copyright, file: credit.file)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: credit.name)
              Text("\(Text(credit.purpose)) · \(credit.licence)").font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text("Software", tableName: "Licenses")
      } footer: {
        Text(
          "Kitbag and the apps inside it are free software under the MIT licence. They were built with AI assistance. Everything stays on your phone; see PRIVACY.md in the source.",
          tableName: "Licenses")
      }
      .listRowBackground(palette.card)
    }
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("Licences", tableName: "Licenses"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// The text of one licence, in a monospaced face, with its copyright line.
private struct LicenseText: View {
  let title: String
  let licence: String
  let copyright: String
  let file: (name: String, ext: String?)?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(verbatim: copyright).font(.subheadline.weight(.semibold))
        Text(verbatim: licence).font(.footnote).foregroundStyle(.secondary)
        if let text {
          Text(verbatim: text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        } else {
          Text("The text of this licence is in the source repository.", tableName: "Licenses")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
    }
    .themedScreen()
    .navigationTitle(Text(verbatim: title))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var text: String? {
    guard let file, let url = Bundle.main.url(forResource: file.name, withExtension: file.ext) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }
}
