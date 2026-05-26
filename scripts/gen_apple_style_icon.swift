import AppKit

let size = 1024
let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "build/icon_apple_1024.png"
let scaleArg = args.count > 2 ? Double(args[2]) ?? 0.85 : 0.85
let cornerArg = args.count > 3 ? Double(args[3]) ?? 220.0 : 220.0
let insetArg = args.count > 4 ? Double(args[4]) ?? 0.04 : 0.04
let scale = CGFloat(scaleArg)
let corner = CGFloat(cornerArg)
let inset = CGFloat(insetArg) * CGFloat(size)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2.0, height: CGFloat(size) - inset * 2.0)
let radius: CGFloat = corner
let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
let base = NSGradient(colors: [NSColor(calibratedRed: 0.14, green: 0.53, blue: 0.96, alpha: 1.0), NSColor(calibratedRed: 0.08, green: 0.36, blue: 0.85, alpha: 1.0)])!
base.draw(in: bgPath, angle: 90)

bgPath.addClip()
let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.20), NSColor.clear])!
let glossRect = NSRect(x: 0, y: size/2, width: size, height: size/2)
gloss.draw(in: glossRect, angle: 90)

let shadow = NSShadow()
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.set()

let axisColor = NSColor.white.withAlphaComponent(0.9)
axisColor.setStroke()

let axis = NSBezierPath()
axis.lineCapStyle = .round
axis.lineJoinStyle = .round
axis.lineWidth = 24
axis.move(to: NSPoint(x: 210, y: 260))
axis.line(to: NSPoint(x: 210, y: 820))
axis.move(to: NSPoint(x: 210, y: 260))
axis.line(to: NSPoint(x: 820, y: 260))

let curve = NSBezierPath()
curve.lineCapStyle = .round
curve.lineJoinStyle = .round
curve.lineWidth = 22
curve.move(to: NSPoint(x: 250, y: 340))
curve.curve(to: NSPoint(x: 820, y: 740), controlPoint1: NSPoint(x: 420, y: 720), controlPoint2: NSPoint(x: 640, y: 520))

let markerColor = NSColor.white.withAlphaComponent(0.95)
let m1 = NSBezierPath(ovalIn: NSRect(x: 240, y: 330, width: 36, height: 36))
let m2 = NSBezierPath(ovalIn: NSRect(x: 810, y: 720, width: 36, height: 36))

var t = AffineTransform()
t.translate(x: rect.midX, y: rect.midY)
t.scale(x: 0.85, y: 0.85)
t.translate(x: -rect.midX, y: -rect.midY)
axis.transform(using: t)
curve.transform(using: t)
m1.transform(using: t)
m2.transform(using: t)

axis.stroke()
axisColor.setStroke()
curve.stroke()
markerColor.setFill()
m1.fill()
m2.fill()

let img = NSImage(size: NSSize(width: size, height: size))
img.addRepresentation(rep)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(2) }
try! data.write(to: URL(fileURLWithPath: outPath))
