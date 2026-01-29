import SwiftUI

struct STTLanguagesListView: View {
  @Binding var defaultLangID: String

  var body: some View {
    List {
      let languages = STTService().getLanguages().sorted { l1, l2 in
        return l1.localizedCaseInsensitiveCompare(l2) == .orderedAscending
      }

      ForEach(languages, id: \.self) { language in
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(Locale.current.localizedString(forIdentifier: language) ?? language)
            Text(language)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }

          Spacer()

          if defaultLangID == language {
            Image(systemName: "checkmark")
              .foregroundColor(.blue)
          }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
          defaultLangID = language
        }
      }
    }
    .navigationTitle("STT Languages")
    .navigationBarTitleDisplayMode(.inline)
  }
}
