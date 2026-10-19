import KitbagCore
import SwiftUI
import UIKit
import UserNotifications

/// Settings: the theme and appearance, the app icon, and what the home screen shows and in what order.
struct SettingsView: View {
  @Environment(ThemeStore.self) private var themes
  @Environment(GuestRuntimes.self) private var guests
  @Environment(DeadlineStore.self) private var deadlines
  @Environment(DataUseStore.self) private var dataUse
  @Environment(\.palette) private var palette

  /// What this month has cost on mobile data, for the row that opens the data usage screen.
  private var dataUseSummary: String {
    let bytes = dataUse.usage.mobileBytes(inMonthOf: Date(), calendar: .current)
    return L10n.string("Mobile: \(DataUseView.size(bytes))", table: "DataUse")
  }

  var body: some View {
    @Bindable var themes = themes
    NavigationStack {
      List {
        Section {
          Picker(selection: languageBinding) {
            Text("System", tableName: "Settings").tag(LanguageChoice.system)
            Text(verbatim: "English").tag(LanguageChoice.english)
            Text(verbatim: "日本語").tag(LanguageChoice.japanese)
          } label: {
            Text("Language", tableName: "Settings")
          }
        } header: {
          Text("Language", tableName: "Settings")
        } footer: {
          Text("Applies to Kitbag, its tools and the apps inside it.", tableName: "Settings")
        }
        .listRowBackground(palette.card)

        Section {
          ThemePicker()
            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
          VStack(alignment: .leading, spacing: 10) {
            Text("Style", tableName: "Settings")
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 16)
            StylePicker()
            Text(themes.style.summary)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 16)
          }
          .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
          Picker(selection: $themes.appearance) {
            ForEach(AppearanceMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          } label: {
            Text("Appearance", tableName: "Settings")
          }
          .pickerStyle(.segmented)
          .disabled(themes.theme.forcedScheme != nil)
        } header: {
          Text("Theme", tableName: "Settings")
        } footer: {
          if themes.theme.forcedScheme != nil {
            Text("This theme is always dark.", tableName: "Settings")
          }
        }
        .listRowBackground(palette.card)

        Section {
          AppIconPicker()
            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
          Text("App icon", tableName: "Settings")
        }
        .listRowBackground(palette.card)

        Section {
          NavigationLink {
            ToolsLayoutView()
          } label: {
            Label {
              Text("Tools", tableName: "Settings")
            } icon: {
              Image(systemName: "square.grid.2x2")
            }
          }
          NavigationLink {
            TodayLayoutView()
          } label: {
            Label {
              Text("Today", tableName: "Settings")
            } icon: {
              Image(systemName: "sun.max")
            }
          }
        } header: {
          Text("Home screen", tableName: "Settings")
        }
        .listRowBackground(palette.card)

        NotificationSettings()
          .listRowBackground(palette.card)

        Section {
          NavigationLink {
            DataUseView()
          } label: {
            LabeledContent {
              Text(dataUseSummary)
            } label: {
              Label {
                Text("Data usage", tableName: "DataUse")
              } icon: {
                Image(systemName: "chart.bar.doc.horizontal")
              }
            }
          }
        } footer: {
          Text(
            "How much Kitbag downloads, and how often the weather and your calendars are updated on Wi-Fi and on mobile data.",
            tableName: "DataUse")
        }
        .listRowBackground(palette.card)

        DataSettings()
          .listRowBackground(palette.card)

        SignatureSettings()
          .listRowBackground(palette.card)

        Section {
          LabeledContent {
            Text(versionText)
          } label: {
            Text("Version", tableName: "Settings")
          }

          NavigationLink {
            LicensesView()
          } label: {
            Text("Licences", tableName: "Licenses")
          }
        } header: {
          Text("About", tableName: "Settings")
        }
        .listRowBackground(palette.card)
      }
      .scrollContentBackground(.hidden)
      .themedScreen()
      .navigationTitle(Text("Settings", tableName: "Settings"))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  /// The language chosen for the whole of Kitbag. Changing it redraws at once, tells the guests, and plans the reminders
  /// again (their text is in the chosen language) and the widgets.
  private var languageBinding: Binding<LanguageChoice> {
    Binding(
      get: { LanguageStore.shared.choice },
      set: { choice in
        LanguageStore.shared.apply(choice)
        guests.applyLanguage(choice)
        deadlines.syncReminders()
        WidgetBridge.sync(theme: themes.themeID)
      })
  }

  private var versionText: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }
}

