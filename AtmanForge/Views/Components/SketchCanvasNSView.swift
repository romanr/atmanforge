import SwiftUI

#if os(macOS)

/// A stroke with points in normalized image coordinates (0...1 relative to the image dimensions).
struct SketchStroke {
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat // normalized relative to image width
}

struct SketchCanvasNSView: NSViewRepresentable {
    var image: NSImage
    @Binding var strokes: [SketchStroke]
    @Binding var currentStroke: SketchStroke?
    @Binding var redoStack: [SketchStroke]
    var brushColor: NSColor
    /// Brush size in display points (will be normalized on save).
    var brushSize: CGFloat

    func makeNSView(context: Context) -> SketchDrawingView {
        let view = SketchDrawingView()
        view.image = image
        view.strokes = strokes
        view.currentStroke = currentStroke
        view.brushColor = brushColor
        view.brushSize = brushSize
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SketchDrawingView, context: Context) {
        nsView.image = image
        nsView.strokes = strokes
        nsView.currentStroke = currentStroke
        nsView.brushColor = brushColor
        nsView.brushSize = brushSize
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: SketchDrawingViewDelegate {
        var parent: SketchCanvasNSView

        init(parent: SketchCanvasNSView) {
            self.parent = parent
        }

        func strokeUpdated(_ stroke: SketchStroke) {
            DispatchQueue.main.async {
                self.parent.currentStroke = stroke
            }
        }

        func strokeFinished(_ stroke: SketchStroke) {
            DispatchQueue.main.async {
                self.parent.strokes.append(stroke)
                self.parent.currentStroke = nil
                self.parent.redoStack.removeAll()
            }
        }

        func undoRequested() {
            DispatchQueue.main.async {
                guard let last = self.parent.strokes.popLast() else { return }
                self.parent.redoStack.append(last)
            }
        }

        func redoRequested() {
            DispatchQueue.main.async {
                guard let stroke = self.parent.redoStack.popLast() else { return }
                self.parent.strokes.append(stroke)
            }
        }
    }
}

protocol SketchDrawingViewDelegate: AnyObject {
    func strokeUpdated(_ stroke: SketchStroke)
    func strokeFinished(_ stroke: SketchStroke)
    func undoRequested()
    func redoRequested()
}

class SketchDrawingView: NSView {
    var image: NSImage?
    var strokes: [SketchStroke] = []
    var currentStroke: SketchStroke?
    var brushColor: NSColor = .black
    var brushSize: CGFloat = 4.0
    weak var delegate: SketchDrawingViewDelegate?

