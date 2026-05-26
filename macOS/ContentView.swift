import SwiftUI
import AppKit
import Foundation
import StoreKit
import UniformTypeIdentifiers

enum FlowStep: Int, CaseIterable {
    case loadImage = 0
    case calibrate
    case extractData
}

enum CalibTarget: Int, CaseIterable {
    case x1 = 0
    case x2
    case y1
    case y2
}

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var selectedTab = 0
    @State private var currentPoint: CGPoint?
    @State private var calibTarget: CalibTarget = .x1
    @State private var x1ValueInput = ""
    @State private var x2ValueInput = ""
    @State private var y1ValueInput = ""
    @State private var y2ValueInput = ""
    
    var body: some View {
        HSplitView {
            FlowSidebar(
                appState: appState,
                currentPoint: $currentPoint,
                calibTarget: $calibTarget,
                x1Value: $x1ValueInput,
                x2Value: $x2ValueInput,
                y1Value: $y1ValueInput,
                y2Value: $y2ValueInput,
                undoAction: { undoCalibrationTarget() },
                backAction: { appState.backToLoad() },
                applyAction: { applyCalibrationValuesAndFinish() },
                openImageAction: { loadImage() }
            )
            .frame(width: 300)
            
            VStack(spacing: 0) {
                FlowDetail(
                    appState: appState,
                    currentPoint: $currentPoint,
                    x1Value: $x1ValueInput,
                    x2Value: $x2ValueInput,
                    y1Value: $y1ValueInput,
                    y2Value: $y2ValueInput,
                    openImageAction: { loadImage() },
                    confirmAction: { confirmCalibrationPoint() },
                    applyAction: { applyCalibrationValuesAndFinish() },
                    backAction: { appState.backToLoad() },
                    undoAction: { undoCalibrationTarget() },
                    calibTarget: $calibTarget
                )
            }
            .background(Color.white)
        }
        .sheet(isPresented: Binding(get: { appState.showPaywall }, set: { appState.showPaywall = $0 })) {
            PaywallView(appState: appState)
        }
    }
    
    private func loadImage() {
        if !appState.isUnlocked { appState.showPaywall = true; return }
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp]
        } else {
            panel.allowedFileTypes = ["png", "jpg", "jpeg", "bmp", "gif"]
        }
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            appState.currentImage = image
            appState.statusMessage = "图片已加载: \(url.lastPathComponent)"
            appState.resetCalibration()
            appState.flowStep = .calibrate
        }
    }
    
    
    

    private func confirmCalibrationPoint() {
        guard let point = currentPoint else { return }
        if appState.coordinateSystem == nil {
            appState.coordinateSystem = AffineCoordinateSystem()
        }
        switch calibTarget {
        case .x1:
            appState.coordinateSystem?.addXAxisPoint(pixel: point, value: 0)
            calibTarget = .x2
        case .x2:
            appState.coordinateSystem?.addXAxisPoint(pixel: point, value: 0)
            calibTarget = .y1
        case .y1:
            appState.coordinateSystem?.addYAxisPoint(pixel: point, value: 0)
            calibTarget = .y2
        case .y2:
            appState.coordinateSystem?.addYAxisPoint(pixel: point, value: 0)
        }
        appState.objectWillChange.send()
        currentPoint = nil
        let hasFour = (appState.coordinateSystem?.xAxisPointsCount ?? 0) >= 2 && (appState.coordinateSystem?.yAxisPointsCount ?? 0) >= 2
        appState.statusMessage = hasFour ? "已选择四个校准点，请统一输入数值" : "已添加校准点"
    }

    private func undoCalibrationTarget() {
        guard let cs = appState.coordinateSystem else { return }
        cs.removeLastPoint()
        
        // Update calibration target based on current state
        let xCount = cs.xAxisPointsCount
        let yCount = cs.yAxisPointsCount
        
        if yCount >= 2 {
            calibTarget = .y2
        } else if yCount >= 1 {
            calibTarget = .y1
        } else if xCount >= 2 {
            calibTarget = .x2
        } else {
            calibTarget = .x1
        }
        
        appState.isCalibrated = cs.isCalibrationValid
    }
}

    class AppState: ObservableObject {
        @Published var currentImage: NSImage?
        @Published var coordinateSystem: AffineCoordinateSystem?
        @Published var extractedData: [DataPoint] = []
        @Published var statusMessage = "请上传图片"
        @Published var isCalibrated = false
        @Published var flowStep: FlowStep = .loadImage
        @Published var extractionMode: Int = 0
        @Published var foregroundColor: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        @Published var autoExtractionResults: [DataPoint] = []
        @Published var sampleDeltaX: Int = 20
        @Published var sampleDeltaY: Int = 20
        @Published var hueTolerance: CGFloat = 0.2
        @Published var minNeighbors: Int = 2
        @Published var useConnectedComponent: Bool = true
        @Published var minPointsPerBin: Int = 4
        @Published var mergeRadius: Int = 2
        @Published var isDeleteMode: Bool = false
        @Published var seedPixelForAuto: CGPoint?
        @Published var currentSaveURL: URL?
        @Published var hasSavedToTemp: Bool = false
        @Published var hasExportedCSV: Bool = false
        @Published var isBrushMode: Bool = false
        @Published var brushRadius: Int = 20
        @Published var brushMask: BrushMask?
        @Published var overlayResetNonce: Int = 0
        @Published var isPremium: Bool = false
        @Published var trialEndsAt: Date?
        @Published var trialDaysLeft: Int = 0
        @Published var showPaywall: Bool = false
        var premiumProductID: String = "com.getfigdata.premium"
        var pointsWindow: NSWindow?
    
    func resetCalibration() {
        coordinateSystem = AffineCoordinateSystem()
        extractedData = []
        isCalibrated = false
        flowStep = .loadImage
        autoExtractionResults = []
    }

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppWillTerminate), name: NSApplication.willTerminateNotification, object: nil)
        let ud = UserDefaults.standard
        if ud.object(forKey: "gfd_trial_end_ts") == nil {
            let end = Date().addingTimeInterval(3 * 24 * 3600)
            ud.set(end.timeIntervalSince1970, forKey: "gfd_trial_end_ts")
        }
        let ts = ud.double(forKey: "gfd_trial_end_ts")
        trialEndsAt = Date(timeIntervalSince1970: ts)
        updateTrialDaysLeft()
        if #available(macOS 12.0, *) {
            Task { await refreshEntitlements() }
        }
    }
    @objc private func handleAppWillTerminate() {
        if !hasExportedCSV, hasSavedToTemp, let tmp = currentSaveURL {
            let alert = NSAlert()
            alert.messageText = "尚未导出CSV"
            alert.informativeText = "是否导出临时保存的数据为CSV？"
            alert.addButton(withTitle: "导出")
            alert.addButton(withTitle: "取消")
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "extracted_data.csv"
                if panel.runModal() == .OK, let url = panel.url {
                    do { try FileManager.default.copyItem(at: tmp, to: url) } catch {}
                }
            }
        }
    }
    
    func backToLoad() {
        flowStep = .loadImage
    }
    
    func clearCalibration() {
        coordinateSystem = AffineCoordinateSystem()
        extractedData = []
        isCalibrated = false
        flowStep = .calibrate
        statusMessage = "已清除校准，请重新拾取四个校准点"
        autoExtractionResults = []
    }

    var isUnlocked: Bool {
        if isPremium { return true }
        return trialDaysLeft > 0
    }

    func updateTrialDaysLeft() {
        guard let end = trialEndsAt else { trialDaysLeft = 0; return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 { trialDaysLeft = 0; return }
        let days = Int(ceil(remaining / (24 * 3600)))
        trialDaysLeft = max(0, days)
    }

    @MainActor func refreshEntitlements() async {
        guard #available(macOS 12.0, *) else { return }
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == premiumProductID {
                isPremium = true
            }
        }
    }

    @MainActor func purchasePremium() async {
        guard #available(macOS 12.0, *) else { return }
        do {
            let products = try await Product.products(for: [premiumProductID])
            guard let product = products.first else { return }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let t) = verification, t.productID == premiumProductID { isPremium = true; showPaywall = false }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {}
    }

    @MainActor func restorePurchases() async {
        guard #available(macOS 12.0, *) else { return }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {}
    }

    
        func openPointsWindow() {
            if let win = pointsWindow {
                win.makeKeyAndOrderFront(nil)
                return
            }
            let hosting = NSHostingController(rootView: DataPointsViewer(appState: self))
            let window = NSWindow(contentViewController: hosting)
            window.title = "数据点查看"
            window.setContentSize(NSSize(width: 420, height: 520))
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            pointsWindow = window
        }
        
    
    func performAutoExtraction() {
        if !isUnlocked { statusMessage = "试用已结束，请购买解锁"; showPaywall = true; return }
        guard let image = currentImage, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            statusMessage = "请先加载图片"
            return
        }
        guard let cs = coordinateSystem, cs.isCalibrationValid else {
            statusMessage = "请先完成坐标轴标定"
            return
        }
        let fast = FastCurveExtractor()
        let params = FastCurveExtractor.Params(
            foregroundColor: foregroundColor,
            hueTolerance: hueTolerance,
            satTolerance: 0.1,
            valTolerance: 0.1,
            deltaX: max(1, sampleDeltaX),
            deltaY: max(1, sampleDeltaY),
            minPointsPerBin: max(1, minPointsPerBin),
            mergeRadius: max(0, mergeRadius)
        )
        let pts = fast.extractCurve(from: cgImage, imageSize: image.size, axes: cs, seedPixel: seedPixelForAuto, params: params, regionMask: (isBrushMode ? brushMask : nil))
        var newData: [DataPoint] = []
        newData.reserveCapacity(pts.count)
        for p in pts {
            let px = Double(p.pixel.x)
            let py = Double(p.pixel.y)
            let dx = Double(p.data.x)
            let dy = Double(p.data.y)
            newData.append(DataPoint(pixelX: px, pixelY: py, dataX: dx, dataY: dy, isManual: false))
        }
        autoExtractionResults = newData
        extractedData.append(contentsOf: newData)
        extractedData.sort { $0.dataX < $1.dataX }
        
        statusMessage = "自动提取完成，新增 \(newData.count) 个数据点"
    }

    func deleteNearestPoint(at pixel: CGPoint, radius: CGFloat = 8) {
        var bestIdx: Int = -1
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (idx, dp) in extractedData.enumerated() {
            let dx = CGFloat(dp.pixelX) - pixel.x
            let dy = CGFloat(dp.pixelY) - pixel.y
            let d = sqrt(dx*dx + dy*dy)
            if d < bestDist {
                bestDist = d
                bestIdx = idx
            }
        }
        if bestIdx >= 0 && bestDist <= radius {
            extractedData.remove(at: bestIdx)
            statusMessage = "已删除一个数据点"
        } else {
            statusMessage = "未找到可删除的数据点"
        }
    }
}

