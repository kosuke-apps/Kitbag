import Testing

@testable import KitbagCore

@Suite("LanguageChoice")
struct LanguageTests {
  @Test func fixedChoicesIgnoreThePhone() {
    #expect(LanguageChoice.english.resolved(preferred: ["ja-JP"]) == "en")
    #expect(LanguageChoice.japanese.resolved(preferred: ["en-US"]) == "ja")
  }

  @Test func systemTakesTheFirstLanguageTheAppSpeaks() {
    #expect(LanguageChoice.system.resolved(preferred: ["ja-JP", "en-US"]) == "ja")
    #expect(LanguageChoice.system.resolved(preferred: ["fr-FR", "ja-JP"]) == "ja")
    #expect(LanguageChoice.system.resolved(preferred: ["en-GB"]) == "en")
    #expect(LanguageChoice.system.resolved(preferred: ["fr-FR", "de-DE"]) == "en")
    #expect(LanguageChoice.system.resolved(preferred: []) == "en")
  }

  @Test func readsTheStoredNames() {
    #expect(LanguageChoice(rawValue: "ja") == .japanese)
    #expect(LanguageChoice(rawValue: "en") == .english)
    #expect(LanguageChoice(rawValue: "system") == .system)
    #expect(LanguageChoice(rawValue: "fr") == nil)
  }
}
