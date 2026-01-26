import SwiftUI

struct AIGenerationPanel: View {
    @Environment(AppState.self) private var appState

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
                Task {
                    await appState.generateImage()
                }
            } label: {
                HStack {
                    if appState.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(appState.isGenerating ? "Generating..." : "Generate")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appState.isGenerating || appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }
}
