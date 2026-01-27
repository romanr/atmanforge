import SwiftUI
#if os(macOS)
import AppKit
import ImageIO
#endif

// MARK: - Cached metadata per library image

struct LibraryImageEntry: Identifiable {
    let id: String
    let job: GenerationJob
    let imageIndex: Int
    let thumbPath: String
    let fileName: String
    let fileSize: UInt64
    let pixelWidth: Int
    let pixelHeight: Int

    var resolutionString: String {
        guard pixelWidth > 0 && pixelHeight > 0 else { return "—" }
        return "\(pixelWidth)×\(pixelHeight)"
    }

    var fileSizeString: String {
        guard fileSize > 0 else { return "—" }
        let mb = Double(fileSize) / (1024 * 1024)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(fileSize) / 1024
        return String(format: "%.0f KB", kb)
    }
}

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    var thumbnailMaxSize: CGFloat = 96

    private var projectRoot: URL? {
        appState.projectManager.projectsRootURL
    }

    // MARK: - Build entries with metadata

    private var allEntries: [LibraryImageEntry] {
        guard let root = projectRoot else { return [] }

        let entries: [LibraryImageEntry] = appState.generationJobs.flatMap { job -> [LibraryImageEntry] in
            guard job.status == .completed else { return [] }
            return job.thumbnailPaths.enumerated().compactMap { index, thumbPath -> LibraryImageEntry? in
                guard index < job.savedImagePaths.count else { return nil }
                let relativePath = job.savedImagePaths[index]
                let fileURL = root.appendingPathComponent(relativePath)
                let fileName = (relativePath as NSString).lastPathComponent

                // File size
                let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = attrs?[.size] as? UInt64 ?? 0

                // Pixel dimensions via CGImageSource (lightweight, no full decode)
                var pw = 0
                var ph = 0
                if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                    pw = props[kCGImagePropertyPixelWidth] as? Int ?? 0
                    ph = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                }

                return LibraryImageEntry(
                    id: "\(job.id)-\(index)",
                    job: job,
                    imageIndex: index,
                    thumbPath: thumbPath,
                    fileName: fileName,
                    fileSize: fileSize,
                    pixelWidth: pw,
                    pixelHeight: ph
                )
            }
        }

        return sortedEntries(entries)
    }

    private func sortedEntries(_ entries: [LibraryImageEntry]) -> [LibraryImageEntry] {
        let ascending = appState.librarySortAscending

        let sorted: [LibraryImageEntry]
        switch appState.librarySortOrder {
        case .dateAdded:
            sorted = entries.sorted {
                ascending
                    ? $0.job.createdAt < $1.job.createdAt
                    : $0.job.createdAt > $1.job.createdAt
            }
        case .name:
            sorted = entries.sorted {
                let cmp = $0.fileName.localizedStandardCompare($1.fileName)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .model:
            sorted = entries.sorted {
                let cmp = $0.job.model.displayName.localizedStandardCompare($1.job.model.displayName)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .resolution:
            sorted = entries.sorted {
                let areaA = $0.pixelWidth * $0.pixelHeight
                let areaB = $1.pixelWidth * $1.pixelHeight
                return ascending ? areaA < areaB : areaA > areaB
            }
        case .size:
            sorted = entries.sorted {
                ascending ? $0.fileSize < $1.fileSize : $0.fileSize > $1.fileSize
            }
        }
        return sorted
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if !allEntries.isEmpty {
                if appState.libraryViewMode == .grid {
                    gridHeaderBar
                } else {
                    listColumnHeader
                }
                Divider()
            }

            Group {
                if allEntries.isEmpty {
                    emptyState
                } else if appState.libraryViewMode == .grid {
                    imageGrid
                } else {
                    imageList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }

    // MARK: - Grid Header Bar

    private var gridHeaderBar: some View {
        HStack {
            gridSortMenu
            Spacer()
            viewModeToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var gridSortMenu: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                    Button {
                        if appState.librarySortOrder == order {
                            appState.librarySortAscending.toggle()
                        } else {
                            appState.librarySortOrder = order
                            appState.librarySortAscending = (order == .name || order == .model)
                        }
                    } label: {
                        HStack {
                            Text(order.label)
                            if appState.librarySortOrder == order {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("Sort: \(appState.librarySortOrder.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                appState.librarySortAscending.toggle()
            } label: {
                Image(systemName: appState.librarySortAscending ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var viewModeToggle: some View {
        HStack(spacing: 2) {
            Button {
                appState.libraryViewMode = .grid
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(appState.libraryViewMode == .grid ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                appState.libraryViewMode = .list
            } label: {
                Image(systemName: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(appState.libraryViewMode == .list ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - List Column Header

    private var listColumnHeader: some View {
        HStack(spacing: 0) {
            // Thumbnail spacer (48 + 10 spacing)
            Color.clear.frame(width: 58, height: 1)

            columnHeaderButton(.name, minWidth: 80)
            plainColumnHeader("Prompt", minWidth: 100)
            columnHeaderButton(.model, minWidth: 70)
            columnHeaderButton(.resolution, minWidth: 70)
            columnHeaderButton(.size, minWidth: 56)
            columnHeaderButton(.dateAdded, minWidth: 70)

            // View mode toggle on the right
            Spacer().frame(width: 4)
            viewModeToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func columnHeaderButton(_ order: LibrarySortOrder, minWidth: CGFloat) -> some View {
        let isActive = appState.librarySortOrder == order

        return Button {
            if isActive {
                appState.librarySortAscending.toggle()
            } else {
                appState.librarySortOrder = order
                // Text fields default ascending, numeric/date fields default descending
                switch order {
                case .name, .model:
                    appState.librarySortAscending = true
                case .resolution, .size, .dateAdded:
                    appState.librarySortAscending = false
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(order.label)
                    .font(.caption2)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)

                if isActive {
                    Image(systemName: appState.librarySortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minWidth: minWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func plainColumnHeader(_ title: String, minWidth: CGFloat) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minWidth: minWidth)
    }

    // MARK: - Empty State

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

    // MARK: - Grid View

    private var imageGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: thumbnailMaxSize), spacing: 8)],
                spacing: 8
            ) {
                ForEach(allEntries) { entry in
                    if let root = projectRoot {
                        let savedURL = root.appendingPathComponent(entry.job.savedImagePaths[entry.imageIndex])
                        let isSelected = appState.selectedImageJob?.id == entry.job.id
                            && appState.selectedImageIndex == entry.imageIndex

                        gridThumbnail(
                            url: root.appendingPathComponent(entry.thumbPath),
                            aspectRatio: entry.job.aspectRatio,
                            isSelected: isSelected,
                            savedImageURL: savedURL
                        ) {
                            appState.selectImage(job: entry.job, index: entry.imageIndex)
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

    // MARK: - List View

    private var imageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(allEntries) { entry in
                    if let root = projectRoot {
                        let savedURL = root.appendingPathComponent(entry.job.savedImagePaths[entry.imageIndex])
                        let isSelected = appState.selectedImageJob?.id == entry.job.id
                            && appState.selectedImageIndex == entry.imageIndex

                        listRow(entry: entry, root: root, isSelected: isSelected, savedImageURL: savedURL)
                    }
                }
            }
        }
    }

    private func listRow(entry: LibraryImageEntry, root: URL, isSelected: Bool, savedImageURL: URL?) -> some View {
        let thumbURL = root.appendingPathComponent(entry.thumbPath)

        return Button {
            appState.selectImage(job: entry.job, index: entry.imageIndex)
        } label: {
            HStack(spacing: 0) {
                listThumbnail(url: thumbURL)
                    .padding(.trailing, 10)

                Text(entry.fileName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minWidth: 80)

                Text(entry.job.prompt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minWidth: 100)

                Text(entry.job.model.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minWidth: 70)

                Text(entry.resolutionString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minWidth: 70)

                Text(entry.fileSizeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minWidth: 56)

                Text(dateLabel(for: entry.job.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minWidth: 70)

                // Spacer matching view mode toggle width
                Color.clear.frame(width: 54, height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            listContextMenu(savedImageURL: savedImageURL)
        }
    }

    private func listThumbnail(url: URL) -> some View {
        Group {
            #if os(macOS)
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                placeholderThumb
            }
            #else
            if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                placeholderThumb
            }
            #endif
        }
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 48, height: 48)
    }

    private func dateLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func listContextMenu(savedImageURL: URL?) -> some View {
        if let fileURL = savedImageURL {
            Button {
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                #endif
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            Button {
                if let data = try? Data(contentsOf: fileURL) {
                    appState.addReferenceImages([data])
                }
            } label: {
                Label("Add to Reference", systemImage: "photo.on.rectangle.angled")
            }

            Button {
                appState.prompt = ""
                appState.referenceImages.removeAll()
                if let data = try? Data(contentsOf: fileURL) {
                    appState.addReferenceImages([data])
                }
                appState.commitUndoCheckpoint()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }
}
