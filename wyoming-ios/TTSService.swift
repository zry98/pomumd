import AVFoundation
import Foundation

class TTSService {
  private let synthesizer: AVSpeechSynthesizer
  private var buffer: AVAudioPCMBuffer?
  private var result: Data?

  init() {
    self.synthesizer = AVSpeechSynthesizer()
    self.synthesizer.usesApplicationAudioSession = true
  }

  func getAvailableVoices() -> [Voice] {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    return voices.map { Voice(from: $0) }
  }

  func findVoice(byIdentifier identifier: String?) -> AVSpeechSynthesisVoice? {
    guard let id = identifier else {
      return nil
    }
    return AVSpeechSynthesisVoice(identifier: id)
  }

  func synthesize(text: String, voiceIdentifier: String?) async throws -> (data: Data, format: AudioFormat) {
    let utterance = AVSpeechUtterance(string: text)

    let voiceToUse: String?
    if let voiceId = voiceIdentifier {
      // voice specified in request
      voiceToUse = voiceId
    } else {
      let savedDefaultVoice = UserDefaults.standard.string(forKey: "defaultTTSVoice")
      if let savedVoice = savedDefaultVoice, !savedVoice.isEmpty {
        voiceToUse = savedVoice
        print("Using saved default voice: \(savedVoice)")
      } else {
        voiceToUse = nil
        print("Using system default voice")
      }
    }

    if let voiceId = voiceToUse {
      if let voice = findVoice(byIdentifier: voiceId) {
        utterance.voice = voice
        print("Voice identifier: \(voice.identifier)")
      } else {
        print("Voice '\(voiceId)' not found, using system default")
      }
    }

    if let setVoice = utterance.voice {
      print("Utterance voice confirmed: \(setVoice.identifier)")
    } else {
      print("Utterance voice is nil")
    }

    var output = Data()
    var bufferCount = 0
    var audioFormat: AudioFormat?

    return try await withCheckedThrowingContinuation { continuation in
      var hasResumed = false

      synthesizer.write(
        utterance,
        toBufferCallback: { [weak self] buffer in
          guard let self = self else { return }
          guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

          bufferCount += 1
          print("Received buffer #\(bufferCount): \(pcmBuffer.frameLength) frames")

          if audioFormat == nil && pcmBuffer.frameLength > 0 {
            let format = pcmBuffer.format
            let rate = Int(format.sampleRate)
            let channels = Int(format.channelCount)

            let width: Int
            if format.commonFormat == .pcmFormatFloat32 {
              width = 2  // Float32 converted to Int16
            } else {
              width = Int(format.streamDescription.pointee.mBytesPerFrame) / channels
            }

            audioFormat = AudioFormat(rate: rate, width: width, channels: channels)
            print("Audio format: \(rate) Hz, \(width) bytes/sample, \(channels) channel(s)")
          }

          if let data = self.convertBufferToData(pcmBuffer) {
            output.append(data)
          }

          // check if this is the last buffer (frameLength == 0 indicates end)
          if pcmBuffer.frameLength == 0 && !hasResumed {
            hasResumed = true
            print("Synthesis complete: \(output.count) bytes from \(bufferCount) buffers")
            let format = audioFormat ?? AudioFormat.commonFormat
            continuation.resume(returning: (data: output, format: format))
          }
        })

      // if no empty buffer is received, wait a bit and return what we have
      DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
        if !hasResumed {
          hasResumed = true
          print("Synthesis timeout: returning \(output.count) bytes from \(bufferCount) buffers")
          let format = audioFormat ?? AudioFormat.commonFormat
          continuation.resume(returning: (data: output, format: format))
        }
      }
    }
  }

  private func convertBufferToData(_ buf: AVAudioPCMBuffer) -> Data? {
    let channels = Int(buf.format.channelCount)
    let frames = Int(buf.frameLength)

    guard frames > 0 else {
      print("Buffer has no frames")
      return nil
    }

    var output = Data()

    if let d = buf.int16ChannelData {
      for f in 0..<frames {
        for c in 0..<channels {
          var v = d[c][f].littleEndian
          output.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
        }
      }
      return output
    } else if let d = buf.int32ChannelData {
      for f in 0..<frames {
        for c in 0..<channels {
          var v = d[c][f].littleEndian
          output.append(Data(bytes: &v, count: MemoryLayout<Int32>.size))
        }
      }
      return output
    } else if let d = buf.floatChannelData {
      for f in 0..<frames {
        for c in 0..<channels {
          let sample = d[c][f]
          let clampedSample = max(-1.0, min(1.0, sample))
          let int16Sample = Int16(clampedSample * Float(Int16.max))
          var v = int16Sample.littleEndian
          output.append(Data(bytes: &v, count: MemoryLayout<Int16>.size))
        }
      }
      return output
    } else {
      print("Buffer has no valid channel data")
      return nil
    }
  }
}
