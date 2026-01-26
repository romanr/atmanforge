import SwiftUI

struct GenerationSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AIGenerationPanel()

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 250, idealWidth: 280, maxWidth: 320)
    }
}
