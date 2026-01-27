import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AIGenerationPanel: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isDropTargeted = false
    @State private var promptDebounceTask: Task<Void, Never>?

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 12) {
            Text("Model")
                .font(.headline)

            VStack(spacing: 6) {
                ForEach(AIModel.allCases, id: \.self) { model in
                    Button {
                        appState.selectedModel = model
                        appState.onModelChanged()
                    } label: {
                        HStack {
                            Text(model.displayName)
                                .fontWeight(appState.selectedModel == model ? .semibold : .regular)
                            Spacer()
                            if appState.selectedModel == model {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(appState.selectedModel == model ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(appState.selectedModel == model ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.selectedModel == model ? .primary : .secondary)
                }
            }

            Divider()

            // Reference Images
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Reference Images")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !appState.referenceImages.isEmpty {
                        Button("Clear") {
                            appState.referenceImages.removeAll()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3))
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                        )
                        .frame(minHeight: appState.referenceImages.isEmpty ? 100 : 80)

                    if appState.referenceImages.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("Drop images here")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(appState.referenceImages.enumerated()), id: \.offset) { index, imageData in
                                    ZStack(alignment: .topTrailing) {
                                        #if os(macOS)
                                        if let nsImage = NSImage(data: imageData) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 64, height: 64)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        #else
                                        if let uiImage = UIImage(data: imageData) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 64, height: 64)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        #endif

                                        Button {
                                            appState.removeReferenceImage(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .offset(x: 4, y: -4)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                }
                .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }

                HStack {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: max(appState.selectedModel.maxReferenceImages - appState.referenceImages.count, 1),
                        matching: .images
                    ) {
                        Label("Browse", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .disabled(appState.referenceImages.count >= appState.selectedModel.maxReferenceImages)
                    .onChange(of: selectedPhotos) { _, newItems in
                        Task {
                            var newImages: [Data] = []
                            for item in newItems {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    newImages.append(data)
                                }
                            }
                            appState.addReferenceImages(newImages)
                            selectedPhotos = []
                        }
                    }

                    Spacer()

                    Text("\(appState.referenceImages.count)/\(appState.selectedModel.maxReferenceImages) max")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $appState.prompt)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Text("Aspect Ratio")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Aspect Ratio", selection: $appState.selectedAspectRatio) {
                    ForEach(appState.selectedModel.supportedAspectRatios, id: \.self) { ratio in
                        Text(ratio.displayName).tag(ratio)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if appState.selectedModel.supportsResolution {
                HStack {
                    Text("Resolution")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Resolution", selection: $appState.selectedResolution) {
                        ForEach(ImageResolution.allCases, id: \.self) { res in
                            Text(res.displayName).tag(res)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            HStack {
                Text("Images")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.imageCount)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { Double(appState.imageCount) },
                        set: { appState.imageCount = Int($0) }
                    ),
                    in: 1...Double(appState.selectedModel.maxImageCount),
                    step: 1
                )
                .frame(width: 100)
            }

            if appState.selectedModel == .gptImage15 {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("GPT Settings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Quality")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Quality", selection: $appState.gptQuality) {
                            ForEach(GPTQuality.allCases, id: \.self) { quality in
                                Text(quality.displayName).tag(quality)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    HStack {
                        Text("Background")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Background", selection: $appState.gptBackground) {
                            ForEach(GPTBackground.allCases, id: \.self) { bg in
                                Text(bg.displayName).tag(bg)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    HStack {
                        Text("Input Fidelity")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Input Fidelity", selection: $appState.gptInputFidelity) {
                            ForEach(GPTInputFidelity.allCases, id: \.self) { fidelity in
                                Text(fidelity.displayName).tag(fidelity)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            Button {
                appState.generateImage()
            } label: {
                HStack {
                    if appState.runningJobCount > 0 {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(appState.runningJobCount > 0 ? "Generate (\(appState.runningJobCount) running)" : "Generate")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .onChange(of: appState.prompt) {
            promptDebounceTask?.cancel()
            promptDebounceTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                appState.commitUndoCheckpoint()
            }
        }
        .onChange(of: appState.selectedModel) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.selectedAspectRatio) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.selectedResolution) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.imageCount) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.gptQuality) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.gptBackground) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.gptInputFidelity) {
            appState.commitUndoCheckpoint()
        }
        .onChange(of: appState.referenceImages) {
            appState.commitUndoCheckpoint()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let remaining = appState.selectedModel.maxReferenceImages - appState.referenceImages.count
        guard remaining > 0 else { return false }

        let providersToProcess = Array(providers.prefix(remaining))
        for provider in providersToProcess {
            // Try loading as file URL first (common for Finder drag)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let imageData = try? Data(contentsOf: url) else { return }
                    DispatchQueue.main.async {
                        appState.addReferenceImages([imageData])
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async {
                        appState.addReferenceImages([data])
                    }
                }
            }
        }
        return true
    }
}
