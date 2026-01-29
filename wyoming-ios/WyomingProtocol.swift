import Foundation

struct WyomingMessage {
  let type: String
  let data: [String: Any]?
  let payload: Data?
  let messageSize: Int

  init(type: String, data: [String: Any]? = nil, payload: Data? = nil, messageSize: Int = 0) {
    self.type = type
    self.data = data
    self.payload = payload
    self.messageSize = messageSize
  }
}

class WyomingProtocol {
  func parseMessage(from data: Data) -> WyomingMessage? {
    guard let newlineIndex = data.firstIndex(of: 0x0A) else {
      return nil
    }

    guard newlineIndex >= 0 && newlineIndex <= data.count else {
      print("Invalid newlineIndex: \(newlineIndex), data.count: \(data.count)")
      return nil
    }

    guard data.count > 0 else {
      print("Empty data buffer")
      return nil
    }

    let headerData = Data(data.prefix(newlineIndex))

    if let headerPreview = String(data: headerData.prefix(min(100, headerData.count)), encoding: .utf8) {
      print("Header preview: \(headerPreview)")
    }

    guard let headerString = String(data: headerData, encoding: .utf8),
      let headerJson = headerString.data(using: .utf8),
      let header = try? JSONSerialization.jsonObject(with: headerJson) as? [String: Any],
      let type = header["type"] as? String
    else {
      print("Failed to parse header")
      if let bufferPreview = String(data: data.prefix(min(200, data.count)), encoding: .utf8) {
        print("Buffer preview: \(bufferPreview)")
      }
      return nil
    }

    var messageData = header["data"] as? [String: Any]
    let dataLength = header["data_length"] as? Int ?? 0
    let payloadLength = header["payload_length"] as? Int ?? 0

    let headerSize = newlineIndex + 1  // +1 for newline after header
    var expectedSize = headerSize
    if dataLength > 0 {
      expectedSize += dataLength
    }
    if payloadLength > 0 {
      expectedSize += payloadLength
    }
    print(
      "Message type=\(type), newlineIndex=\(newlineIndex), headerSize=\(headerSize), dataLength=\(dataLength), payloadLength=\(payloadLength), expectedSize=\(expectedSize), bufferSize=\(data.count)"
    )

    if data.count < expectedSize {
      print("Incomplete message: have \(data.count) bytes, need \(expectedSize) bytes")
      return nil
    }

    var payload: Data?
    // parse additional data if present and merge with header data
    if dataLength > 0 {
      let dataStart = headerSize
      let dataEnd = dataStart + dataLength

      guard dataEnd <= data.count else {
        print("Invalid data range: \(dataStart)..<\(dataEnd), data.count: \(data.count)")
        return nil
      }

      let dataBytes = Data(data.dropFirst(dataStart).prefix(dataLength))
      if let dataString = String(data: dataBytes, encoding: .utf8),
        let dataJson = dataString.data(using: .utf8),
        let additionalData = try? JSONSerialization.jsonObject(with: dataJson) as? [String: Any]
      {
        // merge additional data on top of header data (per Wyoming protocol spec)
        if messageData == nil {
          messageData = [:]
        }
        for (key, value) in additionalData {
          messageData?[key] = value
        }
      }
    }

    // extract payload if present
    // payload comes immediately after data (NO trailing newline)
    if payloadLength > 0 {
      let payloadStart = headerSize + (dataLength > 0 ? dataLength : 0)
      let payloadEnd = payloadStart + payloadLength

      guard payloadEnd <= data.count else {
        print("Invalid payload range: \(payloadStart)..<\(payloadEnd), data.count: \(data.count)")
        return nil
      }

      payload = Data(data.dropFirst(payloadStart).prefix(payloadLength))
    }

    return WyomingMessage(type: type, data: messageData, payload: payload, messageSize: expectedSize)
  }

  func serializeMessage(_ message: WyomingMessage) -> Data {
    var result = Data()
    var dataBytes: Data?
    if let data = message.data {
      dataBytes = try? JSONSerialization.data(withJSONObject: data, options: [])
    }

    var header: [String: Any] = [
      "type": message.type,
      "version": "1.8.0",
    ]

    // if data exists
    if let dataBytes = dataBytes, dataBytes.count > 0 {
      header["data_length"] = dataBytes.count
    }

    // if payload exists
    if let payload = message.payload, payload.count > 0 {
      header["payload_length"] = payload.count
    }

    if let headerData = try? JSONSerialization.data(withJSONObject: header, options: []),
      let headerString = String(data: headerData, encoding: .utf8)
    {
      result.append(headerString.data(using: .utf8)!)
      result.append("\n".data(using: .utf8)!)
    }

    // if additional data exists
    if let dataBytes = dataBytes {
      result.append(dataBytes)
    }

    // if payload exists
    if let payload = message.payload {
      result.append(payload)
    }

    return result
  }

  func createInfoEvent(ttsVoices: [Voice], sttLanguages: [String]) -> WyomingMessage {
    var data: [String: Any] = [:]

    // TTS
    if !ttsVoices.isEmpty {
      let voicesList = ttsVoices.map { voice -> [String: Any] in
        return [
          "name": voice.id,
          "languages": [voice.language],
          "attribution": [
            "name": "Apple",
            "url": "https://www.apple.com",
          ],
          "installed": true,
        ]
      }

      let ttsProgram: [String: Any] = [
        "name": "wyoming-ios-tts",
        "description": "Wyoming Text-to-Speech using iOS AVSpeechSynthesizer",
        "installed": true,
        "attribution": [
          "name": "Apple",
          "url": "https://www.apple.com",
        ],
        "voices": voicesList,
        "supports_synthesize_streaming": false,
      ]

      data["tts"] = [ttsProgram]
    } else {
      data["tts"] = []
    }

    // STT
    if !sttLanguages.isEmpty {
      let asrModel: [String: Any] = [
        "name": "wyoming-ios-stt",
        "description": "Wyoming Speech-to-Text using iOS SpeechAnalyzer",
        "installed": true,
        "languages": sttLanguages,
        "attribution": [
          "name": "Apple",
          "url": "https://www.apple.com",
        ],
      ]

      let asrProgram: [String: Any] = [
        "name": "wyoming-ios-stt",
        "description": "Wyoming Speech-to-Text using iOS SpeechAnalyzer",
        "installed": true,
        "attribution": [
          "name": "Apple",
          "url": "https://www.apple.com",
        ],
        "models": [asrModel],
        "supports_transcript_streaming": false,
      ]

      data["asr"] = [asrProgram]
    } else {
      data["asr"] = []
    }

    return WyomingMessage(type: "info", data: data)
  }

  func createAudioStartEvent(format: AudioFormat) -> WyomingMessage {
    let data = format.toWyomingDict()
    return WyomingMessage(type: "audio-start", data: data)
  }

  func createAudioChunkEvent(audioData: Data, format: AudioFormat) -> WyomingMessage {
    let data = format.toWyomingDict()
    return WyomingMessage(type: "audio-chunk", data: data, payload: audioData)
  }

  func createAudioStopEvent() -> WyomingMessage {
    let data: [String: Any] = ["timestamp": NSNull()]
    return WyomingMessage(type: "audio-stop", data: data)
  }

  func createTranscriptEvent(text: String) -> WyomingMessage {
    let data: [String: Any] = ["text": text]
    return WyomingMessage(type: "transcript", data: data)
  }
}
