import SwiftUI
import AppKit
import QuartzCore

struct CalibrationView: View {
    @ObservedObject var appState: AppState
    @State private var xValue = ""
    @State private var yValue = ""
    @State private var selectedAxis = 0
    @State private var currentPoint: CGPoint?
    
    var body: some View {
        HSplitView {
            // Image view with calibration points
            VStack {
                if let image = appState.currentImage, let cs = appState.coordinateSystem {
                    CalibrationImageView(
                        image: image,
                        coordinateSystem: cs,
                        onPointSelected: { point in
                            currentPoint = point
                        }
                    )
                } else {
                    Text("请先加载图片")
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 400)
            
            // Calibration controls
            VStack(alignment: .leading, spacing: 16) {
                Text("坐标校准")
                    .font(.headline)
                
                Text("步骤：")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 在X轴上选择至少2个点并输入对应数值")
                    Text("2. 在Y轴上选择至少2个点并输入对应数值")
                    Text("3. 系统会自动计算像素到数据的映射关系")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Divider()
                
                if let point = currentPoint {
                    Text("当前点: (\(Int(point.x)), \(Int(point.y)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Picker("坐标轴", selection: $selectedAxis) {
                    Text("X轴").tag(0)
                    Text("Y轴").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                HStack {
                    Text(selectedAxis == 0 ? "X值:" : "Y值:")
                        .frame(width: 40, alignment: .trailing)
                    TextField("输入数值", text: selectedAxis == 0 ? $xValue : $yValue)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Button("添加校准点") {
                    addCalibrationPoint()
                }
                .disabled(currentPoint == nil || (selectedAxis == 0 ? xValue.isEmpty : yValue.isEmpty))
                
                Divider()
                
                // Show current calibration points
                VStack(alignment: .leading, spacing: 8) {
                    Text("X轴校准点 (\(appState.coordinateSystem?.xAxisPointsCount ?? 0)/2)")
                        .font(.subheadline)
                    
                    if let xPoints = appState.coordinateSystem?.xAxisCalibrationPoints {
                        ForEach(Array(xPoints.enumerated()), id: \.offset) { index, point in
                            HStack {
                                Text("点 \(index + 1): (\(Int(point.pixel.x)), \(Int(point.pixel.y)))")
                                    .font(.caption)
                                Spacer()
                                Text("值: \(point.value)")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    Text("Y轴校准点 (\(appState.coordinateSystem?.yAxisPointsCount ?? 0)/2)")
                        .font(.subheadline)
                        .padding(.top, 8)
                    
                    if let yPoints = appState.coordinateSystem?.yAxisCalibrationPoints {
                        ForEach(Array(yPoints.enumerated()), id: \.offset) { index, point in
                            HStack {
                                Text("点 \(index + 1): (\(Int(point.pixel.x)), \(Int(point.pixel.y)))")
                                    .font(.caption)
                                Spacer()
                                Text("值: \(point.value)")
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack {
                    Button("清除所有点") {
                        appState.coordinateSystem?.clear()
                        appState.isCalibrated = false
                    }
                    .disabled(appState.coordinateSystem?.xAxisCalibrationPoints.isEmpty ?? true && appState.coordinateSystem?.yAxisCalibrationPoints.isEmpty ?? true)
                    
                    Spacer()
                    
                    Button("完成校准") {
                        appState.isCalibrated = appState.coordinateSystem?.isCalibrationValid ?? false
                    }
                    .disabled(!(appState.coordinateSystem?.isCalibrationValid ?? false))
                }
                
                if appState.isCalibrated {
                    Text("✅ 校准完成")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
    
    private func addCalibrationPoint() {
        guard let point = currentPoint else { return }
        
        // Ensure coordinateSystem exists
        if appState.coordinateSystem == nil {
            appState.coordinateSystem = AffineCoordinateSystem()
        }
        
        if selectedAxis == 0 {
            if let value = Double(xValue) {
                appState.coordinateSystem?.addXAxisPoint(pixel: point, value: value)
                xValue = ""
            }
        } else {
            if let value = Double(yValue) {
                appState.coordinateSystem?.addYAxisPoint(pixel: point, value: value)
                yValue = ""
            }
        }
        
        currentPoint = nil
    }
}

struct CalibrationImageView: NSViewRepresentable {
    let image: NSImage
    var coordinateSystem: AffineCoordinateSystem
    let onPointSelected: (CGPoint) -> Void
    
    func makeNSView(context: Context) -> CalibrationNSView {
        let view = CalibrationNSView()
        view.image = image
        view.coordinateSystem = coordinateSystem
        view.onPointSelected = onPointSelected
        return view
    }
    
    func updateNSView(_ nsView: CalibrationNSView, context: Context) {
        nsView.image = image
        nsView.coordinateSystem = coordinateSystem
        nsView.needsDisplay = true
    }
}

class CalibrationNSView: NSView {
    var image: NSImage?
    var coordinateSystem: AffineCoordinateSystem?
    var onPointSelected: ((CGPoint) -> Void)?
    var hoverPixel: CGPoint?
    var selectedPixel: CGPoint?
    var trackingArea: NSTrackingArea?
    
    private var scale: CGFloat = 1.0
    private var translation = CGPoint.zero
    private var initialPinchDistance: CGFloat = 0
    private lazy var customCursor: NSCursor = {
        let size: CGFloat = 32
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 0, y: size/2))
        ctx.addLine(to: CGPoint(x: size, y: size/2))
        ctx.move(to: CGPoint(x: size/2, y: 0))
        ctx.addLine(to: CGPoint(x: size/2, y: size))
        ctx.strokePath()
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: NSPoint(x: size/2, y: size/2))
    }()
    
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
        
        // Draw calibration points
        context.setFillColor(NSColor.red.cgColor)
        context.setStrokeColor(NSColor.red.cgColor)
        context.setLineWidth(2)
        
        // Draw X axis points and labels
        if let xPoints = coordinateSystem?.xAxisCalibrationPoints {
            for (idx, point) in xPoints.enumerated() {
                let px = drawRect.origin.x + point.pixel.x * scale
                let py = drawRect.origin.y + point.pixel.y * scale
                let rect = CGRect(x: px - 4, y: py - 4, width: 8, height: 8)
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
                let label = "X\(idx + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
                ]
                label.draw(at: CGPoint(x: px + 8, y: py + 8), withAttributes: attrs)
            }
        }
        
        // Draw Y axis points and labels
        if let yPoints = coordinateSystem?.yAxisCalibrationPoints {
            context.setFillColor(NSColor.blue.cgColor)
            context.setStrokeColor(NSColor.blue.cgColor)
            for (idx, point) in yPoints.enumerated() {
                let px = drawRect.origin.x + point.pixel.x * scale
                let py = drawRect.origin.y + point.pixel.y * scale
                let rect = CGRect(x: px - 4, y: py - 4, width: 8, height: 8)
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
                let label = "Y\(idx + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
                ]
                label.draw(at: CGPoint(x: px + 8, y: py + 8), withAttributes: attrs)
            }
        }
        
        if let p = selectedPixel {
            context.setStrokeColor(NSColor.systemRed.cgColor)
            context.setLineWidth(2)
            let px = drawRect.origin.x + p.x * scale
            let py = drawRect.origin.y + p.y * scale
            let s: CGFloat = 32
            context.move(to: CGPoint(x: px - s, y: py))
            context.addLine(to: CGPoint(x: px + s, y: py))
            context.move(to: CGPoint(x: px, y: py - s))
            context.addLine(to: CGPoint(x: px, y: py + s))
            context.strokePath()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let pixelPoint = imagePixelPoint(for: viewPoint) {
            selectedPixel = pixelPoint
            onPointSelected?(pixelPoint)
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        customCursor.set()
    }
    
    override func updateTrackingAreas() {
        if let ta = trackingArea { removeTrackingArea(ta) }
        let options: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    private func imagePixelPoint(for viewPoint: CGPoint) -> CGPoint? {
        guard let image = image else { return nil }
        let drawRect = currentDrawRect(for: image)
        guard drawRect.contains(viewPoint) else { return nil }
        let x = (viewPoint.x - drawRect.origin.x) / scale
        let y = (viewPoint.y - drawRect.origin.y) / scale
        guard x >= 0, y >= 0, x <= image.size.width, y <= image.size.height else { return nil }
        return CGPoint(x: x, y: y)
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
