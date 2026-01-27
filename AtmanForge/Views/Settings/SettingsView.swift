import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var replicateKey: String = ""
    @State private var rootFolderPath: String = ""
    @State private var showSaveConfirmation = false

    var body: some View {
        Form {
            Section("API Keys") {
                SecureField("Replicate API Key", text: $replicateKey)
                    .textFieldStyle(.roundedBorder)

                Button("Save API Key") {
                    do {
                        try KeychainManager.save(key: "replicate_api_key", value: replicateKey)
                        showSaveConfirmation = true
                    } catch {
                        appState.statusMessage = "Failed to save API key: \(error.localizedDescription)"
                    }
                }
                .disabled(replicateKey.isEmpty)

                if showSaveConfirmation {
                    Text("API key saved.")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Section("Projects Folder") {
                HStack {
                    Text(rootFolderPath.isEmpty ? "Not set" : rootFolderPath)
                        .foregroundStyle(rootFolderPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    Button("Choose...") {
                        pickFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
        .onAppear {
            replicateKey = KeychainManager.load(key: "replicate_api_key") ?? ""
            rootFolderPath = appState.projectManager.projectsRootURL?.path ?? ""
        }
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
            rootFolderPath = url.path
        }
        #endif
    }
}
