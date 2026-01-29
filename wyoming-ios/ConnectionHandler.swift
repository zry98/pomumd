import Foundation
import Network

class ConnectionHandler {
  private let connection: NWConnection
  private let serviceType: ServiceType
  private let ttsService: TTSService?
  private let sttService: STTService?
  private let wyomingProtocol: WyomingProtocol
  private var receiveBuffer = Data()
  private var isTranscribing = false

  private var audioBuffer = Data()
  private var transcribeLanguage: String?
  private var audioSampleRate: Int = 16000
  private var audioChannels: Int = 1
  private var audioWidth: Int = 2

  var onClose: (() -> Void)?

  init(connection: NWConnection, serviceType: ServiceType, ttsService: TTSService?, sttService: STTService?) {
    self.connection = connection
    self.serviceType = serviceType
    self.ttsService = ttsService
    self.sttService = sttService
    self.wyomingProtocol = WyomingProtocol()
  }

  func start() {
    connection.start(queue: .global(qos: .userInitiated))

    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .ready:
        self?.receiveMessage()
      case .failed, .cancelled:
        self?.onClose?()
      default:
        break
      }
    }
  }

  func close() {
    connection.cancel()
  }

  private func sendInfo() {
    var ttsVoices: [Voice] = []
    var sttLanguages: [String] = []

    switch serviceType {
    case .tts:
      if let ttsService = ttsService {
        ttsVoices = ttsService.getAvailableVoices()
      }
    case .stt:
      if let sttService = sttService {
        sttLanguages = sttService.getLanguages()
      }
    }

    let message = wyomingProtocol.createInfoEvent(ttsVoices: ttsVoices, sttLanguages: sttLanguages)
    let data = wyomingProtocol.serializeMessage(message)
    connection.send(content: data, completion: .contentProcessed { _ in })
  }

  private func receiveMessage() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
      guard let self = self else { return }

      print("Rx: \(data?.count ?? 0), isComplete: \(isComplete), error: \(String(describing: error))")

      if let data = data, !data.isEmpty {
        self.receiveBuffer.append(data)
        print("len(buffer)=\(self.receiveBuffer.count)")
        self.processBuffer()
      }

      if isComplete {
        print("Connection closed by client")
        self.onClose?()
        return
      }

      // continue receiving
      self.receiveMessage()
    }
  }

  private func processBuffer() {
    while let message = self.wyomingProtocol.parseMessage(from: self.receiveBuffer) {
      print("Parsed message type: \(message.type)")
      let messageSize = message.messageSize
      if messageSize > 0 && messageSize <= self.receiveBuffer.count {
        self.receiveBuffer = Data(self.receiveBuffer.dropFirst(messageSize))
      }

      self.handleMessage(message)
    }
  }

  private func calculateMessageSize(_ message: WyomingMessage) -> Int {
    var dataLength = 0
    if let data = message.data,
      let dataBytes = try? JSONSerialization.data(withJSONObject: data, options: [])
    {
      dataLength = dataBytes.count
    }

    let payloadLength = message.payload?.count ?? 0

    var headerDict: [String: Any] = [
      "type": message.type,
      "version": "1.0.0",
    ]

    if dataLength > 0 {
      headerDict["data_length"] = dataLength
    }

    if payloadLength > 0 {
      headerDict["payload_length"] = payloadLength
    }

    guard let headerData = try? JSONSerialization.data(withJSONObject: headerDict),
      let headerString = String(data: headerData, encoding: .utf8)
    else {
      return 0
    }

    var size = headerString.utf8.count + 1  // +1 for newline

    if dataLength > 0 {
      size += dataLength
    }

    if payloadLength > 0 {
      size += payloadLength
    }

    return size
  }

  private func handleMessage(_ message: WyomingMessage) {
    switch message.type {
    case "describe":
      handleDescribe(message)
    case "synthesize":
      handleSynthesize(message)
    case "transcribe":
      handleTranscribe(message)
    case "audio-start":
      handleAudioStart(message)
    case "audio-chunk":
      handleAudioChunk(message)
    case "audio-stop":
      handleAudioStop(message)
    default:
      break
    }
  }

  private func handleDescribe(_ message: WyomingMessage) {
    print("handleDescribe called")
    sendInfo()
  }

  private func handleSynthesize(_ message: WyomingMessage) {
    print("handleSynthesize called")

    guard let ttsService = ttsService else {
      print("TTS service not available")
      return
    }

    guard let data = message.data,
      let text = data["text"] as? String
    else {
      print("No text in synthesize request")
      return
    }

    print("Synthesizing text: '\(text)'")

    var voiceIdentifier: String?
    if let voiceDict = data["voice"] as? [String: Any] {
      if let name = voiceDict["name"] as? String {
        voiceIdentifier = name
        print("Specified voice name: '\(name)'")
      } else if let language = voiceDict["language"] as? String {
        voiceIdentifier = language
        print("Specified voice language: '\(language)'")
      }
      // doesn't support multi-speaker
    } else {
      print("No voice specified, using default")
    }

    Task {
      print("Starting synthesis task...")
      do {
        let (audioData, audioFormat) = try await ttsService.synthesize(text: text, voiceIdentifier: voiceIdentifier)
        print("Synthesis complete: \(audioData.count) bytes at \(audioFormat.rate) Hz")
        sendAudioStream(audioData, format: audioFormat)
        print("Sent audio stream")
      } catch {
        print("Synthesis error: \(error)")
      }
    }
  }

  private func sendAudioStream(_ data: Data, format: AudioFormat) {
    let startMessage = wyomingProtocol.createAudioStartEvent(format: format)
    let startData = wyomingProtocol.serializeMessage(startMessage)
    connection.send(content: startData, completion: .contentProcessed { _ in })

    let chunkSize = 2048
    var offset = 0

    while offset < data.count {
      let end = min(offset + chunkSize, data.count)
      let chunk = data.subdata(in: offset..<end)

      let chunkMessage = wyomingProtocol.createAudioChunkEvent(audioData: chunk, format: format)
      let chunkData = wyomingProtocol.serializeMessage(chunkMessage)
      connection.send(content: chunkData, completion: .contentProcessed { _ in })

      offset = end
    }

    let stopMessage = wyomingProtocol.createAudioStopEvent()
    let stopData = wyomingProtocol.serializeMessage(stopMessage)
    connection.send(content: stopData, completion: .contentProcessed { _ in })
  }

  private func handleTranscribe(_ message: WyomingMessage) {
    print("handleTranscribe called")

    if let data = message.data, let language = data["language"] as? String {
      transcribeLanguage = language
      print("Specified language: '\(language)'")
    } else {
      transcribeLanguage = nil
      print("No language specified, using default")
    }

    isTranscribing = true
    audioBuffer = Data()
  }

  private func handleAudioStart(_ message: WyomingMessage) {
    print("handleAudioStart called")

    if let data = message.data {
      if let rate = data["rate"] as? Int {
        audioSampleRate = rate
      }
      if let width = data["width"] as? Int {
        audioWidth = width
      }
      if let channels = data["channels"] as? Int {
        audioChannels = channels
      }
      print("audio-start: sample rate: \(audioSampleRate) Hz, width: \(audioWidth), channels: \(audioChannels)")
    }
  }

  private func handleAudioChunk(_ message: WyomingMessage) {
    print("handleAudioChunk called")

    guard isTranscribing else { return }

    if let payload = message.payload {
      audioBuffer.append(payload)
      print("audio-chunk: \(payload.count) bytes, total: \(audioBuffer.count) bytes")
    }
  }

  private func handleAudioStop(_ message: WyomingMessage) {
    print("handleAudioStop called")

    guard isTranscribing else { return }

    isTranscribing = false

    guard let sttService = sttService else {
      print("STT service not available")
      return
    }

    print("Starting transcription with \(audioBuffer.count) bytes of audio")

    Task {
      do {
        let text = try await sttService.transcribe(
          audioData: audioBuffer,
          sampleRate: audioSampleRate,
          channels: audioChannels,
          language: transcribeLanguage
        )
        print("Transcription complete: '\(text)'")
        sendTranscript(text)
      } catch {
        print("Transcription error: \(error)")
      }
    }
  }

  private func sendTranscript(_ text: String) {
    let message = wyomingProtocol.createTranscriptEvent(text: text)
    let data = wyomingProtocol.serializeMessage(message)

    connection.send(content: data, completion: .contentProcessed { _ in })
    print("Transcript sent")
  }
}
