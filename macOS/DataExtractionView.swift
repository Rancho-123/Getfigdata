import SwiftUI
import AppKit
import QuartzCore

struct DataExtractionView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 12) {
            // 手动提取说明
            HStack {
                Spacer()
                Text("数据点: \(appState.extractedData.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // 图像交互视图（手动提取）
            if let image = appState.currentImage {
                DataExtractionImageView(
                    appState: appState,
                    image: image,
                    coordinateSystem: appState.coordinateSystem,
                    onPointExtracted: { pixelPoint in
                        appState.seedPixelForAuto = pixelPoint
                        extractPoint(at: pixelPoint)
                    },
                    points: appState.extractedData,
                    onColorPicked: { _, _ in }
                )
            } else {
                Text("请先加载图片")
                    .foregroundColor(.secondary)
            }

            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func extractPoint(at pixelPoint: CGPoint) {
        guard let coordinateSystem = appState.coordinateSystem else {
            return
        }
        
        guard let dataPoint = coordinateSystem.pixelToData(pixelPoint) else {
            return
        }
        
        let newDataPoint = DataPoint(
            pixelX: Double(pixelPoint.x),
            pixelY: Double(pixelPoint.y),
            dataX: dataPoint.x,
            dataY: dataPoint.y,
            isManual: true
        )
        
        appState.extractedData.append(newDataPoint)
        appState.extractedData.sort { $0.dataX < $1.dataX }
    }
    

    
    
}

struct DataPointsViewer: View {
    @ObservedObject var appState: AppState
    @State private var textContent = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("数据点（X 空格 Y）")
                .font(.headline)
            TextEditor(text: $textContent)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 360)
            HStack {
                Button("复制到剪贴板") { copyAll() }
                Spacer()
            }
        }
        .padding()
        .onAppear { rebuild() }
        .onReceive(appState.$extractedData) { _ in rebuild() }
        .onChange(of: appState.extractedData) { _ in rebuild() }
    }
    
    private func rebuild() {
        textContent = appState.extractedData
            .map { "\(fmt($0.dataX)) \(fmt($0.dataY))" }
            .joined(separator: "\n") + "\n"
    }
    
    private func fmt(_ v: Double) -> String {
        let a = abs(v)
        if a == 0 { return "0" }
        if a < 1e-6 || a >= 1e6 { return String(format: "%.6e", v) }
        return String(format: "%.6f", v)
    }
    
    private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textContent, forType: .string)
    }
}


struct DataExtractionImageView: NSViewRepresentable {
    let appState: AppState
    let image: NSImage
    let coordinateSystem: AffineCoordinateSystem?
    let onPointExtracted: (CGPoint) -> Void
    let points: [DataPoint]
    let onColorPicked: (NSColor, CGPoint) -> Void
    
    func makeNSView(context: Context) -> DataExtractionNSView {
        let view = DataExtractionNSView()
        view.appState = appState
        view.image = image
        view.coordinateSystem = coordinateSystem
        view.onPointExtracted = onPointExtracted
        view.overlayPoints = points
        view.onColorPicked = onColorPicked
        return view
    }
    
    func updateNSView(_ nsView: DataExtractionNSView, context: Context) {
        nsView.appState = appState
        nsView.image = image
        nsView.coordinateSystem = coordinateSystem
        nsView.overlayPoints = points
        nsView.onColorPicked = onColorPicked
        if appState.brushMask == nil { nsView.clearBrush() }
        let nonce = appState.overlayResetNonce
        if nsView.overlayResetNonce != nonce {
            nsView.clearBrush()
            nsView.overlayResetNonce = nonce
        }
        nsView.needsDisplay = true
    }
}

class DataExtractionNSView: NSView {
    var appState: AppState?
    var image: NSImage?
    var coordinateSystem: AffineCoordinateSystem?
    var onPointExtracted: ((CGPoint) -> Void)?
    var overlayPoints: [DataPoint] = []
    var lastSelectedPixel: CGPoint?
    var onColorPicked: ((NSColor, CGPoint) -> Void)?
    private var brushPoints: [CGPoint] = []
    var overlayResetNonce: Int = 0
    func clearBrush() { brushPoints.removeAll() }
    
    private var scale: CGFloat = 1.0
    private var translation = CGPoint.zero
    private var initialPinchDistance: CGFloat = 0
    
    private func currentDrawRect(for image: NSImage) -> CGRect {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: center.x - scaledSize.width / 2.0 + translation.x,
                             y: center.y - scaledSize.height / 2.0 + translation.y)
        return CGRect(origin: origin, size: scaledSize)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let image = image else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let drawRect = currentDrawRect(for: image)
        image.draw(in: drawRect)
        
