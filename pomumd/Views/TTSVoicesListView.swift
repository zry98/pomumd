import AVFoundation
import SwiftUI

struct TTSVoicesListView: View {
  @Binding var defaultTTSVoice: String
  @State private var voices: [Voice] = []
  @State private var sortedVoices: [Voice] = []
  private let previewSynthesizer = AVSpeechSynthesizer()

  var body: some View {
    List {
      ForEach(sortedVoices, id: \.self.id) { voice in
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language) • \(voice.name)")
            Text(voice.id)
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          if defaultTTSVoice == voice.id {
            Image(systemName: "checkmark")
              .foregroundColor(.blue)
          }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
          playVoiceSample(voice)
          defaultTTSVoice = voice.id
        }
      }
    }
    .navigationTitle("TTS Voices")
    .inlineNavigationBarTitle()
    .onAppear {
      voices = TTSService.getAvailableVoices()
      updateSortedVoices()
    }
    .onChange(of: voices) { _ in
      updateSortedVoices()
    }
  }

  private func updateSortedVoices() {
    sortedVoices = voices.sorted { v1, v2 in
      if v1.language != v2.language {
        return v1.language.localizedCaseInsensitiveCompare(v2.language) == .orderedAscending
      }
      return v1.name.localizedCaseInsensitiveCompare(v2.name) == .orderedAscending
    }
  }

  private func playVoiceSample(_ voice: Voice) {
    // stop any currently playing speech
    if previewSynthesizer.isSpeaking {
      previewSynthesizer.stopSpeaking(at: .immediate)
    }

    let utterance = AVSpeechUtterance(string: "Hello world")
    if let avVoice = AVSpeechSynthesisVoice(identifier: voice.id) {
      utterance.voice = avVoice
    }
    previewSynthesizer.speak(utterance)
  }
}