    private var activeStroke: SketchStroke?
    private var cursorPosition: CGPoint?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(self)
        } else {
            NSCursor.unhide()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// Returns the aspect-fit rect for the image within the given bounds (flipped coordinate system).
    func aspectFitRect(for imageSize: CGSize, in rect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let widthRatio = rect.width / imageSize.width
        let heightRatio = rect.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let x = rect.origin.x + (rect.width - scaledWidth) / 2
        let y = rect.origin.y + (rect.height - scaledHeight) / 2
        return NSRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }

    /// Convert a view point (flipped) to normalized image coordinates (0...1).
    private func viewPointToNormalized(_ point: CGPoint) -> CGPoint? {
        guard let imageSize = image?.size else { return nil }
        let fitRect = aspectFitRect(for: imageSize, in: bounds)
        guard fitRect.width > 0, fitRect.height > 0 else { return nil }
        return CGPoint(
            x: (point.x - fitRect.origin.x) / fitRect.width,
            y: (point.y - fitRect.origin.y) / fitRect.height
        )
    }

    /// Convert a normalized image coordinate to a view point (flipped).
    private func normalizedToViewPoint(_ point: CGPoint) -> CGPoint {
        guard let imageSize = image?.size else { return .zero }
        let fitRect = aspectFitRect(for: imageSize, in: bounds)
        return CGPoint(
            x: point.x * fitRect.width + fitRect.origin.x,
            y: point.y * fitRect.height + fitRect.origin.y
        )
    }

    /// Convert normalized line width to view line width.
    private func normalizedToViewLineWidth(_ normalized: CGFloat) -> CGFloat {
        guard let imageSize = image?.size else { return normalized }
        let fitRect = aspectFitRect(for: imageSize, in: bounds)
        guard fitRect.width > 0 else { return normalized }
        return normalized * fitRect.width
    }

    /// Convert view-space brush size to normalized line width.
    private func viewToNormalizedLineWidth(_ viewWidth: CGFloat) -> CGFloat {
        guard let imageSize = image?.size else { return viewWidth }
        let fitRect = aspectFitRect(for: imageSize, in: bounds)
        guard fitRect.width > 0 else { return viewWidth }
        return viewWidth / fitRect.width
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Clear background
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        // Draw the reference image aspect-fit (respectFlipped for isFlipped=true)
        if let image = image {
            let imageRect = aspectFitRect(for: image.size, in: bounds)
            image.draw(in: imageRect, from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        }

        // Draw committed strokes (convert from normalized to view coords)
        for stroke in strokes {
            drawStroke(stroke)
        }

        // Draw current in-progress stroke
        if let current = currentStroke {
            drawStroke(current)
        }

        // Draw brush cursor outline
        if let pos = cursorPosition {
            let rect = NSRect(
                x: pos.x - brushSize / 2,
                y: pos.y - brushSize / 2,
                width: brushSize,
                height: brushSize
            )
            let cursorPath = NSBezierPath(ovalIn: rect)
            cursorPath.lineWidth = 1.0
            NSColor.white.withAlphaComponent(0.9).setStroke()
            cursorPath.stroke()
            // Inner dark ring for contrast
            let innerPath = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            innerPath.lineWidth = 0.5
            NSColor.black.withAlphaComponent(0.5).setStroke()
            innerPath.stroke()
        }
    }

    private func drawStroke(_ stroke: SketchStroke) {
        guard !stroke.points.isEmpty else { return }

        let viewPoints = stroke.points.map { normalizedToViewPoint($0) }
        let viewLineWidth = normalizedToViewLineWidth(stroke.lineWidth)

        if viewPoints.count == 1 {
            let point = viewPoints[0]
            let rect = NSRect(
                x: point.x - viewLineWidth / 2,
                y: point.y - viewLineWidth / 2,
                width: viewLineWidth,
                height: viewLineWidth
            )
            stroke.color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return
        }

        let path = NSBezierPath()
        path.lineWidth = viewLineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: viewPoints[0])
        for i in 1..<viewPoints.count {
            path.line(to: viewPoints[i])
        }

        stroke.color.setStroke()
        path.stroke()
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == "z" {
            if flags == [.command, .shift] {
                delegate?.redoRequested()
                return
            } else if flags == .command {
                delegate?.undoRequested()
                return
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == "z" {
            if flags == [.command, .shift] {
                delegate?.redoRequested()
                return true
            } else if flags == .command {
                delegate?.undoRequested()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        cursorPosition = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.hide()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.unhide()
        cursorPosition = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        cursorPosition = viewPoint
        guard let normalized = viewPointToNormalized(viewPoint) else { return }

        let normalizedWidth = viewToNormalizedLineWidth(brushSize)
        activeStroke = SketchStroke(points: [normalized], color: brushColor, lineWidth: normalizedWidth)
        delegate?.strokeUpdated(activeStroke!)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var stroke = activeStroke else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        cursorPosition = viewPoint
        guard let normalized = viewPointToNormalized(viewPoint) else { return }

        stroke.points.append(normalized)
        activeStroke = stroke
        delegate?.strokeUpdated(stroke)
    }

    override func mouseUp(with event: NSEvent) {
        guard let stroke = activeStroke else { return }
        activeStroke = nil
        delegate?.strokeFinished(stroke)
    }
}

#endif
