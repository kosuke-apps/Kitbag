import Foundation

/// The language the person chose for Kitbag and the tools inside it. English is the base language and Japanese is kept up
/// to date; "system" follows the phone.
public enum LanguageChoice: String, CaseIterable, Codable, Sendable {
  case system
  case english = "en"
  case japanese = "ja"

  /// The languages the app has translations for.
  public static let supported = ["en", "ja"]

  /// "en" or "ja": the two fixed choices as they are, and "system" as the first of the phone's preferred languages that
  /// the app is translated into (English when none is).
  public func resolved(preferred: [String]) -> String {
    switch self {
    case .english: return "en"
    case .japanese: return "ja"
    case .system:
      for language in preferred {
        if let code = Locale(identifier: language).language.languageCode?.identifier, Self.supported.contains(code) {
          return code
        }
      }
      return "en"
    }
  }
}
