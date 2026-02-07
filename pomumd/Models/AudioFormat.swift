import AVFoundation
import Foundation

struct AudioFormat: Codable, Equatable {
  let rate: UInt32
  let width: UInt32
  let channels: UInt32

  /// Common audio format used by Wyoming protocol clients
  static let commonFormat = AudioFormat(rate: 16000, width: 2, channels: 1)

  /// Creates an AVAudioFormat for PCM Int16 audio
  func toAVAudioFormat() -> AVAudioFormat? {
    return AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(rate),
      channels: AVAudioChannelCount(channels),
      interleaved: true
    )
  }

  /// Validates that the audio format has valid parameters
  var isValid: Bool {
    return rate > 0 && channels > 0 && (width == 2 || width == 4)
  }

  /// Human-readable description of the audio format
  var description: String {
    return "\(rate) Hz, \(width) bytes/sample, \(channels) channel(s)"
  }
}
