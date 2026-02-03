import SwiftUI

@main
struct pomumdApp: App {
  @StateObject private var serverManager = ServerManager()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(serverManager)
        .onAppear {
          startServers()
        }
    }
  }

  private func startServers() {
    serverManager.requestPermissions { authorized in
      if authorized {
        serverManager.startServers()
      }
    }
  }
}
