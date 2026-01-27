import SwiftUI
#if os(macOS)
import AppKit
#endif

struct HorizontalClipShape: Shape {
    var clipFromX: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: clipFromX, y: 0, width: rect.width - clipFromX, height: rect.height))
    }
}

struct ImageInspectorView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedReferenceIndex: Int = 0
    @State private var comparisonPosition: CGFloat = 0.0

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
                        comparisonImageView(job)
                        referenceImageThumbnails(job)
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
            .onChange(of: appState.selectedImageJob?.id) { _, _ in
                selectedReferenceIndex = 0
                comparisonPosition = 0.0
            }
            .onChange(of: appState.selectedImageIndex) { _, _ in
                selectedReferenceIndex = 0
                comparisonPosition = 0.0
            }
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
    private func comparisonImageView(_ job: GenerationJob) -> some View {
        if job.referenceImagePaths.isEmpty || job.model == .removeBackground {
            fullImage(job)
        } else {
            comparisonSlider(job)
        }
    }

    @ViewBuilder
    private func comparisonSlider(_ job: GenerationJob) -> some View {
        if imageIndex < job.savedImagePaths.count, let root = projectRoot {
            let generatedURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
            let safeRefIndex = min(selectedReferenceIndex, job.referenceImagePaths.count - 1)
            let referenceURL = root.appendingPathComponent(job.referenceImagePaths[max(0, safeRefIndex)])

            #if os(macOS)
            if let generatedNS = NSImage(contentsOf: generatedURL),
               let referenceNS = NSImage(contentsOf: referenceURL) {
                comparisonOverlay(
                    referenceImage: Image(nsImage: referenceNS),
                    generatedImage: Image(nsImage: generatedNS),
                    generatedURL: generatedURL
                )
            } else {
                fullImage(job)
            }
            #else
            if let genData = try? Data(contentsOf: generatedURL),
               let genUI = UIImage(data: genData),
               let refData = try? Data(contentsOf: referenceURL),
               let refUI = UIImage(data: refData) {
                comparisonOverlay(
                    referenceImage: Image(uiImage: refUI),
                    generatedImage: Image(uiImage: genUI),
                    generatedURL: generatedURL
                )
            } else {
                fullImage(job)
            }
            #endif
        }
    }

    private func comparisonOverlay(referenceImage: Image, generatedImage: Image, generatedURL: URL) -> some View {
        GeometryReader { geo in
            let dividerX = geo.size.width * comparisonPosition

            ZStack(alignment: .leading) {
                // Base layer: reference image
                referenceImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Overlay: generated image clipped from dividerX to right
                generatedImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .clipShape(HorizontalClipShape(clipFromX: dividerX))
                    .contextMenu {
                        imageContextMenu(imageURL: generatedURL)
                    }

                // Divider line + handle
                dividerHandle(dividerX: dividerX, height: geo.size.height)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        comparisonPosition = min(max(value.location.x / geo.size.width, 0), 1)
                    }
            )
        }
        .aspectRatio(contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func dividerHandle(dividerX: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: height)
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0)

            // Circle handle
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 0)
                .overlay {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                }
        }
        .position(x: dividerX, y: height / 2)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func referenceImageThumbnails(_ job: GenerationJob) -> some View {
        if !job.referenceImagePaths.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reference Images")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            comparisonPosition = 0.5
                        }
                    } label: {
                        Text("Compare")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(job.referenceImagePaths.enumerated()), id: \.offset) { index, path in
                            if let root = projectRoot {
                                let url = root.appendingPathComponent(path)
                                referenceThumbnail(url: url, isSelected: index == selectedReferenceIndex)
                                    .onTapGesture {
                                        selectedReferenceIndex = index
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func referenceThumbnail(url: URL, isSelected: Bool) -> some View {
        #if os(macOS)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        #else
        if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        #endif
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
                    .background(checkerboard)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onDrag {
                        NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
                    }
                    .contextMenu {
                        imageContextMenu(imageURL: imageURL)
                    }
            }
            #else
            if let data = try? Data(contentsOf: imageURL), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(checkerboard)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onDrag {
                        NSItemProvider(contentsOf: imageURL) ?? NSItemProvider()
                    }
                    .contextMenu {
                        imageContextMenu(imageURL: imageURL)
                    }
            }
            #endif
        }
    }

    private var checkerboard: some View {
        SwiftUI.Canvas { context, size in
            let sq: CGFloat = 8
            for row in 0..<Int(ceil(size.height / sq)) {
                for col in 0..<Int(ceil(size.width / sq)) {
                    let isLight = (row + col).isMultiple(of: 2)
                    context.fill(
                        Path(CGRect(x: CGFloat(col) * sq, y: CGFloat(row) * sq, width: sq, height: sq)),
                        with: .color(isLight ? Color(white: 0.9) : Color(white: 0.75))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func imageContextMenu(imageURL: URL) -> some View {
        #if os(macOS)
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([imageURL])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Divider()
        #endif

        Button {
            if let data = try? Data(contentsOf: imageURL) {
                appState.addReferenceImages([data])
            }
        } label: {
            Label("Add to Reference", systemImage: "photo.on.rectangle.angled")
        }

        Button {
            appState.prompt = ""
            appState.referenceImages.removeAll()
            if let data = try? Data(contentsOf: imageURL) {
                appState.addReferenceImages([data])
            }
            appState.commitUndoCheckpoint()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
    }

    private func metadataSection(_ job: GenerationJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(.subheadline)
                .fontWeight(.semibold)

            metadataRow("Model", value: job.model.displayName)

            if imageIndex < job.savedImagePaths.count, let root = projectRoot {
                let imageURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
                if let dimensions = imageSize(url: imageURL) {
                    metadataRow("Resolution", value: "\(dimensions.width) × \(dimensions.height)")
                }
                if let size = fileSize(url: imageURL) {
                    metadataRow("File Size", value: size)
                }
            }

            metadataRow("Created", value: formattedDate(job.createdAt))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(job.prompt, forType: .string)
                        #else
                        UIPasteboard.general.string = job.prompt
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy prompt")
                }
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

            VStack(spacing: 6) {
                Button {
                    guard imageIndex < job.savedImagePaths.count, let root = projectRoot else { return }
                    let imageURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
                    guard let data = try? Data(contentsOf: imageURL) else { return }
                    appState.prompt = ""
                    appState.referenceImages.removeAll()
                    appState.addReferenceImages([data])
                    appState.commitUndoCheckpoint()
                } label: {
                    Label("Edit Image", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    appState.removeBackground(job: job, imageIndex: imageIndex)
                } label: {
                    HStack {
                        if appState.isRemovingBackground {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label("Remove Background", systemImage: "person.and.background.dotted")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(appState.isRemovingBackground)

                #if os(macOS)
                Button {
                    guard imageIndex < job.savedImagePaths.count, let root = projectRoot else { return }
                    let imageURL = root.appendingPathComponent(job.savedImagePaths[imageIndex])
                    NSWorkspace.shared.activateFileViewerSelecting([imageURL])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                #endif
            }
        }
    }

    private func imageSize(url: URL) -> (width: Int, height: Int)? {
        #if os(macOS)
        guard let image = NSImage(contentsOf: url),
              let rep = image.representations.first else { return nil }
        return (rep.pixelsWide, rep.pixelsHigh)
        #else
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        return (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
        #endif
    }

    private func fileSize(url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return nil }
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
