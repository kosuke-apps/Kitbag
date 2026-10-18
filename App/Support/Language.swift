import KitbagCore
import Observation
import SwiftUI

/// The language Kitbag speaks right now, and what comes from it: the translation bundle and the locale for formatting.
///
/// The choice is Kitbag-wide (Settings > Language) and is passed on to the guests, which have their own language setting.
/// Reading a property inside a SwiftUI body registers the body for redraw, so a change shows at once, without restarting.
/// The language is kept apart from the region: the locale pairs the chosen language with the phone's region, so 12 or 24
/// hours and units still follow the phone.
final class LanguageStore: Observable, @unchecked Sendable {
  /// What the app uses.
  static let shared = LanguageStore()

  private struct Resolved {
    let code: String
    let locale: Locale
    let bundle: Bundle
  }

  private static let key = "kitbag.language"

  private let registrar = ObservationRegistrar()
  private let lock = NSLock()
  private let defaults: UserDefaults
  private var resolved: Resolved
  private var storedChoice: LanguageChoice

  init(defaults: UserDefaults = .standard, preferred: [String] = Locale.preferredLanguages) {
    self.defaults = defaults
    let choice = defaults.string(forKey: Self.key).flatMap(LanguageChoice.init(rawValue:)) ?? .system
    storedChoice = choice
    resolved = Self.resolve(choice, preferred: preferred)
  }

  var choice: LanguageChoice { read { _ in storedChoice } }
  /// "en" or "ja".
  var code: String { read { $0.code } }
  /// The chosen language with the phone's region (`ja_US`), for dates, numbers and the lookup of SwiftUI text.
  var locale: Locale { read { $0.locale } }
  /// The folder of translations for the chosen language (`ja.lproj`), or the main bundle without one.
  var bundle: Bundle { read { $0.bundle } }

  /// Switches the language and remembers the choice; views that read it redraw.
  func apply(_ choice: LanguageChoice, preferred: [String] = Locale.preferredLanguages) {
    let next = Self.resolve(choice, preferred: preferred)
    registrar.withMutation(of: self, keyPath: \.code) {
      lock.lock()
      resolved = next
      storedChoice = choice
      lock.unlock()
    }
    defaults.set(choice.rawValue, forKey: Self.key)
  }

  /// Reads the choice again from the settings, after a backup was restored.
  func reload() {
    apply(defaults.string(forKey: Self.key).flatMap(LanguageChoice.init(rawValue:)) ?? .system)
  }

  private func read<Value>(_ get: (Resolved) -> Value) -> Value {
    registrar.access(self, keyPath: \.code)
    lock.lock()
    defer { lock.unlock() }
    return get(resolved)
  }

  private static func resolve(_ choice: LanguageChoice, preferred: [String]) -> Resolved {
    let code = choice.resolved(preferred: preferred)
    let region = Locale.autoupdatingCurrent.region?.identifier
    let locale = Locale(identifier: region.map { "\(code)_\($0)" } ?? code)
    let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap { Bundle(path: $0) } ?? .main
    return Resolved(code: code, locale: locale, bundle: bundle)
  }
}

/// Text built in code, in the language the person chose. `String(localized:)` would follow the phone's language and ignore
/// Settings > Language, so every string Kitbag builds in code goes through here (a SwiftUI `Text` follows the locale of the
/// environment instead).
enum L10n {
  static func string(_ value: String.LocalizationValue, table: String? = nil) -> String {
    let language = LanguageStore.shared
    return String(localized: value, table: table, bundle: language.bundle, locale: language.locale)
  }

  static func string(_ resource: LocalizedStringResource) -> String {
    var chosen = resource
    chosen.locale = LanguageStore.shared.locale
    return String(localized: chosen)
  }
}

extension Text {
  /// A resource as text in the chosen language. SwiftUI's own initialiser would take the phone's.
  init(_ resource: LocalizedStringResource) {
    self.init(verbatim: L10n.string(resource))
  }
}

/// Puts the chosen language into the environment, so that SwiftUI text, dates and numbers use it.
struct LanguageRoot<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content.environment(\.locale, LanguageStore.shared.locale)
  }
}

extension Date {
  /// The date in the language chosen for Kitbag. `formatted(date:time:)` takes the phone's language instead.
  func formattedInLanguage(
    date: Date.FormatStyle.DateStyle = .omitted, time: Date.FormatStyle.TimeStyle = .omitted
  ) -> String {
    formatted(Date.FormatStyle(date: date, time: time).locale(LanguageStore.shared.locale))
  }
}
