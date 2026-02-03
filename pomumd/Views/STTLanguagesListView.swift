import SwiftUI

struct STTLanguagesListView: View {
  @Binding var defaultLanguage: String
  @State private var languages: [String] = []
  @State private var sortedLanguages: [String] = []

  var body: some View {
    List {
      ForEach(sortedLanguages, id: \.self) { language in
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(Locale.current.localizedString(forIdentifier: language) ?? language)
            Text(language)
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          if defaultLanguage == language {
            Image(systemName: "checkmark")
              .foregroundColor(.blue)
          }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
          defaultLanguage = language
        }
      }
    }
    .navigationTitle("STT Languages")
    .inlineNavigationBarTitle()
    .onAppear {
      languages = STTService.getLanguages()
      updateSortedLanguages()
    }
    .onChange(of: languages) { _ in
      updateSortedLanguages()
    }
  }

  private func updateSortedLanguages() {
    sortedLanguages = languages.sorted { l1, l2 in
      return l1.localizedCaseInsensitiveCompare(l2) == .orderedAscending
    }
  }
}
