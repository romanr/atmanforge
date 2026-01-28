import SwiftUI

#if os(macOS)

struct SketchEditorView: View {
    let imageData: Data
    var onSave: (Data) -> Void
    var onCancel: () -> Void

    @State private var strokes: [SketchStroke] = []
    @State private var currentStroke: SketchStroke?
    @State private var redoStack: [SketchStroke] = []
    @State private var brushSize: CGFloat = 4.0
    @State private var brushColor: Color = .red

    var body: some View {
        VStack(spacing: 0) {
            // Canvas
            SketchCanvasNSView(
                image: NSImage(data: imageData) ?? NSImage(),
                strokes: $strokes,
                currentStroke: $currentStroke,
                redoStack: $redoStack,
                brushColor: NSColor(brushColor),
                brushSize: brushSize
            )

            Divider()

            // Bottom bar with all controls
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Divider()
                    .frame(height: 20)

                ColorPicker("Color", selection: $brushColor)
                    .labelsHidden()

                Button {
                    pickColorFromScreen()
                } label: {
                    Image(systemName: "eyedropper")
                }
                .help("Pick color from screen")

                Divider()
                    .frame(height: 20)

                Button {
                    undoStroke()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(strokes.isEmpty)
                .help("Undo (⌘Z)")

                Button {
                    redoStroke()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(redoStack.isEmpty)
                .help("Redo (⇧⌘Z)")

                Spacer()

                Slider(value: $brushSize, in: 2...40)
                    .frame(width: 100)
                    .help("\(Int(brushSize))pt")

                Spacer()

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .frame(minWidth: 600, minHeight: 500)
        .onDisappear {
            NSColorPanel.shared.close()
        }
    }

    private func pickColorFromScreen() {
        let sampler = NSColorSampler()
        sampler.show { selectedColor in
            if let color = selectedColor {
                brushColor = Color(nsColor: color)
            }
        }
    }

    private func undoStroke() {
        guard let last = strokes.popLast() else { return }
        redoStack.append(last)
    }

    private func redoStroke() {
        guard let stroke = redoStack.popLast() else { return }
        strokes.append(stroke)
    }

    private func save() {
        guard let nsImage = NSImage(data: imageData) else {
            onCancel()
            return
        }

        let imageSize = nsImage.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            onCancel()
            return
        }

        // Render at full original resolution using a bitmap context
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(imageSize.width),
            pixelsHigh: Int(imageSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            onCancel()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            NSGraphicsContext.restoreGraphicsState()
            onCancel()
            return
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        // Bitmap context has bottom-left origin (not flipped).
        // Draw the original image in standard bottom-left coordinates.
        nsImage.draw(
            in: NSRect(origin: .zero, size: imageSize),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .sourceOver,
            fraction: 1.0
        )

        // Replay strokes: normalized coords use top-left origin (y=0 at top),
        // bitmap uses bottom-left origin, so flip Y: bitmapY = (1 - normalizedY) * height
        for stroke in strokes {
            guard !stroke.points.isEmpty else { continue }

            let imagePoints = stroke.points.map { pt in
                CGPoint(x: pt.x * imageSize.width, y: (1.0 - pt.y) * imageSize.height)
            }
            let imageLineWidth = stroke.lineWidth * imageSize.width

            if imagePoints.count == 1 {
                let pt = imagePoints[0]
                let rect = NSRect(
                    x: pt.x - imageLineWidth / 2,
                    y: pt.y - imageLineWidth / 2,
                    width: imageLineWidth,
                    height: imageLineWidth
                )
                stroke.color.setFill()
                NSBezierPath(ovalIn: rect).fill()
                continue
            }

            let path = NSBezierPath()
            path.lineWidth = imageLineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: imagePoints[0])
            for i in 1..<imagePoints.count {
                path.line(to: imagePoints[i])
            }
            stroke.color.setStroke()
            path.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            onCancel()
            return
        }

        onSave(pngData)
    }
}

#endif
