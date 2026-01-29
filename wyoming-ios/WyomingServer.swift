import Combine
import Foundation
import Network

enum ServiceType {
  case tts
  case stt
}

class WyomingServer: ObservableObject {
  @Published var isRunning: Bool = false

  private var listener: NWListener?
  private let port: UInt16
  private let serviceType: ServiceType
  private let ttsService: TTSService?
  private let sttService: STTService?
  private var connections: [ConnectionHandler] = []

  init(port: UInt16, serviceType: ServiceType) {
    self.port = port
    self.serviceType = serviceType

    if serviceType == .tts {
      self.ttsService = TTSService()
    } else {
      self.ttsService = nil
    }

    if serviceType == .stt {
      self.sttService = STTService()
    } else {
      self.sttService = nil
    }
  }

  func start() throws {
    guard !isRunning else { return }

    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true

    guard let port = NWEndpoint.Port(rawValue: port) else {
      throw NSError(domain: "WyomingServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
    }

    listener = try NWListener(using: params, on: port)

    listener?.stateUpdateHandler = { [weak self] state in
      DispatchQueue.main.async {
        switch state {
        case .ready:
          self?.isRunning = true
        case .failed(let error):
          print("Server failed: \(error)")
          self?.isRunning = false
        case .cancelled:
          self?.isRunning = false
        default:
          break
        }
      }
    }

    listener?.newConnectionHandler = { [weak self] connection in
      self?.handleConnection(connection)
    }

    listener?.start(queue: .global(qos: .userInitiated))
  }

  func stop() {
    listener?.cancel()
    listener = nil

    // close all connections
    connections.forEach { $0.close() }
    connections.removeAll()

    DispatchQueue.main.async {
      self.isRunning = false
    }
  }

  private func handleConnection(_ connection: NWConnection) {
    let handler = ConnectionHandler(
      connection: connection,
      serviceType: serviceType,
      ttsService: ttsService,
      sttService: sttService
    )

    handler.onClose = { [weak self] in
      DispatchQueue.main.async {
        self?.connections.removeAll { $0 === handler }
      }
    }

    connections.append(handler)

    handler.start()
  }
}
