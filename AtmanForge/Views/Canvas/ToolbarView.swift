import SwiftUI
import UniformTypeIdentifiers

struct CanvasToolbar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 4) {
            Button {
                appState.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!appState.canUndo)
            .help("Undo (⌘Z)")

            Button {
                appState.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .buttonStyle(.bordered)
            .disabled(!appState.canRedo)
            .help("Redo (⇧⌘Z)")

            Spacer()

            Button {
                exportImage()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(appState.selectedCanvas?.hasImage != true)
            .help("Export Image")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func exportImage() {
        #if os(macOS)
        guard let canvas = appState.selectedCanvas, canvas.hasImage else { return }

        let panel = NSSavePanel()
        panel.title = "Export Image"
        panel.nameFieldStringValue = "\(canvas.name).png"
        panel.allowedContentTypes = [.png, .jpeg]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: canvas.imageURL)
                try data.write(to: url)
                appState.statusMessage = "Exported to \(url.lastPathComponent)"
            } catch {
                appState.statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        #endif
    }
}