        if let _ = coordinateSystem {
            context.setLineWidth(2)
            for (idx, dp) in overlayPoints.enumerated() {
                let px = drawRect.origin.x + CGFloat(dp.pixelX) * scale
                let py = drawRect.origin.y + CGFloat(dp.pixelY) * scale
                let r: CGFloat = 6
                let color = dp.isManual
                    ? NSColor(calibratedHue: 0.33, saturation: 0.65, brightness: 0.95, alpha: 1.0)
                    : NSColor(calibratedHue: 0.33, saturation: 0.85, brightness: 0.80, alpha: 1.0)
                context.setFillColor(color.cgColor)
                context.setStrokeColor(color.cgColor)
                let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
                let label = "\(idx + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: color
                ]
                label.draw(at: CGPoint(x: px + r + 2, y: py - r - 2), withAttributes: attrs)
            }
            if let app = appState, app.isBrushMode {
                context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.25).cgColor)
                for p in brushPoints {
                    let px = drawRect.origin.x + p.x * scale
                    let py = drawRect.origin.y + p.y * scale
                    let r = CGFloat(app.brushRadius)
                    let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    context.fillEllipse(in: rect)
                }
            }
            if let p = lastSelectedPixel {
                context.setStrokeColor(NSColor.systemBlue.cgColor)
                let px = drawRect.origin.x + p.x * scale
                let py = drawRect.origin.y + p.y * scale
                let s: CGFloat = 28
                context.move(to: CGPoint(x: px - s, y: py))
                context.addLine(to: CGPoint(x: px + s, y: py))
                context.move(to: CGPoint(x: px, y: py - s))
                context.addLine(to: CGPoint(x: px, y: py + s))
                context.strokePath()
            }
        }
        
    }
    
    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let pixelPoint = imagePixelPoint(for: viewPoint) {
            lastSelectedPixel = pixelPoint
            needsDisplay = true
            if let app = appState, app.isDeleteMode {
                app.deleteNearestPoint(at: pixelPoint)
            } else if let app = appState, app.isBrushMode {
                applyBrush(at: pixelPoint)
            } else {
                onPointExtracted?(pixelPoint)
                if let color = getPixelColor(at: pixelPoint) {
                    onColorPicked?(color, pixelPoint)
                }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let app = appState, app.isBrushMode, let pixelPoint = imagePixelPoint(for: viewPoint) {
            applyBrush(at: pixelPoint)
        }
    }

    private func applyBrush(at pixelPoint: CGPoint) {
        guard let app = appState, let image = image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let width = cgImage.width
        let height = cgImage.height
        let sx = CGFloat(width) / image.size.width
        let sy = CGFloat(height) / image.size.height
        let ix = Int(pixelPoint.x * sx)
        let iy0 = Int(pixelPoint.y * sy)
        let iy = max(0, min(height - 1, (height - 1) - iy0))
        if app.brushMask == nil { app.brushMask = BrushMask(width: width, height: height, bytes: [UInt8](repeating: 0, count: width * height)) }
        var mask = app.brushMask!
        let r = max(1, app.brushRadius)
        var yy = max(0, iy - r)
        while yy <= min(height - 1, iy + r) {
            var xx = max(0, ix - r)
            while xx <= min(width - 1, ix + r) {
                let dx = xx - ix
                let dy = yy - iy
                if dx*dx + dy*dy <= r*r { mask.bytes[yy * width + xx] = 1 }
                xx += 1
            }
            yy += 1
        }
        app.brushMask = mask
        brushPoints.append(pixelPoint)
        needsDisplay = true
    }
    
    private func imagePixelPoint(for viewPoint: CGPoint) -> CGPoint? {
        guard let image = image else { return nil }
        let drawRect = currentDrawRect(for: image)
        guard drawRect.contains(viewPoint) else { return nil }
        let x = (viewPoint.x - drawRect.origin.x) / scale
        let y = (viewPoint.y - drawRect.origin.y) / scale
        guard x >= 0, y >= 0, x <= image.size.width, y <= image.size.height else { return nil }
        return CGPoint(x: x, y: y)
    }
    private func getPixelColor(at pixelPoint: CGPoint) -> NSColor? {
        guard let image = image else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let sx = CGFloat(width) / image.size.width
        let sy = CGFloat(height) / image.size.height
        let ix = Int(pixelPoint.x * sx)
        let iy0 = Int(pixelPoint.y * sy)
        let iy = max(0, min(height - 1, (height - 1) - iy0))
        guard ix >= 0 && ix < width && iy >= 0 && iy < height else { return nil }
        guard let data = cgImage.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return nil }
        let offset = (iy * width + ix) * 4
        let r = CGFloat(ptr[offset]) / 255.0
        let g = CGFloat(ptr[offset + 1]) / 255.0
        let b = CGFloat(ptr[offset + 2]) / 255.0
        let a = CGFloat(ptr[offset + 3]) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: a)
    }
    
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupGestures()
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
        wantsLayer = true
    }
    
    private func setupGestures() {
        let magnificationGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        addGestureRecognizer(magnificationGesture)
    }
    
    @objc private func handleMagnify(_ gr: NSMagnificationGestureRecognizer) {
        switch gr.state {
        case .began:
            initialPinchDistance = scale
        case .changed:
            let newScale = initialPinchDistance * (1.0 + gr.magnification)
            scale = max(0.5, min(5.0, newScale))
            clampTranslation()
            needsDisplay = true
        default:
            break
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        translation.x += dx
        translation.y -= dy
        clampTranslation()
        needsDisplay = true
    }
    
    private func clampTranslation() {
        guard let image = image else { return }
        let scaledImageWidth = image.size.width * scale
        let scaledImageHeight = image.size.height * scale
        let maxTranslationX = max(0, (scaledImageWidth - bounds.width) / 2.0)
        let maxTranslationY = max(0, (scaledImageHeight - bounds.height) / 2.0)
        translation.x = max(-maxTranslationX, min(maxTranslationX, translation.x))
        translation.y = max(-maxTranslationY, min(maxTranslationY, translation.y))
    }
}
