import Foundation
import CoreGraphics
import Metal

class FastCurveExtractor {
    struct Params {
        var foregroundColor: CGColor
        var hueTolerance: CGFloat
        var satTolerance: CGFloat
        var valTolerance: CGFloat
        var deltaX: Int
        var deltaY: Int
        var minPointsPerBin: Int
        var mergeRadius: Int
    }
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let colorPipeline: MTLComputePipelineState?
    private let peakPipeline: MTLComputePipelineState?
    init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        if let d = device {
            let library = try? d.makeDefaultLibrary()
            if let f0 = library?.makeFunction(name: "colorMask") {
                colorPipeline = try? d.makeComputePipelineState(function: f0)
            } else {
                colorPipeline = nil
            }
            if let f1 = library?.makeFunction(name: "columnPeak") {
                peakPipeline = try? d.makeComputePipelineState(function: f1)
            } else {
                peakPipeline = nil
            }
        } else {
            colorPipeline = nil
            peakPipeline = nil
        }
    }
    func extractCurve(from image: CGImage, imageSize: CGSize, axes: AffineCoordinateSystem, seedPixel: CGPoint?, params: Params, regionMask: BrushMask? = nil) -> [(pixel: CGPoint, data: CGPoint)] {
        guard let device = device, let queue = queue, let colorPS = colorPipeline, let peakPS = peakPipeline else {
            let fallback = CurveExtractor()
            fallback.foregroundColor = params.foregroundColor
            fallback.useColor = true
            fallback.deltaX = params.deltaX
            fallback.deltaY = params.deltaY
            fallback.hueTolerance = params.hueTolerance
            fallback.minPointsPerBin = params.minPointsPerBin
            fallback.mergeRadius = params.mergeRadius
            fallback.satTolerance = params.satTolerance
            fallback.valTolerance = params.valTolerance
            return fallback.extractCurve(from: image, imageSize: imageSize, axes: axes, seedPixel: seedPixel)
        }
        let width = image.width
        let height = image.height
        let srcDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        srcDesc.usage = [.shaderRead]
        let maskDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        maskDesc.usage = [.shaderRead, .shaderWrite]
        guard let srcTex = device.makeTexture(descriptor: srcDesc), let maskTex = device.makeTexture(descriptor: maskDesc) else { return [] }
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return [] }
        let bytesPerRow = image.bytesPerRow
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1))
        srcTex.replace(region: region, mipmapLevel: 0, withBytes: ptr, bytesPerRow: bytesPerRow)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let tgt = params.foregroundColor.converted(to: srgb, intent: .perceptual, options: nil) ?? params.foregroundColor
        let tc = tgt.components ?? [1,0,0,1]
        let hsv = rgbToHSV(CGFloat(tc[0]), CGFloat(tc[1]), CGFloat(tc[2]))
        let dynMinSat = max(0.05, hsv.s - params.satTolerance * 2.0)
        var uniforms = ColorUniforms(h: Float(hsv.h), s: Float(hsv.s), v: Float(hsv.v), ht: Float(params.hueTolerance), st: Float(params.satTolerance), vt: Float(params.valTolerance), minSat: Float(dynMinSat), whiteThr: 0.95)
        guard let cmd = queue.makeCommandBuffer() else { return [] }
        if let enc = cmd.makeComputeCommandEncoder() {
            enc.setComputePipelineState(colorPS)
            enc.setTexture(srcTex, index: 0)
            enc.setTexture(maskTex, index: 1)
            enc.setBytes(&uniforms, length: MemoryLayout<ColorUniforms>.stride, index: 0)
            let w = colorPS.threadExecutionWidth
            let hts = MTLSize(width: w, height: 1, depth: 1)
            let gts = MTLSize(width: width, height: height, depth: 1)
            enc.dispatchThreads(gts, threadsPerThreadgroup: hts)
            enc.endEncoding()
        }
        let outBuf = device.makeBuffer(length: MemoryLayout<Int32>.stride * 2 * width, options: [])
        if let enc2 = cmd.makeComputeCommandEncoder() {
            enc2.setComputePipelineState(peakPS)
            enc2.setTexture(maskTex, index: 0)
            enc2.setBuffer(outBuf, offset: 0, index: 0)
            let w = peakPS.threadExecutionWidth
            let hts = MTLSize(width: w, height: 1, depth: 1)
            let gts = MTLSize(width: width, height: 1, depth: 1)
            enc2.dispatchThreads(gts, threadsPerThreadgroup: hts)
            enc2.endEncoding()
        }
        cmd.commit()
        cmd.waitUntilCompleted()
        var keepMask: [UInt8]? = nil
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let regionAll = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1))
        maskTex.getBytes(&bytes, bytesPerRow: width * 4, from: regionAll, mipmapLevel: 0)
        if let rm = regionMask, rm.width == width && rm.height == height {
            var masked = bytes
            var anyOn = false
            var i = 0
            while i < width * height {
                if rm.bytes[i] == 0 {
                    masked[i*4] = 0
                } else if masked[i*4] > 0 {
                    anyOn = true
                }
                i += 1
            }
            if anyOn { bytes = masked }
        }
        func bfsComponent(startX: Int, startY: Int) -> [UInt8] {
            var visited = [UInt8](repeating: 0, count: width * height)
            var queue: [(Int, Int)] = [(startX, startY)]
            visited[startY * width + startX] = 1
            var head = 0
            let dirs = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]
            while head < queue.count {
                let (x0,y0) = queue[head]
                head += 1
                for (dx,dy) in dirs {
                    let xx = x0 + dx
                    let yy = y0 + dy
                    if xx >= 0 && yy >= 0 && xx < width && yy < height {
                        let idx = yy * width + xx
                        let idxR = (yy * width + xx) * 4
                        if visited[idx] == 0 && bytes[idxR] > 0 {
                            visited[idx] = 1
                            queue.append((xx,yy))
                        }
                    }
                }
            }
            return visited
        }
        if let seed = seedPixel {
            var seedX = Int(round(Double(width) * Double(seed.x) / Double(imageSize.width)))
            let syImage = Int(round(Double(height) * Double(seed.y) / Double(imageSize.height)))
            var seedY = max(0, min(height - 1, (height - 1) - syImage))
            let idxR = (seedY * width + seedX) * 4
            if seedX >= 0 && seedX < width && seedY >= 0 && seedY < height && bytes[idxR] > 0 {
                keepMask = bfsComponent(startX: seedX, startY: seedY)
            }
        } else {
            var bestMask: [UInt8]? = nil
            var bestScore = -Double.infinity
            let centerX = width / 2
            let centerY = height / 2
            var radius = min(width, height) / 10
            if radius < 10 { radius = 10 }
            var found = false
            for r in stride(from: 0, to: radius, by: 2) {
                let sx = centerX + r
                let sy = centerY
                let idxR = (sy * width + sx) * 4
                if idxR >= 0 && idxR < bytes.count && bytes[idxR] > 0 { found = true; break }
            }
            if !found {
                for y in stride(from: centerY - radius, through: centerY + radius, by: 2) {
                    for x in stride(from: centerX - radius, through: centerX + radius, by: 2) {
                        if x <= 0 || y <= 0 || x >= width || y >= height { continue }
                        let idxR = (y * width + x) * 4
                        if bytes[idxR] > 0 {
                            let mask = bfsComponent(startX: x, startY: y)
                            var minx = width, miny = height, maxx = 0, maxy = 0, count = 0
                            for yy in 0..<height {
                                for xx in 0..<width {
                                    if mask[yy * width + xx] != 0 {
                                        count += 1
                                        if xx < minx { minx = xx }
                                        if xx > maxx { maxx = xx }
                                        if yy < miny { miny = yy }
                                        if yy > maxy { maxy = yy }
                                    }
                                }
                            }
                            let touchesEdge = (minx <= 2 || miny <= 2 || maxx >= width - 3 || maxy >= height - 3)
                            let cx = (minx + maxx) / 2
                            let cy = (miny + maxy) / 2
                            let distCenter = hypot(Double(cx - centerX), Double(cy - centerY))
                            let score = Double(count) - (touchesEdge ? 1e6 : 0) - distCenter
                            if score > bestScore {
                                bestScore = score
                                bestMask = mask
                            }
                        }
                    }
                    if bestMask != nil { break }
                }
            }
            keepMask = bestMask
        }
        guard let raw = outBuf?.contents() else { return [] }
        let cols = raw.bindMemory(to: Int32.self, capacity: width * 2)
        let scaleX = Double(imageSize.width) / Double(width)
        let scaleY = Double(imageSize.height) / Double(height)
        var results: [(pixel: CGPoint, data: CGPoint)] = []
        var lastX = -params.deltaX
        var x = 0
        let marginX = max(2, Int(Double(width) * 0.02))
        let marginY = max(2, Int(Double(height) * 0.02))
        while x < width {
            if x < marginX || x > width - marginX { x += 1; continue }
            let yTop = cols[x * 2 + 1]
            if yTop >= 0 {
                if x - lastX >= params.deltaX {
                    var ySel = Int(yTop)
                    if let keep = keepMask {
                        let idx = ySel * width + x
                        if keep[idx] == 0 { x += 1; continue }
                    }
                    if let rm = regionMask, rm.width == width && rm.height == height {
                        var found = false
                        var yy = max(ySel, Int(marginY))
                        while yy < min(height - Int(marginY), height) {
                            let idxR = (yy * width + x) * 4
                            if bytes[idxR] > 0 && rm.bytes[yy * width + x] != 0 { ySel = yy; found = true; break }
                            yy += 1
                        }
                        if !found { x += 1; continue }
                    }
                    if ySel < Int(marginY) || ySel > (height - Int(marginY)) { x += 1; continue }
                    let vx = Double(x) * scaleX
                    let vy = Double((height - 1) - ySel) * scaleY
                    let p = CGPoint(x: vx, y: vy)
                    if let d = axes.pixelToData(p) { results.append((pixel: p, data: d)) }
                    lastX = x
                }
            }
            x += 1
        }
        var merged: [(pixel: CGPoint, data: CGPoint)] = []
        for cand in results {
            var dup = false
            for exist in merged {
                if abs(cand.pixel.x - exist.pixel.x) <= CGFloat(params.mergeRadius) && abs(cand.pixel.y - exist.pixel.y) <= CGFloat(params.mergeRadius) { dup = true; break }
            }
            if !dup { merged.append(cand) }
        }
        return merged
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

struct ColorUniforms {
    var h: Float
    var s: Float
    var v: Float
    var ht: Float
    var st: Float
    var vt: Float
    var minSat: Float
    var whiteThr: Float
}
