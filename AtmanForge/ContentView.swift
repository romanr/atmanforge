import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.hasProjectsRoot {
                mainLayout
            } else {
                WelcomeView()
            }
        }
        .navigationTitle(appState.projectName)
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            CanvasToolbar()
                .padding(.vertical, 4)

            Divider()

            HSplitView {
                GenerationSidebar()

                CenterPanelView()
                    .frame(minWidth: 480)

                if appState.selectedImageJob != nil {
                    ImageInspectorView()
                }
            }
        }
        .task {
            appState.loadProjects()
        }
        .alert("New Project", isPresented: newProjectBinding) {
            TextField("Project Name", text: newItemNameBinding)
            Button("Create") {
                let name = appState.newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    appState.createProject(name: name)
                }
                appState.newItemName = ""
            }
            Button("Cancel", role: .cancel) {
                appState.newItemName = ""
            }
        } message: {
            Text("Enter a name for the new project.")
        }
        .alert("New Canvas", isPresented: newCanvasBinding) {
            TextField("Canvas Name", text: newItemNameBinding)
            Button("Create") {
                let name = appState.newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, let projectID = appState.selectedProjectID {
                    appState.createCanvas(inProjectID: projectID, name: name)
                }
                appState.newItemName = ""
            }
            Button("Cancel", role: .cancel) {
                appState.newItemName = ""
            }
        } message: {
            Text("Enter a name for the new canvas.")
        }
    }

    private var newProjectBinding: Binding<Bool> {
        Binding(
            get: { appState.showNewProjectAlert },
            set: { appState.showNewProjectAlert = $0 }
        )
    }

    private var newCanvasBinding: Binding<Bool> {
        Binding(
            get: { appState.showNewCanvasAlert },
            set: { appState.showNewCanvasAlert = $0 }
        )
    }

    private var newItemNameBinding: Binding<String> {
        Binding(
            get: { appState.newItemName },
            set: { appState.newItemName = $0 }
        )
    }

}
