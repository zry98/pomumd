import Foundation

struct AudioFormat {
  let rate: Int  // sample rate in Hz (e.g., 16000)
  let width: Int  // bytes per sample (e.g., 2 for 16-bit)
  let channels: Int  // number of channels

  static let commonFormat = AudioFormat(rate: 16000, width: 2, channels: 1)

  func toWyomingDict() -> [String: Any] {
    return [
      "rate": rate,
      "width": width,
      "channels": channels,
    ]
  }
}
