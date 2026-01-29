import AVFoundation
import Speech
import SwiftUI

struct ContentView: View {
  @StateObject private var ttsServer = WyomingServer(port: 10200, serviceType: .tts)
  @StateObject private var sttServer = WyomingServer(port: 10300, serviceType: .stt)
  @State private var showAlert = false
  @State private var alertTitle = ""
  @State private var alertMessage = ""
  @AppStorage("defaultTTSVoice") private var defaultTTSVoice: String = ""
  @AppStorage("defaultSTTLanguage") private var defaultSTTLanguage: String = ""

  var body: some View {
    NavigationView {
      List {
        Section("Text-to-Speech Service") {
          HStack {
            Text("Status")
            Spacer()
            Text(ttsServer.isRunning ? "Running" : "Stopped")
              .foregroundColor(ttsServer.isRunning ? .green : .red)
          }

          HStack {
            Text("Port")
            Spacer()
            Text("10200")
              .foregroundColor(.secondary)
          }

          NavigationLink(destination: TTSVoicesListView(defaultTTSVoice: $defaultTTSVoice)) {
            Text("Voices")
          }
        }

        Section("Speech-to-Text Service") {
          HStack {
            Text("Status")
            Spacer()
            Text(sttServer.isRunning ? "Running" : "Stopped")
              .foregroundColor(sttServer.isRunning ? .green : .red)
          }

          HStack {
            Text("Port")
            Spacer()
            Text("10300")
              .foregroundColor(.secondary)
          }

          NavigationLink(destination: STTLanguagesListView(defaultLangID: $defaultSTTLanguage)) {
            Text("Languages")
          }
        }

        Section {

          HStack {
            Text("IP Address")
            Spacer()
            Text(getIPAddress() ?? "?")
              .foregroundColor(.secondary)
              .textSelection(.enabled)
          }

          Button(action: restartServices) {
            HStack {
              Spacer()
              Text("Restart Services")
                .fontWeight(.semibold)
                .foregroundColor(.red)
              Spacer()
            }
          }
        }
      }
      .navigationTitle("Wyoming iOS")
      .alert(alertTitle, isPresented: $showAlert) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(alertMessage)
      }
      .onAppear {
        requestPermissions()
        restartServices()
      }
    }
  }

  private func restartServices() {
    ttsServer.stop()
    sttServer.stop()

    do {
      try ttsServer.start()
      try sttServer.start()
    } catch {
      alertTitle = "Error"
      alertMessage = error.localizedDescription
      showAlert = true
    }
  }

  private func getIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?

    if getifaddrs(&ifaddr) == 0 {
      var ptr = ifaddr
      while ptr != nil {
        defer { ptr = ptr?.pointee.ifa_next }

        guard let interface = ptr?.pointee else { continue }
        let addrFamily = interface.ifa_addr.pointee.sa_family

        if addrFamily == UInt8(AF_INET) {
          let name = String(cString: interface.ifa_name)
          if name == "en0" || name == "en1" {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
              interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
              &hostname, socklen_t(hostname.count),
              nil, socklen_t(0), NI_NUMERICHOST)
            address = String(cString: hostname)
          }
        }
      }
      freeifaddrs(ifaddr)
    }

    return address
  }

  private func requestPermissions() {
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        switch status {
        case .authorized:
          break
        case .denied:
          alertTitle = "Speech Recognition Denied"
          alertMessage = "Please enable speech recognition in Settings to use the Speech-to-Text service."
          showAlert = true
        case .restricted:
          alertTitle = "Speech Recognition Restricted"
          alertMessage = "Speech recognition is restricted on this device."
          showAlert = true
        case .notDetermined:
          fallthrough
        @unknown default:
          alertTitle = "Speech Recognition Status"
          alertMessage = "Unknown speech recognition authorization status."
          showAlert = true
        }
      }
    }
  }
}

#Preview {
  ContentView()
}
