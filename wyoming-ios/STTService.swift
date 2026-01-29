import AVFoundation
import Foundation
import Speech

class STTService {
  private let audioFormat: AVAudioFormat

  init() {
    self.audioFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 16000,
      channels: 1,
      interleaved: true
    )!
  }

  func getLanguages() -> [String] {
    return SFSpeechRecognizer.supportedLocales().map { $0.identifier }
  }

  func transcribe(audioData: Data, sampleRate: Int, channels: Int, language: String?) async throws -> String {
    print("Transcribing audio: \(audioData.count) bytes, \(sampleRate) Hz, \(channels) channels")

    let languageToUse: String?
    if let lang = language {
      // language specified in request
      languageToUse = lang
      print("Using specified language: \(lang)")
    } else {
      let savedDefaultLanguage = UserDefaults.standard.string(forKey: "defaultSTTLanguage")
      if let savedLang = savedDefaultLanguage, !savedLang.isEmpty {
        languageToUse = savedLang
        print("Using saved default language: \(savedLang)")
      } else {
        languageToUse = nil
        print("Using system default language")
      }
    }

    // use different API based on iOS version
    // iOS 26.0+: SpeechAnalyzer
    // iOS 26.0-: legacy SFSpeechRecognizer
    if #available(iOS 26.0, *) {
      print("Using SpeechAnalyzer API")
      return try await transcribeWithSpeechAnalyzer(
        audioData: audioData, sampleRate: sampleRate, channels: channels, language: languageToUse)
    } else {
      print("Using legacy SFSpeechRecognizer API")
      return try await transcribeWithSFSpeechRecognizer(
        audioData: audioData, sampleRate: sampleRate, channels: channels, language: languageToUse)
    }
  }

  @available(iOS 26.0, *)
  private func transcribeWithSpeechAnalyzer(audioData: Data, sampleRate: Int, channels: Int, language: String?)
    async throws
    -> String
  {
    let requestedLocale = language != nil ? Locale(identifier: language!) : Locale.current
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
      print("Language not supported: \(requestedLocale.identifier)")
      throw STTError.unsupportedLanguage
    }
    print("Using language: \(locale.identifier)")

    let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

    // download assets if needed
    if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      print("Downloading transcriber assets...")
      try await installationRequest.downloadAndInstall()
      print("Transcriber assets downloaded")
    }

    let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)

    guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
      throw STTError.invalidAudioData
    }
    print("Target format: \(targetFormat.sampleRate) Hz, \(targetFormat.channelCount) channels")

    guard
      let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(sampleRate),
        channels: AVAudioChannelCount(channels),
        interleaved: true
      )
    else {
      throw STTError.invalidAudioData
    }

    // convert audio data to PCM buffer in source format
    guard let sourcePCMBuffer = createPCMBuffer(from: audioData, format: sourceFormat) else {
      throw STTError.invalidAudioData
    }
    print("Created source PCM buffer: \(sourcePCMBuffer.frameLength) frames")

    // resample if needed
    let finalBuffer: AVAudioPCMBuffer
    if sourceFormat.sampleRate != targetFormat.sampleRate || sourceFormat.channelCount != targetFormat.channelCount {
      print("Resampling from \(sourceFormat.sampleRate) Hz to \(targetFormat.sampleRate) Hz")
      guard let resampledBuffer = resampleAudio(buffer: sourcePCMBuffer, to: targetFormat) else {
        throw STTError.invalidAudioData
      }
      finalBuffer = resampledBuffer
      print("Resampled buffer: \(finalBuffer.frameLength) frames")
    } else {
      finalBuffer = sourcePCMBuffer
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])

    // input audio in a task
    Task {
      let input = AnalyzerInput(buffer: finalBuffer)
      inputBuilder.yield(input)
      inputBuilder.finish()
      print("Audio input finished")
    }

    // collect transcription results in a task
    var transcription = ""
    let resultsTask = Task {
      do {
        for try await result in transcriber.results {
          transcription = String(result.text.characters)
          print("Received transcription: '\(transcription)'")
        }
      } catch {
        print("Transcription error: \(error)")
        throw error
      }
    }

    let lastSampleTime = try await analyzer.analyzeSequence(inputSequence)
    if let lastSampleTime = lastSampleTime {
      try await analyzer.finalizeAndFinish(through: lastSampleTime)
    } else {
      await analyzer.cancelAndFinishNow()
    }

    // wait for results task to complete
    try await resultsTask.value

    print("Transcription complete: '\(transcription)'")
    return transcription
  }

  private func transcribeWithSFSpeechRecognizer(audioData: Data, sampleRate: Int, channels: Int, language: String?)
    async throws
    -> String
  {
    let locale: Locale
    if let lang = language {
      locale = Locale(identifier: lang)
    } else {
      locale = Locale.current
    }

    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      print("Speech recognizer not available for locale: \(locale.identifier)")
      throw STTError.recognizerUnavailable
    }

    guard recognizer.isAvailable else {
      print("Speech recognizer not available")
      throw STTError.recognizerUnavailable
    }
    print("Using language: \(locale.identifier)")

    guard
      let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(sampleRate),
        channels: AVAudioChannelCount(channels),
        interleaved: true
      )
    else {
      throw STTError.invalidAudioData
    }

    guard let audioBuffer = createPCMBuffer(from: audioData, format: sourceFormat) else {
      throw STTError.invalidAudioData
    }
    print("Created audio buffer: \(audioBuffer.frameLength) frames")

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = false
    request.append(audioBuffer)
    request.endAudio()

    return try await withCheckedThrowingContinuation { continuation in
      recognizer.recognitionTask(with: request) { result, error in
        if let error = error {
          print("Recognition error: \(error)")
          continuation.resume(throwing: STTError.transcriptionFailed)
          return
        }

        if let result = result, result.isFinal {
          let transcription = result.bestTranscription.formattedString
          print("Transcription complete: '\(transcription)'")
          continuation.resume(returning: transcription)
        }
      }
    }
  }

  // MARK: - Audio Conversion

  private func resampleAudio(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
      print("Failed to create audio converter")
      return nil
    }

    let inputFrameCount = buffer.frameLength
    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let outputFrameCapacity = AVAudioFrameCount(Double(inputFrameCount) * ratio)

    guard
      let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: targetFormat,
        frameCapacity: outputFrameCapacity
      )
    else {
      print("Failed to create output buffer")
      return nil
    }

    var error: NSError?
    let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
      outStatus.pointee = .haveData
      return buffer
    }

    let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
    if status == .error {
      print("Conversion error: \(error?.localizedDescription ?? "unknown")")
      return nil
    }

    return outputBuffer
  }

  private func createPCMBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frameCount = data.count / 2

    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(frameCount)
      )
    else {
      return nil
    }

    buffer.frameLength = AVAudioFrameCount(frameCount)

    guard let channelData = buffer.int16ChannelData else {
      return nil
    }

    data.withUnsafeBytes { rawBufferPointer in
      guard let baseAddress = rawBufferPointer.baseAddress else { return }
      let int16Pointer = baseAddress.assumingMemoryBound(to: Int16.self)
      channelData[0].update(from: int16Pointer, count: frameCount)
    }

    return buffer
  }
}

enum STTError: Error {
  case invalidAudioData
  case transcriptionFailed
  case unsupportedLanguage
  case recognizerUnavailable
}