/// What the provisioning profile says about this build, down to the minute: a free Apple ID's signature lasts seven days.
private struct SignatureSettings: View {
  var body: some View {
    if let profile = SigningStatus.profile, let expires = profile.expiresAt {
      Section {
        TimelineView(.everyMinute) { context in
          VStack(spacing: 0) {
            row("Signature expires", Text(expires, format: dateStyle))
            Divider().padding(.vertical, 8)
            row(
              "Time left",
              Text(
                expires > context.date
                  ? SigningStatus.left(from: context.date, to: expires)
                  : L10n.string("Expired", table: "Settings"))
            )
            if let created = profile.createdAt {
              Divider().padding(.vertical, 8)
              row("Signed on", Text(created, format: dateStyle))
            }
            if let name = profile.name {
              Divider().padding(.vertical, 8)
              row("Profile", Text(name.replacingOccurrences(of: "iOS Team Provisioning Profile: ", with: "")))
            }
            if let team = profile.teamName {
              Divider().padding(.vertical, 8)
              row("Account", Text(team))
            }
          }
        }
      } header: {
        Text("Signature", tableName: "Settings")
      } footer: {
        Text(
          "A build signed with a free Apple ID stops opening when this runs out, and is renewed by installing it again from the Mac.",
          tableName: "Settings")
      }
    }
  }

  private var dateStyle: Date.FormatStyle {
    .dateTime.year().month(.abbreviated).day().hour().minute()
  }

  private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
    LabeledContent {
      value
    } label: {
      Text(title, tableName: "Settings")
    }
  }
}

/// Whether notifications are allowed, and a button that sends one, so that it is clear on this phone that they arrive.
private struct NotificationSettings: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var status: UNAuthorizationStatus = .notDetermined
  @State private var testSent = false

  private let scheduler = ReminderScheduler()

  var body: some View {
    Section {
      LabeledContent {
        Text(statusText, tableName: "Settings").foregroundStyle(allowed ? Color.secondary : Color.red)
      } label: {
        Text("Notifications", tableName: "Settings")
      }
      switch status {
      case .notDetermined:
        Button {
          Task {
            _ = await scheduler.authorize()
            status = await scheduler.status()
          }
        } label: {
          Text("Allow notifications", tableName: "Settings")
        }
      case .denied:
        Button {
          if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } label: {
          Text("Open iOS Settings", tableName: "Settings")
        }
      default:
        Button {
          Task {
            testSent = await scheduler.sendTest()
            status = await scheduler.status()
          }
        } label: {
          Text("Send a test notification", tableName: "Settings")
        }
      }
      NavigationLink {
        NotificationPreferencesView()
      } label: {
        Label {
          Text("Choose what to be reminded of", tableName: "Settings")
        } icon: {
          Image(systemName: "slider.horizontal.3")
        }
      }
    } header: {
      Text("Notifications", tableName: "Settings")
    } footer: {
      if testSent {
        Text("It arrives in 5 seconds. Lock the screen to see how it looks there.", tableName: "Settings")
      } else if status == .denied {
        Text("Reminders cannot be shown until notifications are allowed in iOS Settings.", tableName: "Settings")
      } else {
        Text(
          "Deadline reminders and the warning before the signature runs out are local notifications: they need no internet and arrive even when Kitbag is closed.",
          tableName: "Settings")
      }
    }
    .task { status = await scheduler.status() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { status = await scheduler.status() } }
    }
  }

  private var allowed: Bool {
    switch status {
    case .authorized, .provisional, .ephemeral: true
    default: false
    }
  }

  private var statusText: LocalizedStringKey {
    switch status {
    case .authorized, .provisional, .ephemeral: "On"
    case .denied: "Off"
    default: "Not set up yet"
    }
  }
}

/// The themes as small previews to choose from.
private struct ThemePicker: View {
  @Environment(ThemeStore.self) private var themes

  /// What each theme would look like with the appearance chosen below, not the one it is in now (a dark theme would
  /// otherwise show every other theme dark).
  private var scheme: ColorScheme { themes.appearance.colorScheme ?? SystemAppearance.scheme }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(ThemeID.allCases) { id in
          let theme = KitbagTheme.theme(id)
          let palette = theme.palette(for: theme.forcedScheme ?? scheme)
          Button {
            themes.themeID = id
          } label: {
            VStack(spacing: 8) {
              ZStack(alignment: .bottomLeading) {
                LinearGradient(
                  colors: [palette.backgroundTop, palette.backgroundBottom], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 5) {
                  Capsule().fill(palette.accent).frame(width: 30, height: 5)
                  RoundedRectangle(cornerRadius: 5).fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.cardStroke, lineWidth: 0.5))
                    .frame(height: 22)
                  RoundedRectangle(cornerRadius: 5).fill(palette.card)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.cardStroke, lineWidth: 0.5))
                    .frame(height: 14)
                }
                .padding(10)
              }
              .frame(width: 92, height: 92)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .strokeBorder(
                    themes.themeID == id ? palette.accent : Color.primary.opacity(0.12),
                    lineWidth: themes.themeID == id ? 2.5 : 0.75)
              }
              Text(theme.name).font(.footnote.weight(themes.themeID == id ? .semibold : .regular)).foregroundStyle(
                .primary)
            }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(themes.themeID == id ? .isSelected : [])
        }
      }
      .padding(.horizontal, 16)
    }
  }
}

