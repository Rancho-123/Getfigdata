import Foundation
import CoreGraphics

class CurveExtractor {
    var smoothWindow: Int = 7
    var scoreThreshold: CGFloat = 0.5
    var foregroundColor: CGColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    var useColor: Bool = false
    var deltaX: Int = 4
    var deltaY: Int = 2
    var hueTolerance: CGFloat = 0.08
    var minSaturation: CGFloat = 0.5
    var whiteThreshold: CGFloat = 0.95
    var minPointsPerBin: Int = 4
    var mergeRadius: Int = 2
    var satTolerance: CGFloat = 0.1
    var valTolerance: CGFloat = 0.1
    var adaptiveRelaxation: Bool = true
    var minMaskPixels: Int = 20
    var maxHueTolerance: CGFloat = 0.5
    var useConnectedComponent: Bool = true
    var minNeighbors: Int = 2
    var morphKernelSize: Int = 3

    func extractCurve(from image: CGImage, imageSize: CGSize, axes: AffineCoordinateSystem, seedPixel: CGPoint? = nil) -> [(pixel: CGPoint, data: CGPoint)] {
        let width = image.width
        let height = image.height
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return [] }

        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let tgt = foregroundColor.converted(to: srgb, intent: .perceptual, options: nil) ?? foregroundColor
        let tc = tgt.components ?? [1,0,0,1]
        let thsv = rgbToHSV(tc[0], tc[1], tc[2])
        var match: [[Bool]] = Array(repeating: Array(repeating: false, count: height), count: width)
        for x in 0..<width {
            for y in 0..<height {
                let off = (y * width + x) * 4
                let r = CGFloat(ptr[off]) / 255.0
                let g = CGFloat(ptr[off + 1]) / 255.0
                let b = CGFloat(ptr[off + 2]) / 255.0
                if useColor {
                    let phsv = rgbToHSV(r, g, b)
                    let dh = min(abs(phsv.h - thsv.h), 1.0 - abs(phsv.h - thsv.h))
                    let sd = abs(phsv.s - thsv.s)
                    let vd = abs(phsv.v - thsv.v)
                    if phsv.s < minSaturation { continue }
                    if phsv.s < 0.1 && phsv.v > whiteThreshold { continue }
                    if dh > hueTolerance { continue }
                    if sd > satTolerance { continue }
                    if vd > valTolerance { continue }
                    match[x][y] = true
                } else {
                    let maxC = max(r, max(g, b)); let minC = min(r, min(g, b))
                    let s = maxC > 0 ? (maxC - minC) / maxC : 0
                    let v = maxC
                    let score = s * 0.7 + (1.0 - v) * 0.3
                    match[x][y] = score >= scoreThreshold
                }
            }
        }

        var matchedCount = 0
        for x in 0..<width { for y in 0..<height { if match[x][y] { matchedCount += 1 } } }

        var seedX: Int = -1
        var seedY: Int = -1
        if let seed = seedPixel {
            seedX = Int(round(Double(width) * Double(seed.x) / Double(imageSize.width)))
            let syImage = Int(round(Double(height) * Double(seed.y) / Double(imageSize.height)))
            seedY = max(0, min(height - 1, (height - 1) - syImage))
        }

        var needRelax = adaptiveRelaxation && (matchedCount < minMaskPixels || (seedX >= 0 && seedY >= 0 && (seedX >= width || seedY >= height || !match[seedX][seedY])))
        if needRelax {
            var relaxed: [[Bool]] = Array(repeating: Array(repeating: false, count: height), count: width)
            let hTol = min(maxHueTolerance, max(hueTolerance * 1.5, 0.12))
            for x in 0..<width {
                for y in 0..<height {
                    let off = (y * width + x) * 4
                    let r = CGFloat(ptr[off]) / 255.0
                    let g = CGFloat(ptr[off + 1]) / 255.0
                    let b = CGFloat(ptr[off + 2]) / 255.0
                    let phsv = rgbToHSV(r, g, b)
                    let dh = min(abs(phsv.h - thsv.h), 1.0 - abs(phsv.h - thsv.h))
                    if dh <= hTol { relaxed[x][y] = true }
                }
            }
            match = relaxed
        }

