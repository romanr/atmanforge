import SwiftUI

@main
struct AtmanForgeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            ProjectCommands(appState: appState)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
        }
        #endif
    }
}

struct ProjectCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandMenu("Project") {
            Button("New Project...") {
                appState.showNewProjectAlert = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open Project...") {
                openProjectFolder()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("New Canvas...") {
                appState.showNewCanvasAlert = true
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(!appState.hasProjectsRoot || appState.selectedProjectID == nil)

            Divider()

            Button("Close Project") {
                appState.closeProject()
            }
            .disabled(!appState.hasProjectsRoot)
        }
    }

    private func openProjectFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Open Projects Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            appState.openProject(url: url)
        }
        #endif
    }
}
