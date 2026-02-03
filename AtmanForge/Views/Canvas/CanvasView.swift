import SwiftUI
import ImageIO
#if os(macOS)
import AppKit
#endif

struct CanvasView: View {
    @Environment(AppState.self) private var appState
    @State private var image: CGImage?
    @State private var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                #if os(macOS)
                Color(nsColor: .windowBackgroundColor)
                #else
                Color(uiColor: .systemBackground)
                #endif

                if let image {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(appState.canvasZoom)
                        .offset(appState.canvasOffset)
                        .gesture(dragGesture)
                        .gesture(magnifyGesture)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.selectedCanvas != nil {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No image yet")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Use the AI Generation panel to create an image")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("Select a canvas")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { loadImage() }
        .onChange(of: appState.selectedCanvasID) { loadImage() }
        .onChange(of: appState.imageVersion) { loadImage() }
    }

    private func loadImage() {
        guard let canvas = appState.selectedCanvas,
              canvas.hasImage else {
            image = nil
            return
        }

        guard let source = CGImageSourceCreateWithURL(canvas.imageURL as CFURL, nil) else {
            image = nil
            return
        }

        // Read original dimensions
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
           let w = properties[kCGImagePropertyPixelWidth] as? Int,
           let h = properties[kCGImagePropertyPixelHeight] as? Int {
            imageSize = CGSize(width: w, height: h)
        }

        // Downsample large images for display performance
        let maxDisplayPixels: CGFloat = 2560
        let maxDim = max(imageSize.width, imageSize.height)

        if maxDim > maxDisplayPixels {
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxDisplayPixels,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                appState.canvasOffset = value.translation
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                appState.canvasZoom = max(0.1, min(value.magnification, 10.0))
            }
    }
}
