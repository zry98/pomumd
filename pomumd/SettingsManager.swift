import Combine
import Foundation

@MainActor
class SettingsManager: ObservableObject {
  static let userDefaultsKeyDefaultTTSVoice = "defaultTTSVoice"
  static let userDefaultsKeyDefaultSTTLanguage = "defaultSTTLanguage"

  @Published var defaultTTSVoice: String {
    didSet {
      UserDefaults.standard.set(defaultTTSVoice, forKey: Self.userDefaultsKeyDefaultTTSVoice)
    }
  }

  @Published var defaultSTTLanguage: String {
    didSet {
      UserDefaults.standard.set(defaultSTTLanguage, forKey: Self.userDefaultsKeyDefaultSTTLanguage)
    }
  }

  init() {
    self.defaultTTSVoice = UserDefaults.standard.string(forKey: Self.userDefaultsKeyDefaultTTSVoice) ?? ""
    self.defaultSTTLanguage = UserDefaults.standard.string(forKey: Self.userDefaultsKeyDefaultSTTLanguage) ?? ""
  }

  func validateTTSVoice(_ voiceID: String) throws {
    guard !voiceID.isEmpty else {
      // empty will fallback to system default
      return
    }

    let availableVoices = TTSService.getAvailableVoices()

    guard availableVoices.contains(where: { $0.id == voiceID }) else {
      throw SettingsError.invalidVoice("Voice '\(voiceID)' not found")
    }
  }

  func validateSTTLanguage(_ langID: String) throws {
    guard !langID.isEmpty else {
      // empty will fallback to system default
      return
    }

    let availableLanguages = STTService.getLanguages()

    guard availableLanguages.contains(langID) else {
      throw SettingsError.invalidLanguage("Language '\(langID)' not found")
    }
  }

  struct Settings: Codable {
    let defaultTTSVoice: String
    let defaultSTTLanguage: String
  }

  func toSettings() -> Settings {
    return Settings(
      defaultTTSVoice: defaultTTSVoice,
      defaultSTTLanguage: defaultSTTLanguage
    )
  }

  func updateFromSettings(_ settings: Settings) throws {
    try validateTTSVoice(settings.defaultTTSVoice)
    try validateSTTLanguage(settings.defaultSTTLanguage)

    self.defaultTTSVoice = settings.defaultTTSVoice
    self.defaultSTTLanguage = settings.defaultSTTLanguage
  }

  func updatePartial(
    defaultTTSVoice: String? = nil,
    defaultSTTLanguage: String? = nil
  ) throws {
    let newTTSVoice = defaultTTSVoice ?? self.defaultTTSVoice
    let newSTTLang = defaultSTTLanguage ?? self.defaultSTTLanguage

    try validateTTSVoice(newTTSVoice)
    try validateSTTLanguage(newSTTLang)

    if let voice = defaultTTSVoice { self.defaultTTSVoice = voice }
    if let lang = defaultSTTLanguage { self.defaultSTTLanguage = lang }
  }
}

enum SettingsError: Error, LocalizedError {
  case invalidVoice(String)
  case invalidLanguage(String)

  var errorDescription: String? {
    switch self {
    case .invalidVoice(let msg),
      .invalidLanguage(let msg):
      return msg
    }
  }
}
