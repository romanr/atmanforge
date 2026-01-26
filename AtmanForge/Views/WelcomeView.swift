import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.artframe")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Welcome to AtmanForge")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Choose a folder to store your projects.\nAll projects and canvases will be saved here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Choose Projects Folder...") {
                pickFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose Projects Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.setProjectsRoot(url)
        }
        #endif
    }
}