struct FlowSidebar: View {
    @ObservedObject var appState: AppState
    @Binding var currentPoint: CGPoint?
    @Binding var calibTarget: CalibTarget
    @Binding var x1Value: String
    @Binding var x2Value: String
    @Binding var y1Value: String
    @Binding var y2Value: String
    let undoAction: () -> Void
    let backAction: () -> Void
    let applyAction: () -> Void
    let openImageAction: () -> Void
    @State private var hoveringIndex: Int? = nil
    
    private func title(for step: FlowStep) -> String {
        switch step {
        case .loadImage: return "导入图片"
        case .calibrate: return "坐标校准"
        case .extractData: return "提取数据"
        }
    }
    private func icon(for step: FlowStep) -> String {
        switch step {
        case .loadImage: return "photo.on.rectangle"
        case .calibrate: return "scope"
        case .extractData: return "chart.xyaxis.line"
        }
    }
    
    private var targetLabel: String {
        switch calibTarget {
        case .x1: return "X1"
        case .x2: return "X2"
        case .y1: return "Y1"
        case .y2: return "Y2"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    if appState.isPremium {
                        HStack { Image(systemName: "checkmark.seal.fill"); Text("已解锁专业版") }
                            .foregroundColor(Color(NSColor.systemGreen))
                    } else if appState.trialDaysLeft > 0 {
                        HStack { Image(systemName: "clock"); Text("试用剩余 \(appState.trialDaysLeft) 天") }
                            .foregroundColor(.secondary)
                        HStack {
                            Button("购买解锁") { appState.showPaywall = true }
                            Button("恢复购买") { Task { await appState.restorePurchases() } }
                        }
                    } else {
                        HStack { Image(systemName: "lock"); Text("试用已结束") }
                            .foregroundColor(Color(NSColor.systemRed))
                        HStack {
                            Button("购买解锁") { appState.showPaywall = true }
                            Button("恢复购买") { Task { await appState.restorePurchases() } }
                        }
                    }
                }
            }
            ForEach(Array(FlowStep.allCases.enumerated()), id: \.offset) { index, step in
                let isActive = index == appState.flowStep.rawValue
                HStack(spacing: 10) {
                    Image(systemName: icon(for: step))
                        .foregroundColor(isActive ? Color(NSColor.systemBlue) : .secondary)
                    Text(title(for: step))
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundColor(isActive ? Color(NSColor.controlTextColor) : .secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    isActive
                    ? Color(NSColor.systemBlue).opacity(0.10)
                    : (hoveringIndex == index ? Color(NSColor.systemGray).opacity(0.10) : Color.clear)
                )
                .cornerRadius(10)
                .contentShape(Rectangle())
                .onHover { inside in
                    hoveringIndex = inside ? index : (hoveringIndex == index ? nil : hoveringIndex)
                }
                .animation(.easeInOut(duration: 0.15), value: hoveringIndex)
                .onTapGesture {
                    if index <= appState.flowStep.rawValue {
                        if let s = FlowStep(rawValue: index) {
                            appState.flowStep = s
                        }
                    }
                }
            }
            Divider()
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            if appState.flowStep == .calibrate {
                sectionCard {
                    VStack(alignment: .center, spacing: 8) {
                        let xCount = appState.coordinateSystem?.xAxisPointsCount ?? 0
                        let yCount = appState.coordinateSystem?.yAxisPointsCount ?? 0
                        if xCount >= 2 && yCount >= 2 {
                            Text("标记完成，请输入校准值！")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(NSColor.systemGreen))
                        } else {
                            Text("当前需要拾取: \(targetLabel)")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(NSColor.systemRed))
                        }
                        if let p = currentPoint {
                            Text("当前像素: (\(Int(p.x)), \(Int(p.y)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("X轴点: \(xCount)/2  ·  Y轴点: \(yCount)/2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Button("清除坐标校准") {
                                appState.clearCalibration()
                                calibTarget = .x1
                                currentPoint = nil
                                x1Value = ""
                                x2Value = ""
                                y1Value = ""
                                y2Value = ""
                            }
                        }
                    }
                }
                sectionCard {
                    VStack(spacing: 12) {
                        labeledField(title: "X1值", text: $x1Value)
                        labeledField(title: "X2值", text: $x2Value)
                        labeledField(title: "Y1值", text: $y1Value)
                        labeledField(title: "Y2值", text: $y2Value)
                        Toggle("X轴对数坐标", isOn: Binding(get: {
                            appState.coordinateSystem?.isLogX ?? false
                        }, set: { newVal in
                            appState.coordinateSystem?.isLogX = newVal
                            appState.objectWillChange.send()
                        }))
                        Toggle("Y轴对数坐标", isOn: Binding(get: {
                            appState.coordinateSystem?.isLogY ?? false
                        }, set: { newVal in
                            appState.coordinateSystem?.isLogY = newVal
                            appState.objectWillChange.send()
                        }))
                HStack {
                    Spacer()
                    Button("应用并完成校准") { applyAction() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canApplyCalibration)
                }
            }
        }
            } else if appState.flowStep == .extractData {
                sectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ColorPicker("目标线条颜色", selection: Binding(get: {
                                Color(cgColor: appState.foregroundColor)
                            }, set: { newColor in
                                if let cg = newColor.cgColor { appState.foregroundColor = cg }
                            }))
                            Button("吸色") { NSColorSampler().show { sampled in if let color = sampled { appState.foregroundColor = color.cgColor } } }
                        }
                        HStack(spacing: 8) {
                            Text("色相容忍度")
                            Slider(value: Binding(get: { Double(appState.hueTolerance) }, set: { appState.hueTolerance = CGFloat($0) }), in: 0.0...0.5)
                            Text(String(format: "%.2f", Double(appState.hueTolerance)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        HStack(spacing: 8) {
                            Text("刷子大小")
                            Slider(value: Binding(get: { Double(appState.brushRadius) }, set: { appState.brushRadius = max(4, min(64, Int($0))) }), in: 4...64)
                            Text("\(appState.brushRadius) px")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        HStack {
                            Spacer()
                            Button(appState.isBrushMode ? "退出刷子" : "启动刷子") {
                                appState.isBrushMode.toggle()
                            }
                            Spacer()
                            Button("隐藏颜色") {
                                appState.overlayResetNonce &+= 1
                            }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            Text("采样密度")
                            Stepper("ΔX: \(appState.sampleDeltaX) px", value: Binding(get: { appState.sampleDeltaX }, set: { appState.sampleDeltaX = max(1, min(64, $0)) }), in: 1...64)
                            Stepper("ΔY: \(appState.sampleDeltaY) px", value: Binding(get: { appState.sampleDeltaY }, set: { appState.sampleDeltaY = max(1, min(64, $0)) }), in: 1...64)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        HStack {
                            Spacer()
                            Button(appState.isDeleteMode ? "退出删除" : "删除点") {
                                appState.isDeleteMode.toggle()
                                appState.statusMessage = appState.isDeleteMode ? "删除模式已开启" : "删除模式已关闭"
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button("手动提取") {
                                appState.statusMessage = "点击图像添加数据点"
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button("自动提取") {
                                appState.performAutoExtraction()
                            }
                            .buttonStyle(.borderedProminent)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("刷子使用：涂抹目标曲线范围 → 隐藏涂抹 → 吸色 → 自动提取（仅在涂抹范围内） → 退出刷子恢复正常。仅在存在干扰时使用（如坐标轴/网格线与目标同色），避免误提取。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("采样密度：步长越小点越密，越大越稀疏；建议与曲线复杂度匹配。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("色相容忍度：彩色曲线用于扩大色相匹配范围。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("建议优先使用自动提取；对于不合适的数据点可删除并用手动补充。无法识别的曲线可通过刷子功能小范围提取。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                sectionCard {
                    VStack(spacing: 12) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            Button(action: { appState.openPointsWindow() }) {
                                Label("查看数据", systemImage: "doc.text.magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.extractedData.isEmpty)
                            Button(action: {
                                appState.extractedData.removeAll()
                                appState.autoExtractionResults.removeAll()
                                appState.seedPixelForAuto = nil
                                appState.brushMask = nil
                                appState.overlayResetNonce &+= 1
                                appState.statusMessage = "已清除面板数据"
                            }) {
                                Label("清除面板", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(appState.extractedData.isEmpty)
                            
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("查看数据：查看当前提取到的数据，请尽快复制保存。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("清除面板：清除当前页面标记与数据")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func labeledField(title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).frame(width: 50, alignment: .trailing)
            TextField("", text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    @ViewBuilder private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading) {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
    }

    private var hasAnyCalibrationPoint: Bool {
        let xCount = appState.coordinateSystem?.xAxisPointsCount ?? 0
        let yCount = appState.coordinateSystem?.yAxisPointsCount ?? 0
        return xCount > 0 || yCount > 0
    }

    private var canApplyCalibration: Bool {
        let xCount = appState.coordinateSystem?.xAxisPointsCount ?? 0
        let yCount = appState.coordinateSystem?.yAxisPointsCount ?? 0
        guard xCount >= 2 && yCount >= 2 else { return false }
        guard let x1 = Double(x1Value), let x2 = Double(x2Value), let y1 = Double(y1Value), let y2 = Double(y2Value) else { return false }
        let isLogX = appState.coordinateSystem?.isLogX ?? false
        let isLogY = appState.coordinateSystem?.isLogY ?? false
        if isLogX && (x1 <= 0 || x2 <= 0) { return false }
        if isLogY && (y1 <= 0 || y2 <= 0) { return false }
        return true
    }

    

    


}

struct FlowDetail: View {
    @ObservedObject var appState: AppState
    @Binding var currentPoint: CGPoint?
    @Binding var x1Value: String
    @Binding var x2Value: String
    @Binding var y1Value: String
    @Binding var y2Value: String
    let openImageAction: () -> Void
    
    let confirmAction: () -> Void
    let applyAction: () -> Void
    let backAction: () -> Void
    let undoAction: () -> Void
    @Binding var calibTarget: CalibTarget
    
    private var axisLabel: String { "" }
    
    var body: some View {
        switch appState.flowStep {
        case .loadImage:
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Button("打开图片") { openImageAction() }
                }
                .padding(24)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .calibrate:
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                VStack {
                    if let image = appState.currentImage, let cs = appState.coordinateSystem {
                        CalibrationImageView(
                            image: image,
                            coordinateSystem: cs,
                            onPointSelected: { p in
                                currentPoint = p
                                confirmAction()
                            }
                        )
                    } else {
                        Text("请先打开图片")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .extractData:
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                VStack(alignment: .leading, spacing: 8) {
                    DataExtractionView(appState: appState)
                }
                .padding(12)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var targetLabel: String {
        switch calibTarget {
        case .x1: return "X1"
        case .x2: return "X2"
        case .y1: return "Y1"
        case .y2: return "Y2"
        }
    }
    private var hasAnyCalibrationPoint: Bool {
        let xCount = appState.coordinateSystem?.xAxisPointsCount ?? 0
        let yCount = appState.coordinateSystem?.yAxisPointsCount ?? 0
        return xCount > 0 || yCount > 0
    }

    
}

extension ContentView {
    private func applyCalibrationValuesAndFinish() {
        guard let cs = appState.coordinateSystem else {
            appState.statusMessage = "请先拾取四个校准点"
            return
        }
        let xCount = cs.xAxisPointsCount
        let yCount = cs.yAxisPointsCount
        guard xCount >= 2 && yCount >= 2 else {
            appState.statusMessage = "请先拾取四个校准点"
            return
        }
        guard let x1 = Double(x1ValueInput), let x2 = Double(x2ValueInput), let y1 = Double(y1ValueInput), let y2 = Double(y2ValueInput) else {
            appState.statusMessage = "请输入有效数值"
            return
        }
        let isLogX = cs.isLogX
        let isLogY = cs.isLogY
        if isLogX && (x1 <= 0 || x2 <= 0) {
            appState.statusMessage = "对数X轴需要正数"
            return
        }
        if isLogY && (y1 <= 0 || y2 <= 0) {
            appState.statusMessage = "对数Y轴需要正数"
            return
        }
        cs.updateXAxisPointValue(at: 0, value: x1)
        cs.updateXAxisPointValue(at: 1, value: x2)
        cs.updateYAxisPointValue(at: 0, value: y1)
        cs.updateYAxisPointValue(at: 1, value: y2)
        appState.isCalibrated = cs.isCalibrationValid
        if appState.isCalibrated {
            appState.statusMessage = "校准完成"
            appState.flowStep = .extractData
        } else {
            appState.statusMessage = "校准失败，请检查输入"
        }
    }
}

struct PaywallView: View {
    @ObservedObject var appState: AppState
    @State private var loading = false
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "lock")
                Text("解锁专业版")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            Text(appState.trialDaysLeft > 0 ? "试用剩余 \(appState.trialDaysLeft) 天" : "试用已结束")
                .foregroundColor(.secondary)
            Text("购买后可无限使用所有功能")
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("购买解锁") {
                    Task {
                        loading = true
                        await appState.purchasePremium()
                        loading = false
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("恢复购买") {
                    Task { await appState.restorePurchases() }
                }
                .buttonStyle(.bordered)
            }
            if loading { ProgressView() }
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 260)
        .overlay(alignment: .topTrailing) {
            Button(action: { appState.showPaywall = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(8)
        }
    }
}