/// The icon choices. The first is the app's main icon; the others are alternates that iOS can switch to.
enum AppIconChoice: String, CaseIterable, Identifiable {
  case cap
  case book
  case pencil
  case monogram
  case bag

  var id: String { rawValue }

  /// The name of the alternate icon set, or nil for the main icon.
  var alternateName: String? {
    self == .cap ? nil : "Icon" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
  }

  /// The preview image in the asset catalog.
  var previewName: String { "IconPreview" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

  var title: LocalizedStringResource {
    switch self {
    case .cap: LocalizedStringResource("Mortarboard", table: "Settings")
    case .book: LocalizedStringResource("Open book", table: "Settings")
    case .pencil: LocalizedStringResource("Pencil", table: "Settings")
    case .monogram: LocalizedStringResource("Monogram", table: "Settings")
    case .bag: LocalizedStringResource("Kitbag", table: "Settings")
    }
  }

  static var current: AppIconChoice {
    allCases.first { $0.alternateName == UIApplication.shared.alternateIconName } ?? .cap
  }
}

private struct AppIconPicker: View {
  @State private var selected = AppIconChoice.current
  @State private var failed = false

  private let columns = [GridItem(.adaptive(minimum: 76), spacing: 14, alignment: .top)]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      LazyVGrid(columns: columns, spacing: 14) {
        ForEach(AppIconChoice.allCases) { choice in
          Button {
            select(choice)
          } label: {
            VStack(spacing: 6) {
              AppIconImage(image: UIImage(named: choice.previewName), size: 62)
                .overlay {
                  if selected == choice {
                    RoundedRectangle(cornerRadius: 62 * 0.2237, style: .continuous)
                      .strokeBorder(Color.accentColor, lineWidth: 3)
                      .padding(-3)
                  }
                }
              Text(choice.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selected == choice ? .isSelected : [])
        }
      }
      if failed {
        Text("The icon could not be changed.", tableName: "Settings").font(.footnote).foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func select(_ choice: AppIconChoice) {
    guard UIApplication.shared.supportsAlternateIcons else {
      failed = true
      return
    }
    UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
      Task { @MainActor in
        failed = error != nil
        selected = AppIconChoice.current
      }
    }
  }
}

/// The tools in their order, with a switch for each and handles to drag them.
private struct ToolsLayoutView: View {
  @Environment(LayoutStore.self) private var layout
  @Environment(\.palette) private var palette

  var body: some View {
    List {
      Section {
        ForEach(layout.orderedTools) { tool in
          HStack(spacing: 12) {
            toolIcon(tool)
            Text(tool.title)
            Spacer()
            Toggle(
              isOn: Binding(get: { !layout.isHidden(tool) }, set: { layout.setHidden(tool, !$0) })
            ) {
              Text(tool.title)
            }
            .labelsHidden()
            .disabled(tool == .settings)
          }
        }
        .onMove { layout.moveTools(from: $0, to: $1) }
        .listRowBackground(palette.card)
      } footer: {
        Text(
          "Drag to reorder. Turn a tool off to hide it from the home screen. Settings always stays.",
          tableName: "Settings")
      }
    }
    .environment(\.editMode, .constant(.active))
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("Tools", tableName: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder private func toolIcon(_ tool: ModuleID) -> some View {
    switch tool.icon {
    case .guest(let name): AppIconImage(image: GuestIcon.load(name), size: 30)
    case .symbol(let name, let color): SymbolIcon(name: name, color: color, size: 30)
    }
  }
}

/// The parts of the Today section, in order, with a switch for each.
private struct TodayLayoutView: View {
  @Environment(LayoutStore.self) private var layout
  @Environment(\.palette) private var palette

  var body: some View {
    List {
      Section {
        ForEach(layout.orderedSections) { section in
          HStack(spacing: 12) {
            Image(systemName: section.symbol).frame(width: 26).foregroundStyle(.secondary)
            Text(section.title)
            Spacer()
            Toggle(
              isOn: Binding(get: { !layout.isHidden(section) }, set: { layout.setHidden(section, !$0) })
            ) {
              Text(section.title)
            }
            .labelsHidden()
          }
        }
        .onMove { layout.moveSections(from: $0, to: $1) }
        .listRowBackground(palette.card)
      } footer: {
        Text("Drag to reorder. Turn a part off to hide it from Today.", tableName: "Settings")
      }
    }
    .environment(\.editMode, .constant(.active))
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("Today", tableName: "Settings"))
    .navigationBarTitleDisplayMode(.inline)
  }
}
