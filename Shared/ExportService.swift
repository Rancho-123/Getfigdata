import Foundation
import CoreGraphics

struct ExportService {
    static func exportToCSV(data: [DataPoint], to url: URL) {
        var lines: [String] = []
        for p in data {
            lines.append("\(p.dataX),\(p.dataY)")
        }
        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
        }
    }
    static func exportToJSON(data: [DataPoint], to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        do {
            let d = try encoder.encode(data)
            try d.write(to: url)
        } catch {
        }
    }
    static func colorName(for color: CGColor) -> String {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = color.converted(to: cs, intent: .perceptual, options: nil) ?? color
        let comps: [CGFloat] = c.components ?? [0,0,0,1]
        let r = comps.count > 0 ? comps[0] : 0
        let g = comps.count > 1 ? comps[1] : 0
        let b = comps.count > 2 ? comps[2] : 0
        let maxC = max(r, max(g, b)); let minC = min(r, min(g, b))
        let v = maxC; let s = maxC == 0 ? 0 : (maxC - minC) / maxC
        var h: CGFloat = 0
        let d = maxC - minC
        if d == 0 { h = 0 } else if maxC == r { h = (g - b) / d } else if maxC == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
        h /= 6; if h < 0 { h += 1 }
        if v < 0.08 { return "black" }
        if v > 0.92 && s < 0.1 { return "white" }
        if s < 0.12 { return "gray" }
        if h < 0.03 || h > 0.97 { return "red" }
        if h < 0.10 { return v < 0.7 ? "brown" : "orange" }
        if h < 0.18 { return "yellow" }
        if h < 0.42 { return "green" }
        if h < 0.54 { return "cyan" }
        if h < 0.75 { return "blue" }
        if h < 0.92 { return "magenta" }
        return "red"
    }
    static func saveCSVWithHeader(data: [DataPoint], color: CGColor, to url: URL) {
        var lines: [String] = []
        let name = colorName(for: color)
        lines.append("\(name) X,\(name) Y")
        for p in data {
            lines.append("\(p.dataX),\(p.dataY)")
        }
        let content = lines.joined(separator: "\n")
        do { try content.write(to: url, atomically: true, encoding: .utf8) } catch {}
    }

    static func appendSeriesToCSV(data: [DataPoint], color: CGColor, to url: URL) {
        let fm = FileManager.default
        let name = colorName(for: color)
        if !fm.fileExists(atPath: url.path) {
            saveCSVWithHeader(data: data, color: color, to: url)
            return
        }
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
            saveCSVWithHeader(data: data, color: color, to: url)
            return
        }
        var rows = existing.components(separatedBy: "\n")
        if rows.last == "" { rows.removeLast() }
        var headerCells: [String] = rows.first?
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "\r", with: "") } ?? []
        let existingCols = headerCells.count
        let headerLabelX = "line\(max(1, existingCols/2 + 1)) \(name) X"
        let headerLabelY = "line\(max(1, existingCols/2 + 1)) \(name) Y"
        var out: [String] = []
        let newCount = data.count
        let maxRows = max(max(0, rows.count - 1), newCount)
        headerCells.append(contentsOf: [headerLabelX, headerLabelY])
        out.append(headerCells.joined(separator: ","))
        for i in 0..<maxRows {
            var existingCells: [String]
            if i + 1 < rows.count {
                existingCells = rows[i + 1]
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { String($0).replacingOccurrences(of: "\r", with: "") }
                if existingCells.count < existingCols {
                    existingCells.append(contentsOf: Array(repeating: "", count: existingCols - existingCells.count))
                }
            } else {
                existingCells = Array(repeating: "", count: existingCols)
            }
            let x = i < newCount ? String(data[i].dataX) : ""
            let y = i < newCount ? String(data[i].dataY) : ""
            existingCells.append(contentsOf: [x, y])
            out.append(existingCells.joined(separator: ","))
        }
        let updated = out.joined(separator: "\n") + "\n"
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".bak")
        _ = try? FileManager.default.removeItem(at: backupURL)
        _ = try? FileManager.default.copyItem(at: url, to: backupURL)
        try? updated.write(to: url, atomically: true, encoding: .utf8)
    }
}
