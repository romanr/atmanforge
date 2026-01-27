import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ActivityView: View {
    @Environment(AppState.self) private var appState
    var thumbnailMaxSize: CGFloat = 64

    private var projectRoot: URL? {
        appState.projectManager.projectsRootURL
    }

    var body: some View {
        Group {
            if appState.generationJobs.isEmpty {
                emptyState
            } else {
                jobListView
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
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No activity yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Generated images will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var jobListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.generationJobs) { job in
                    jobRow(job)
                    Divider()
                }
            }
        }
    }

    private func jobRow(_ job: GenerationJob) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Status icon or spinner
            Group {
                if job.status == .running {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: job.statusIcon)
                        .foregroundStyle(job.statusColor)
                }
            }
            .frame(width: 20)
            .padding(.top, 2)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(job.model.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(job.progressText)
                        .font(.caption)
                        .foregroundStyle(job.statusColor)
                    Spacer()
                    Text(relativeTime(job.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(job.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if job.status == .completed && !job.thumbnailPaths.isEmpty, let root = projectRoot {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(job.thumbnailPaths.enumerated()), id: \.element) { index, thumbPath in
                            let savedURL = index < job.savedImagePaths.count
                                ? root.appendingPathComponent(job.savedImagePaths[index])
                                : nil
                            thumbnailImage(
                                root.appendingPathComponent(thumbPath),
                                aspectRatio: job.aspectRatio,
                                isSelected: appState.selectedImageJob?.id == job.id && appState.selectedImageIndex == index,
                                savedImageURL: savedURL
                            ) {
                                appState.selectImage(job: job, index: index)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                if job.status == .completed && !job.savedImagePaths.isEmpty && job.thumbnailPaths.isEmpty {
                    Text("\(job.savedImagePaths.count) image\(job.savedImagePaths.count == 1 ? "" : "s") saved")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                if let error = job.errorMessage, job.status == .failed {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                if job.status == .completed || job.status == .failed {
                    HStack(spacing: 12) {
                        Button {
                            appState.prompt = job.prompt
                        } label: {
                            Label("Reuse Prompt", systemImage: "text.quote")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)

                        Button {
                            appState.loadSettings(from: job)
                        } label: {
                            Label("Reuse Parameters", systemImage: "arrow.counterclockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(job.status == .running ? Color.accentColor.opacity(0.05) : Color.clear)
    }

    private func thumbnailImage(_ url: URL, aspectRatio: AspectRatio, isSelected: Bool = false, savedImageURL: URL? = nil, onTap: (() -> Void)? = nil) -> some View {
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

        return ThumbnailHoverView(url: url, width: thumbWidth, height: thumbHeight, isSelected: isSelected, savedImageURL: savedImageURL, onTap: onTap)
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}

struct ThumbnailHoverView: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat
    var isSelected: Bool = false
    var savedImageURL: URL?
    var onTap: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        #if os(macOS)
        if let nsImage = NSImage(contentsOf: url) {
            imageContent(Image(nsImage: nsImage))
                .contextMenu { contextMenuItems }
        }
        #else
        if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
            imageContent(Image(uiImage: uiImage))
                .contextMenu { contextMenuItems }
        }
        #endif
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let fileURL = savedImageURL {
            Button {
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                #endif
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }

    private func imageContent(_ image: Image) -> some View {
        #if os(macOS)
        NativeHoverZoomView(
            nsImage: NSImage(contentsOf: url),
            width: width,
            height: height,
            isSelected: isSelected,
            onTap: onTap
        )
        .frame(width: width, height: height)
        #else
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
            .onTapGesture { onTap?() }
        #endif
    }
}

#if os(macOS)
struct NativeHoverZoomView: NSViewRepresentable {
    let nsImage: NSImage?
    let width: CGFloat
    let height: CGFloat
    var isSelected: Bool
    var onTap: (() -> Void)?

    func makeNSView(context: Context) -> HoverZoomNSView {
        let view = HoverZoomNSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.image = nsImage
        view.cornerRadius = 4
        view.onTap = onTap
        return view
    }

    func updateNSView(_ nsView: HoverZoomNSView, context: Context) {
        nsView.onTap = onTap
        nsView.updateSelection(isSelected)
    }
}

class HoverZoomNSView: NSView {
    var image: NSImage? {
        didSet { imageLayer.contents = image }
    }
    var cornerRadius: CGFloat = 4
    var onTap: (() -> Void)?

    private let imageLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.cornerRadius = cornerRadius
        layer?.addSublayer(imageLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.controlAccentColor.cgColor
        borderLayer.lineWidth = 2
        borderLayer.opacity = 0
        layer?.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                   cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                                   transform: nil)
        CATransaction.commit()
    }

    func updateSelection(_ selected: Bool) {
        borderLayer.opacity = selected ? 1 : 0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageLayer.setAffineTransform(CGAffineTransform(scaleX: 1.15, y: 1.15))
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageLayer.setAffineTransform(.identity)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onTap?()
    }
}
#endif

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if i > 0 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for (i, row) in rows.enumerated() {
            if i > 0 { y += spacing }
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[Int]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[Int]] = [[]]
        var currentWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(index)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
