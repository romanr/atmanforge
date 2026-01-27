import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    var thumbnailMaxSize: CGFloat = 96

    private var projectRoot: URL? {
        appState.projectManager.projectsRootURL
    }

    private var allImages: [(job: GenerationJob, index: Int, thumbPath: String)] {
        appState.generationJobs.flatMap { job in
            job.thumbnailPaths.enumerated().compactMap { index, thumbPath in
                guard job.status == .completed else { return nil }
                return (job: job, index: index, thumbPath: thumbPath)
            }
        }
    }

    var body: some View {
        Group {
            if allImages.isEmpty {
                emptyState
            } else {
                imageGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No images yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Generated images will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: thumbnailMaxSize), spacing: 8)],
                spacing: 8
            ) {
                ForEach(Array(allImages.enumerated()), id: \.offset) { _, entry in
                    if let root = projectRoot {
                        let savedURL = entry.index < entry.job.savedImagePaths.count
                            ? root.appendingPathComponent(entry.job.savedImagePaths[entry.index])
                            : nil
                        let isSelected = appState.selectedImageJob?.id == entry.job.id
                            && appState.selectedImageIndex == entry.index

                        gridThumbnail(
                            url: root.appendingPathComponent(entry.thumbPath),
                            aspectRatio: entry.job.aspectRatio,
                            isSelected: isSelected,
                            savedImageURL: savedURL
                        ) {
                            appState.selectImage(job: entry.job, index: entry.index)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func gridThumbnail(url: URL, aspectRatio: AspectRatio, isSelected: Bool, savedImageURL: URL?, onTap: @escaping () -> Void) -> some View {
        let maxDim = thumbnailMaxSize
        let (w, h) = aspectRatio.ratio
        let thumbWidth: CGFloat
        let thumbHeight: CGFloat
        if w >= h {
            thumbWidth = maxDim
            thumbHeight = maxDim * CGFloat(h) / CGFloat(w)
        } else {
            thumbHeight = maxDim
            thumbWidth = maxDim * CGFloat(w) / CGFloat(h)
        }

        return ThumbnailHoverView(
            url: url,
            width: thumbWidth,
            height: thumbHeight,
            isSelected: isSelected,
            savedImageURL: savedImageURL,
            onTap: onTap
        )
    }
}
