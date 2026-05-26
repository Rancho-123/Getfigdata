import Foundation

struct DataPoint: Identifiable, Codable, Equatable {
    let id = UUID()
    let pixelX: Double
    let pixelY: Double
    let dataX: Double
    let dataY: Double
    let isManual: Bool
    
    init(pixelX: Double, pixelY: Double, dataX: Double, dataY: Double, isManual: Bool = true) {
        self.pixelX = pixelX
        self.pixelY = pixelY
        self.dataX = dataX
        self.dataY = dataY
        self.isManual = isManual
    }
    init(x: Double, y: Double, isManual: Bool = true) {
        self.pixelX = .nan
        self.pixelY = .nan
        self.dataX = x
        self.dataY = y
        self.isManual = isManual
    }
}