        matchedCount = 0
        for x in 0..<width { for y in 0..<height { if match[x][y] { matchedCount += 1 } } }
        if minNeighbors > 0 && matchedCount >= minMaskPixels {
            match = neighborFilter(mask: match, minNeighbors: minNeighbors)
        }

        if morphKernelSize > 1 && matchedCount >= minMaskPixels {
            match = opening(mask: match, kernel: morphKernelSize)
        }

        if useConnectedComponent, let seed = seedPixel {
            if seedX >= 0 && seedY >= 0 && seedX < width && seedY < height {
                match = extractComponent(mask: match, seedX: seedX, seedY: seedY)
            }
        }

        let scaleX = Double(imageSize.width) / Double(width)
        let scaleY = Double(imageSize.height) / Double(height)
        let dx = max(1, Int(round(Double(deltaX) * Double(width) / Double(imageSize.width))))
        let dy = max(1, Int(round(Double(deltaY) * Double(height) / Double(imageSize.height))))

        var candidates: [(pixel: CGPoint, data: CGPoint)] = []

        for y0 in stride(from: 0, to: height, by: dy) {
            let y1 = min(height - 1, y0 + dy - 1)
            for x0 in stride(from: 0, to: width, by: dx) {
                let x1 = min(width - 1, x0 + dx - 1)
                var pts: [(Int, Int)] = []
                for x in x0...x1 { for y in y0...y1 { if match[x][y] { pts.append((x,y)) } } }
                if pts.isEmpty { continue }
                if pts.count < minPointsPerBin {
                    let mid = pts[pts.count/2]
                    let vx = Double(mid.0) * scaleX
                    let vy = (Double(height - 1 - mid.1)) * scaleY
                    let p = CGPoint(x: vx, y: vy)
                    if let d = axes.pixelToData(p) { candidates.append((pixel: p, data: d)) }
                } else {
                    var xs: [Int: [Int]] = [:]
                    for (x,y) in pts { xs[x, default: []].append(y) }
                    var lastX = -dx
                    for x in xs.keys.sorted() {
                        if x - lastX >= dx {
                            let ys = xs[x]!.sorted(); let ymed = ys[ys.count/2]
                            let vx = Double(x) * scaleX
                            let vy = (Double(height - 1 - ymed)) * scaleY
                            let p = CGPoint(x: vx, y: vy)
                            if let d = axes.pixelToData(p) { candidates.append((pixel: p, data: d)) }
                            lastX = x
                        }
                    }
                }
            }
        }

        for x0 in stride(from: 0, to: width, by: dx) {
            let x1 = min(width - 1, x0 + dx - 1)
            for y0 in stride(from: 0, to: height, by: dy) {
                let y1 = min(height - 1, y0 + dy - 1)
                var pts: [(Int, Int)] = []
                for x in x0...x1 { for y in y0...y1 { if match[x][y] { pts.append((x,y)) } } }
                if pts.isEmpty { continue }
                if pts.count < minPointsPerBin {
                    let mid = pts[pts.count/2]
                    let vx = Double(mid.0) * scaleX
                    let vy = (Double(height - 1 - mid.1)) * scaleY
                    let p = CGPoint(x: vx, y: vy)
                    if let d = axes.pixelToData(p) { candidates.append((pixel: p, data: d)) }
                } else {
                    var ys: [Int: [Int]] = [:]
                    for (x,y) in pts { ys[y, default: []].append(x) }
                    var lastYp = -dy
                    for y in ys.keys.sorted() {
                        if y - lastYp >= dy {
                            let xs = ys[y]!.sorted(); let xmed = xs[xs.count/2]
                            let vx = Double(xmed) * scaleX
                            let vy = (Double(height - 1 - y)) * scaleY
                            let p = CGPoint(x: vx, y: vy)
                            if let d = axes.pixelToData(p) { candidates.append((pixel: p, data: d)) }
                            lastYp = y
                        }
                    }
                }
            }
        }

