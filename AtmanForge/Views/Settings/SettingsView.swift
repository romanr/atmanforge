import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var replicateKey: String = ""
    @State private var googleAIKey: String = ""
    @State private var openAIKey: String = ""
    @State private var rootFolderPath: String = ""
    @State private var showSaveConfirmation = false

    var body: some View {
        Form {
            Section("API Keys") {
                SecureField("Google AI API Key", text: $googleAIKey)
                    .textFieldStyle(.roundedBorder)

                SecureField("OpenAI API Key", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)

                SecureField("Replicate API Key", text: $replicateKey)
                    .textFieldStyle(.roundedBorder)

                Button("Save API Keys") {
                    do {
                        try KeychainManager.save(key: "google_ai_api_key", value: googleAIKey)
                        try KeychainManager.save(key: "openai_api_key", value: openAIKey)
                        try KeychainManager.save(key: "replicate_api_key", value: replicateKey)
                        showSaveConfirmation = true
                    } catch {
                        appState.statusMessage = "Failed to save API keys: \(error.localizedDescription)"
                    }
                }
                .disabled(googleAIKey.isEmpty && openAIKey.isEmpty && replicateKey.isEmpty)

                if showSaveConfirmation {
                    Text("API keys saved.")
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
            googleAIKey = KeychainManager.load(key: "google_ai_api_key") ?? ""
            openAIKey = KeychainManager.load(key: "openai_api_key") ?? ""
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
