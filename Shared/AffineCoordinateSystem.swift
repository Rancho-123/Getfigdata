import Foundation
import CoreGraphics

class AffineCoordinateSystem {
    private var transformMatrix: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]] // 3x3 identity matrix
    private var isValid = false
    
    // 4个标定点：2个X轴点，2个Y轴点
    var xAxisPoints: [CalibrationPoint] = []
    var yAxisPoints: [CalibrationPoint] = []
    var isLogX: Bool = false { didSet { recalculateTransform() } }
    var isLogY: Bool = false { didSet { recalculateTransform() } }
    
    var isCalibrationValid: Bool {
        return isValid && xAxisPoints.count >= 2 && yAxisPoints.count >= 2
    }
    
    var xAxisPointsCount: Int {
        return xAxisPoints.count
    }
    
    var yAxisPointsCount: Int {
        return yAxisPoints.count
    }
    
    func getXAxisPoint(at index: Int) -> CalibrationPoint? {
        guard index < xAxisPoints.count else { return nil }
        return xAxisPoints[index]
    }
    
    func getYAxisPoint(at index: Int) -> CalibrationPoint? {
        guard index < yAxisPoints.count else { return nil }
        return yAxisPoints[index]
    }
    
    var xAxisCalibrationPoints: [CalibrationPoint] {
        return xAxisPoints
    }
    
    var yAxisCalibrationPoints: [CalibrationPoint] {
        return yAxisPoints
    }
    
    func addXAxisPoint(pixel: CGPoint, value: Double) {
        xAxisPoints.append(CalibrationPoint(pixel: pixel, value: value))
        recalculateTransform()
    }
    
    func addYAxisPoint(pixel: CGPoint, value: Double) {
        yAxisPoints.append(CalibrationPoint(pixel: pixel, value: value))
        recalculateTransform()
    }
    
    func updateXAxisPointValue(at index: Int, value: Double) {
        guard index < xAxisPoints.count else { return }
        xAxisPoints[index] = CalibrationPoint(pixel: xAxisPoints[index].pixel, value: value)
        recalculateTransform()
    }
    
    func updateYAxisPointValue(at index: Int, value: Double) {
        guard index < yAxisPoints.count else { return }
        yAxisPoints[index] = CalibrationPoint(pixel: yAxisPoints[index].pixel, value: value)
        recalculateTransform()
    }
    
    func removeLastPoint() {
        if xAxisPoints.count > yAxisPoints.count {
            if !xAxisPoints.isEmpty {
                xAxisPoints.removeLast()
            }
        } else {
            if !yAxisPoints.isEmpty {
                yAxisPoints.removeLast()
            }
        }
        recalculateTransform()
    }
    func clear() {
        xAxisPoints.removeAll()
        yAxisPoints.removeAll()
        isValid = false
    }
    
    func pixelToData(_ point: CGPoint) -> CGPoint? {
        guard isValid else { return nil }
        
        let x = Double(point.x)
        let y = Double(point.y)
        
        let dataX = transformMatrix[0][0] * x + transformMatrix[0][1] * y + transformMatrix[0][2]
        let dataY = transformMatrix[1][0] * x + transformMatrix[1][1] * y + transformMatrix[1][2]
        let finalX = isLogX ? pow(10.0, dataX) : dataX
        let finalY = isLogY ? pow(10.0, dataY) : dataY
        
        return CGPoint(x: finalX, y: finalY)
    }
    
    func dataToPixel(_ point: CGPoint) -> CGPoint? {
        guard isValid else { return nil }
        
        var x = Double(point.x)
        var y = Double(point.y)
        if isLogX {
            if x <= 0 { return nil }
            x = log10(x)
        }
        if isLogY {
            if y <= 0 { return nil }
            y = log10(y)
        }
        
        // 计算逆变换
        let det = transformMatrix[0][0] * transformMatrix[1][1] - transformMatrix[0][1] * transformMatrix[1][0]
        guard abs(det) > 1e-10 else { return nil }
        
        let invDet = 1.0 / det
        let invMatrix = [
            [transformMatrix[1][1] * invDet, -transformMatrix[0][1] * invDet],
            [-transformMatrix[1][0] * invDet, transformMatrix[0][0] * invDet]
        ]
        
        let px = invMatrix[0][0] * (x - transformMatrix[0][2]) + invMatrix[0][1] * (y - transformMatrix[1][2])
        let py = invMatrix[1][0] * (x - transformMatrix[0][2]) + invMatrix[1][1] * (y - transformMatrix[1][2])
        
        return CGPoint(x: px, y: py)
    }
    
    private func recalculateTransform() {
        guard xAxisPoints.count >= 2 && yAxisPoints.count >= 2 else {
            isValid = false
            return
        }

        // X: 使用像素x与X值（若对数则log10）做线性拟合
        var xs: [Double] = []
        var xv: [Double] = []
        for p in xAxisPoints {
            var v = p.value
            if isLogX {
                if v <= 0 { isValid = false; return }
                v = log10(v)
            }
            xs.append(Double(p.pixel.x))
            xv.append(v)
        }
        let mxbx = linearFit(pixels: xs, values: xv)
        guard let mx = mxbx?.slope, let bx = mxbx?.intercept else { isValid = false; return }

        // Y: 使用像素y与Y值（若对数则log10）做线性拟合
        var ys: [Double] = []
        var yv: [Double] = []
        for p in yAxisPoints {
            var v = p.value
            if isLogY {
                if v <= 0 { isValid = false; return }
                v = log10(v)
            }
            ys.append(Double(p.pixel.y))
            yv.append(v)
        }
        let myby = linearFit(pixels: ys, values: yv)
        guard let my = myby?.slope, let by = myby?.intercept else { isValid = false; return }

        // 将结果写入矩阵，保证pixelToData兼容现有实现
        transformMatrix = [
            [mx, 0, bx],
            [0, my, by],
            [0, 0, 1]
        ]
        isValid = true
    }

    private func linearFit(pixels: [Double], values: [Double]) -> (slope: Double, intercept: Double)? {
        guard pixels.count == values.count, pixels.count >= 2 else { return nil }
        let n = Double(pixels.count)
        var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0
        for i in 0..<pixels.count {
            let x = pixels[i]
            let y = values[i]
            sumX += x
            sumY += y
            sumXX += x * x
            sumXY += x * y
        }
        let denom = n * sumXX - sumX * sumX
        if abs(denom) < 1e-12 { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept)
    }
    
    private func solveLeastSquares(A: [[Double]], b: [Double]) -> [Double]? {
        let m = A.count
        let n = A[0].count
        
        guard m >= n && b.count == m else { return nil }
        
        // 计算 A^T * A 和 A^T * b
        var AtA: [[Double]] = Array(repeating: Array(repeating: 0, count: n), count: n)
        var Atb: [Double] = Array(repeating: 0, count: n)
        
        for i in 0..<n {
            for j in 0..<n {
                for k in 0..<m {
                    AtA[i][j] += A[k][i] * A[k][j]
                }
            }
            for k in 0..<m {
                Atb[i] += A[k][i] * b[k]
            }
        }
        
        // 使用高斯消元法求解 AtA * x = Atb
        return solveGaussian(A: AtA, b: Atb)
    }
    
    private func solveGaussian(A: [[Double]], b: [Double]) -> [Double]? {
        let n = A.count
        var A = A
        var b = b
        
        // 前向消元
        for i in 0..<n {
            // 寻找主元
            var maxRow = i
            for k in i+1..<n {
                if abs(A[k][i]) > abs(A[maxRow][i]) {
                    maxRow = k
                }
            }
            
            // 交换行
            A.swapAt(i, maxRow)
            b.swapAt(i, maxRow)
            
            // 检查奇异性
            if abs(A[i][i]) < 1e-10 {
                return nil
            }
            
            // 消元
            for k in i+1..<n {
                let factor = A[k][i] / A[i][i]
                for j in i..<n {
                    A[k][j] -= factor * A[i][j]
                }
                b[k] -= factor * b[i]
            }
        }
        
        // 回代
        var x = Array(repeating: 0.0, count: n)
        for i in stride(from: n-1, through: 0, by: -1) {
            x[i] = b[i]
            for j in i+1..<n {
                x[i] -= A[i][j] * x[j]
            }
            x[i] /= A[i][i]
        }
        
        return x
    }
}

struct CalibrationPoint {
    let pixel: CGPoint
    let value: Double
}
