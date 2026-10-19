import KitbagCore
import SwiftUI

/// Today's date, the face of the home screen. It stays at the top while everything else scrolls under it (`HomeView`), and
/// opens the calendar on today. How it is drawn depends on the style.
struct TodayHeader: View {
  @Environment(\.palette) private var palette
  @Environment(\.titleDesign) private var design
  @Environment(\.kitbagStyle) private var style

  let open: (ModuleRoute) -> Void

  var body: some View {
    TimelineView(.everyMinute) { context in
      Button {
        open(ModuleRoute(.calendar, day: LocalDate(context.date, calendar: .current)))
      } label: {
        switch style.header {
        case .large: large(now: context.date)
        case .editorial: editorial(now: context.date)
        case .compact: compact(now: context.date)
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint(Text("Opens the calendar", tableName: "Today"))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func large(now: Date) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(now, format: .dateTime.weekday(.wide))
        .font(.subheadline.weight(.semibold))
        .textCase(.uppercase)
        .tracking(1.6)
        .foregroundStyle(palette.heading)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(now, format: .dateTime.month(.wide).day())
          .font(.system(size: 40, weight: .semibold, design: design))
          .minimumScaleFactor(0.7)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.heading)
      }
    }
  }

  /// Like the head of a page: a small line of capitals, a large serif date and a thin rule.
  private func editorial(now: Date) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(now, format: .dateTime.weekday(.wide))
          .font(.system(.footnote, design: .serif).weight(.semibold))
          .textCase(.uppercase)
          .tracking(2.4)
          .foregroundStyle(palette.accent)
        Spacer()
        Text(now, format: .dateTime.year())
          .font(.system(.footnote, design: .serif))
          .foregroundStyle(palette.heading)
      }
      Text(now, format: .dateTime.month(.wide).day())
        .font(.system(size: 44, weight: .regular, design: .serif))
        .minimumScaleFactor(0.7)
        .lineLimit(1)
      Rectangle().fill(palette.accent).frame(height: 2)
    }
  }

  /// One line: enough to know the day.
  private func compact(now: Date) -> some View {
    HStack(spacing: 6) {
      Text(now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
        .font(.system(size: 22, weight: .semibold, design: design))
        .lineLimit(1)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(palette.heading)
      Spacer()
    }
  }
}
