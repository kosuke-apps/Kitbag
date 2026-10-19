import SwiftUI

/// The styles as small drawings of what the home screen would look like, in the colours of the theme in use: any style
/// goes with any theme, so the drawing follows the theme rather than showing a fixed one.
struct StylePicker: View {
  @Environment(ThemeStore.self) private var themes
  @Environment(\.palette) private var palette

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(StyleID.allCases) { id in
          let style = KitbagStyle.style(id)
          let selected = themes.styleID == id
          Button {
            themes.styleID = id
          } label: {
            VStack(spacing: 8) {
              StyleThumbnail(style: id)
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                      selected ? palette.accent : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 0.75)
                }
              Text(style.name).font(.footnote.weight(selected ? .semibold : .regular)).foregroundStyle(.primary)
            }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .padding(.horizontal, 16)
    }
  }
}

/// A drawing of the home screen in one style: the date, then the parts of the day.
private struct StyleThumbnail: View {
  @Environment(\.palette) private var palette
  let style: StyleID

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(
        colors: [palette.backgroundTop, palette.backgroundBottom], startPoint: .top, endPoint: .bottom)
      VStack(alignment: .leading, spacing: spacing) {
        date
        switch style {
        case .classic: classic
        case .glass: glass
        case .bento: bento
        case .editorial: editorial
        case .compact: compact
        }
      }
      .padding(9)
    }
  }

  private var spacing: CGFloat { style == .compact ? 4 : 6 }

  /// The date: a small line over a larger one.
  private var date: some View {
    VStack(alignment: .leading, spacing: 2) {
      Capsule().fill(palette.heading).frame(width: 18, height: 3)
      Capsule().fill(Color.primary.opacity(0.85)).frame(
        width: style == .compact ? 30 : 42, height: style == .compact ? 5 : 8)
      if style == .editorial { Rectangle().fill(palette.accent).frame(height: 1.5).padding(.top, 2) }
    }
  }

  private func card(radius: CGFloat, height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(palette.card)
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(palette.cardStroke, lineWidth: 0.5)
      )
      .frame(height: height)
  }

  private var classic: some View {
    VStack(spacing: 5) {
      card(radius: 5, height: 18)
      card(radius: 5, height: 18)
      card(radius: 5, height: 12)
    }
  }

  private var glass: some View {
    VStack(spacing: 5) {
      glassCard(height: 20)
      glassCard(height: 20)
      glassCard(height: 12)
    }
  }

  private func glassCard(height: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
    return shape.fill(.ultraThinMaterial)
      .overlay(shape.fill(palette.card.opacity(0.4)))
      .overlay(
        shape.strokeBorder(
          LinearGradient(
            colors: [.white.opacity(0.5), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
          lineWidth: 0.8)
      )
      .frame(height: height)
  }

  private var bento: some View {
    VStack(spacing: 4) {
      HStack(spacing: 4) {
        card(radius: 6, height: 26)
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.accent.opacity(0.75)).frame(height: 26)
      }
      card(radius: 6, height: 14)
      HStack(spacing: 4) {
        card(radius: 6, height: 11)
        card(radius: 6, height: 11)
      }
    }
  }

  private var editorial: some View {
    VStack(alignment: .leading, spacing: 5) {
      line(width: 22, tall: true)
      rule
      line(width: 50)
      line(width: 36)
      rule
      line(width: 44)
    }
  }

  private var rule: some View { Rectangle().fill(palette.cardStroke).frame(height: 1) }

  private func line(width: CGFloat, tall: Bool = false) -> some View {
    Capsule().fill(Color.primary.opacity(tall ? 0.8 : 0.35)).frame(width: width, height: tall ? 6 : 3)
  }

  private var compact: some View {
    VStack(spacing: 3) {
      card(radius: 3, height: 9)
      card(radius: 3, height: 9)
      card(radius: 3, height: 13)
      card(radius: 3, height: 13)
      HStack(spacing: 3) {
        ForEach(0..<4, id: \.self) { _ in
          RoundedRectangle(cornerRadius: 3, style: .continuous).fill(palette.accent.opacity(0.6)).frame(height: 8)
        }
      }
    }
  }
}