        var results: [(pixel: CGPoint, data: CGPoint)] = []
        for cand in candidates {
            var dup = false
            for exist in results {
                if abs(cand.pixel.x - exist.pixel.x) <= CGFloat(mergeRadius) && abs(cand.pixel.y - exist.pixel.y) <= CGFloat(mergeRadius) { dup = true; break }
            }
            if !dup { results.append(cand) }
        }
        return results
    }

    private func extractComponent(mask: [[Bool]], seedX: Int, seedY: Int) -> [[Bool]] {
        let w = mask.count
        let h = mask[0].count
        if seedX < 0 || seedX >= w || seedY < 0 || seedY >= h || !mask[seedX][seedY] { return mask }
        var visited = Array(repeating: Array(repeating: false, count: h), count: w)
        var keep = Array(repeating: Array(repeating: false, count: h), count: w)
        var queue: [(Int, Int)] = [(seedX, seedY)]
        visited[seedX][seedY] = true
        keep[seedX][seedY] = true
        var head = 0
        let dirs = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]
        while head < queue.count {
            let (x,y) = queue[head]
            head += 1
            for (dx,dy) in dirs {
                let xx = x + dx
                let yy = y + dy
                if xx >= 0 && yy >= 0 && xx < w && yy < h && !visited[xx][yy] && mask[xx][yy] {
                    visited[xx][yy] = true
                    keep[xx][yy] = true
                    queue.append((xx,yy))
                }
            }
        }
        return keep
    }

    private func neighborFilter(mask: [[Bool]], minNeighbors: Int) -> [[Bool]] {
        let w = mask.count
        let h = mask[0].count
        var out = Array(repeating: Array(repeating: false, count: h), count: w)
        for x in 0..<w {
            for y in 0..<h {
                if !mask[x][y] { continue }
                var count = 0
                for dx in -1...1 {
                    for dy in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let xx = x + dx
                        let yy = y + dy
                        if xx >= 0 && yy >= 0 && xx < w && yy < h && mask[xx][yy] { count += 1 }
                    }
                }
                out[x][y] = count >= minNeighbors
            }
        }
        return out
    }

    private func opening(mask: [[Bool]], kernel: Int) -> [[Bool]] {
        let w = mask.count
        let h = mask[0].count
        let r = max(1, kernel) / 2
        var erode: [[Bool]] = Array(repeating: Array(repeating: false, count: h), count: w)
        for x in 0..<w {
            for y in 0..<h {
                var ok = true
                for dx in -r...r {
                    for dy in -r...r {
                        let xx = x + dx
                        let yy = y + dy
                        if xx < 0 || yy < 0 || xx >= w || yy >= h || !mask[xx][yy] { ok = false; break }
                    }
                    if !ok { break }
                }
                erode[x][y] = ok
            }
        }
        var dilate: [[Bool]] = Array(repeating: Array(repeating: false, count: h), count: w)
        for x in 0..<w {
            for y in 0..<h {
                var any = false
                for dx in -r...r {
                    for dy in -r...r {
                        let xx = x + dx
                        let yy = y + dy
                        if xx >= 0 && yy >= 0 && xx < w && yy < h && erode[xx][yy] { any = true; break }
                    }
                    if any { break }
                }
                dilate[x][y] = any
            }
        }
        return dilate
    }

    

    private func rgbToHSV(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let v = maxC
        let s = maxC == 0 ? 0 : (maxC - minC) / maxC
        var h: CGFloat = 0
        let delta = maxC - minC
        if delta == 0 {
            h = 0
        } else if maxC == r {
            h = (g - b) / delta
        } else if maxC == g {
            h = 2 + (b - r) / delta
        } else {
            h = 4 + (r - g) / delta
        }
        h /= 6
        if h < 0 { h += 1 }
        return (h, s, v)
    }
}

