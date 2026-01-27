import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ImageInspectorView: View {
    @Environment(AppState.self) private var appState

    private var job: GenerationJob? {
        appState.selectedImageJob
    }

    private var imageIndex: Int {
        appState.selectedImageIndex
    }

    private var projectRoot: URL? {
        appState.projectManager.projectsRootURL
    }

    var body: some View {
        if let job = job {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fullImage(job)
                        metadataSection(job)
                        actionButtons(job)
                    }
                    .padding(16)
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #else
            .background(Color(uiColor: .systemBackground))
            #endif
        }
    }

    private var header: some View {
        HStack {
            Text("Inspector")
                .font(.headline)
            Spacer()
            Button {
                appState.clearImageSelection()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func fullImage(_ job: GenerationJob) -> some View {
        if imageIndex < job.savedImagePaths.count, let root = projectRoot {
            let imageURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
            #if os(macOS)
            if let nsImage = NSImage(contentsOf: imageURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onDrag {
                        NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
                    }
            }
            #else
            if let data = try? Data(contentsOf: imageURL), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onDrag {
                        NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
                    }
            }
            #endif
        }
    }

    private func metadataSection(_ job: GenerationJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.subheadline)
                .fontWeight(.semibold)

            metadataRow("Model", value: job.model.displayName)
            metadataRow("Aspect Ratio", value: job.aspectRatio.displayName)

            if let resolution = job.resolution {
                metadataRow("Resolution", value: resolution.displayName)
            }

            metadataRow("Image Count", value: "\(job.imageCount)")

            if let quality = job.gptQuality {
                metadataRow("GPT Quality", value: quality.displayName)
            }
            if let background = job.gptBackground {
                metadataRow("GPT Background", value: background.displayName)
            }
            if let fidelity = job.gptInputFidelity {
                metadataRow("GPT Input Fidelity", value: fidelity.displayName)
            }

            metadataRow("Created", value: formattedDate(job.createdAt))

            if imageIndex < job.savedImagePaths.count {
                metadataRow("File", value: job.savedImagePaths[imageIndex])
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(job.prompt)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func actionButtons(_ job: GenerationJob) -> some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    appState.prompt = job.prompt
                } label: {
                    Label("Reuse Prompt", systemImage: "text.quote")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Button {
                    appState.loadSettings(from: job)
                } label: {
                    Label("Reuse Parameters", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
