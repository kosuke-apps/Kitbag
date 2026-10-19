import KitbagCore
import SwiftUI

/// Settings > Data usage: how much Kitbag downloads and how to make it download less. Kitbag fetches the weather forecast
/// (the place search with it) and the calendars you subscribe to; this screen shows what that cost this month on Wi-Fi and on
/// mobile data, and chooses how often each is brought up to date on each. Headway counts and chooses for itself.
struct DataUseView: View {
  @Environment(DataUseStore.self) private var store
  @Environment(GuestRuntimes.self) private var guests
  @Environment(\.palette) private var palette
  @State private var confirmingReset = false

  var body: some View {
    @Bindable var store = store
    List {
      connectionSection
      Section {
        Toggle(isOn: $store.settings.saveMobileData) {
          Text("Save mobile data", tableName: "DataUse")
        }
      } footer: {
        Text(
          "Where the rhythm is Automatic, Kitbag waits twice as long between updates on mobile data and four times as long in Low Data Mode. A personal hotspot counts as mobile data.",
          tableName: "DataUse")
      }
      .listRowBackground(palette.card)

      limitSection(store)
      sourceSection(
        title: Text("Weather forecast", tableName: "DataUse"), source: .weather, onWiFi: $store.settings.weatherOnWiFi,
        onMobile: $store.settings.weatherOnMobile)
      sourceSection(
        title: Text("Calendar subscriptions", tableName: "DataUse"), source: .calendars,
        onWiFi: $store.settings.calendarsOnWiFi, onMobile: $store.settings.calendarsOnMobile)
      usageSection
      resetSection
      headwaySection
    }
    .scrollContentBackground(.hidden)
    .themedScreen()
    .navigationTitle(Text("Data usage", tableName: "DataUse"))
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog(
      Text("Reset the data meter?", tableName: "DataUse"), isPresented: $confirmingReset, titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        store.reset()
      } label: {
        Text("Reset", tableName: "DataUse")
      }
    }
  }

  // MARK: Connection

  private var connectionSection: some View {
    Section {
      HStack(spacing: 8) {
        Text("Connection now", tableName: "DataUse")
        Spacer()
        Image(systemName: connectionSymbol)
        Text(connectionName)
      }
      .foregroundStyle(store.connection.isMetered ? Color.orange : Color.secondary)
      .accessibilityElement(children: .combine)
    }
    .listRowBackground(palette.card)
  }

  private var connectionName: String {
    switch store.connection {
    case .wifi: L10n.string("Wi-Fi", table: "DataUse")
    case .mobile: L10n.string("Mobile data", table: "DataUse")
    case .lowData: L10n.string("Low Data Mode", table: "DataUse")
    }
  }

  private var connectionSymbol: String {
    switch store.connection {
    case .wifi: "wifi"
    case .mobile: "antenna.radiowaves.left.and.right"
    case .lowData: "tortoise"
    }
  }

  // MARK: Limit

  private func limitSection(_ store: DataUseStore) -> some View {
    @Bindable var store = store
    let used = store.usage.mobileBytes(inMonthOf: Date(), calendar: .current)
    return Section {
      Picker(selection: $store.settings.monthlyMobileLimit) {
        Text("No limit", tableName: "DataUse").tag(Int?.none)
        ForEach(DataUseSettings.limitChoices, id: \.self) { bytes in
          Text("\(Self.size(bytes)) a month", tableName: "DataUse").tag(Int?.some(bytes))
        }
      } label: {
        Text("Mobile data limit", tableName: "DataUse")
      }
      if let limit = store.settings.monthlyMobileLimit {
        VStack(alignment: .leading, spacing: 6) {
          ProgressView(value: Double(min(used, limit)), total: Double(limit))
            .tint(used >= limit ? Color.red : palette.accent)
          Text("Used this month on mobile data: \(Self.size(used)) of \(Self.size(limit))", tableName: "DataUse")
            .font(.footnote)
            .foregroundStyle(used >= limit ? Color.red : Color.secondary)
        }
      }
    } footer: {
      Text(
        "When this month's mobile data reaches the limit, Kitbag stops updating by itself on mobile data until next month. Updating by hand (pulling a screen down, a refresh button) still works.",
        tableName: "DataUse")
    }
    .listRowBackground(palette.card)
  }

  // MARK: What is fetched

  private func sourceSection(
    title: Text, source: DataSource, onWiFi: Binding<RefreshChoice>, onMobile: Binding<RefreshChoice>
  ) -> some View {
    Section {
      Picker(selection: onWiFi) {
        ForEach(RefreshChoice.allCases.filter { $0 != .notOnMobile }, id: \.self) { choice in
          Text(choice.title).tag(choice)
        }
      } label: {
        Text("On Wi-Fi", tableName: "DataUse")
      }
      Picker(selection: onMobile) {
        ForEach(RefreshChoice.allCases, id: \.self) { choice in
          Text(choice.title).tag(choice)
        }
      } label: {
        Text("On mobile data", tableName: "DataUse")
      }
    } header: {
      title
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(automaticText(for: source))
        if let average = store.usage.averageRequest(source) {
          Text("About \(Self.size(average)) each time, measured.", tableName: "DataUse")
        }
        if source == .weather {
          Text(
            "A search for a place is fetched when you ask, and follows the choice for mobile data.",
            tableName: "DataUse")
        }
      }
    }
    .listRowBackground(palette.card)
  }

  /// What "Automatic" comes to for a source, with the choice to save mobile data taken into account.
  private func automaticText(for source: DataSource) -> String {
    let usual = DataUsePolicy.usualInterval(for: source)
    let wifi = Self.duration(usual)
    guard store.settings.saveMobileData else {
      return L10n.string("Automatic: every \(wifi), on any connection.", table: "DataUse")
    }
    return L10n.string(
      "Automatic: every \(wifi) on Wi-Fi, every \(Self.duration(usual * 2)) on mobile data, every \(Self.duration(usual * 4)) in Low Data Mode.",
      table: "DataUse")
  }

  // MARK: Meter

  private var usageSection: some View {
    let now = Date()
    let calendar = Calendar.current
    let usage = store.usage
    let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
    return Section {
      ForEach(DataSource.allCases, id: \.self) { source in
        row(source.title, usage.tally(source, inMonthOf: now, calendar: calendar))
      }
      row(L10n.string("Total", table: "DataUse"), usage.tally(inMonthOf: now, calendar: calendar), bold: true)
    } header: {
      Text("Used this month", tableName: "DataUse")
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        let previous = usage.tally(inMonthOf: lastMonth, calendar: calendar)
        if previous.requests > 0 {
          Text(
            "Last month: Wi-Fi \(Self.size(previous.wifi)) · mobile \(Self.size(previous.mobile))", tableName: "DataUse"
          )
        }
        let all = usage.tally()
        Text(
          "Since \(usage.since.formattedInLanguage(date: .abbreviated, time: .omitted)): Wi-Fi \(Self.size(all.wifi)) · mobile \(Self.size(all.mobile))",
          tableName: "DataUse")
        Text(
          "Counted by Kitbag from what the network reports, headers included. iOS Settings > Cellular shows a little more and covers every app.",
          tableName: "DataUse")
      }
    }
    .listRowBackground(palette.card)
  }

  private var resetSection: some View {
    Section {
      Button(role: .destructive) {
        confirmingReset = true
      } label: {
        Text("Reset the meter", tableName: "DataUse")
      }
    }
    .listRowBackground(palette.card)
  }

  private func row(_ title: String, _ tally: DataUsage.Tally, bold: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(title).fontWeight(bold ? .semibold : .regular)
        Spacer()
        Text(Self.size(tally.total)).monospacedDigit().fontWeight(bold ? .semibold : .regular)
      }
      (Text("Wi-Fi \(Self.size(tally.wifi)) · mobile \(Self.size(tally.mobile))", tableName: "DataUse")
        + Text(verbatim: " · ") + Text("\(tally.requests) updates", tableName: "DataUse"))
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: Headway

  private var headwaySection: some View {
    let headway = guests.headway.dataUsed()
    return Section {
      LabeledContent {
        Text(Self.size(headway.wifi + headway.mobile)).monospacedDigit()
      } label: {
        Text("Headway", tableName: "DataUse")
      }
      Text(
        "Wi-Fi \(Self.size(headway.wifi)) · mobile \(Self.size(headway.mobile)) since \(headway.since.formattedInLanguage(date: .abbreviated, time: .omitted))",
        tableName: "DataUse"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    } header: {
      Text("Apps inside Kitbag", tableName: "DataUse")
    } footer: {
      Text(
        "Headway keeps its own meter and its own choices: open Headway, then Settings > Live buses > Mobile data. Mantissa uses no network.",
        tableName: "DataUse")
    }
    .listRowBackground(palette.card)
  }

  // MARK: Formatting

  /// "10 KB", "1.2 MB", and "0 KB" for nothing (not "Zero KB").
  static func size(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .decimal
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(bytes))
  }

  /// "15 minutes", "2 hours": a span in the language chosen for Kitbag.
  static func duration(_ seconds: TimeInterval) -> String {
    let style = Duration.UnitsFormatStyle.units(
      allowed: seconds >= 3600 && seconds.truncatingRemainder(dividingBy: 3600) == 0 ? [.hours] : [.minutes],
      width: .wide)
    return Duration.seconds(seconds).formatted(style.locale(LanguageStore.shared.locale))
  }
}

extension RefreshChoice {
  var title: LocalizedStringResource {
    switch self {
    case .automatic: LocalizedStringResource("Automatic", table: "DataUse")
    case .every15Minutes: LocalizedStringResource("Every 15 minutes", table: "DataUse")
    case .every30Minutes: LocalizedStringResource("Every 30 minutes", table: "DataUse")
    case .everyHour: LocalizedStringResource("Every hour", table: "DataUse")
    case .every3Hours: LocalizedStringResource("Every 3 hours", table: "DataUse")
    case .every6Hours: LocalizedStringResource("Every 6 hours", table: "DataUse")
    case .manual: LocalizedStringResource("Only when I refresh", table: "DataUse")
    case .notOnMobile: LocalizedStringResource("Not on mobile data", table: "DataUse")
    }
  }
}

extension DataSource {
  var title: String {
    switch self {
    case .weather: L10n.string("Weather forecast", table: "DataUse")
    case .places: L10n.string("Place search", table: "DataUse")
    case .calendars: L10n.string("Calendar subscriptions", table: "DataUse")
    }
  }
}
