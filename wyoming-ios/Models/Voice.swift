import AVFoundation
import Foundation

struct Voice: Identifiable {
  let id: String
  let name: String
  let language: String
  let quality: String

  init(id: String, name: String, language: String, quality: String = "default") {
    self.id = id
    self.name = name
    self.language = language
    self.quality = quality
  }

  init(from avVoice: AVSpeechSynthesisVoice) {
    self.id = avVoice.identifier
    self.name = avVoice.name
    self.language = avVoice.language

    switch avVoice.quality {
    case .default:
      self.quality = "Compact"
    case .enhanced:
      self.quality = "Enhanced"
    case .premium:
      self.quality = "Premium (Siri)"
    @unknown default:
      self.quality = "Unknown"
    }
  }

  func toWyomingDict() -> [String: Any] {
    return [
      "name": id,
      "description": name,
      "languages": [language],
    ]
  }
}
