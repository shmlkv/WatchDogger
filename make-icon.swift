import Cocoa

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
let iconDir = "WatchDogger.app/Contents/Resources/AppIcon.iconset"

try? FileManager.default.createDirectory(atPath: iconDir, withIntermediateDirectories: true)

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size

    // Background circle — orange
    ctx.setFillColor(NSColor(red: 0.85, green: 0.45, blue: 0.1, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: s*0.04, y: s*0.04, width: s*0.92, height: s*0.92))

    // Shield
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: s*0.5, y: s*0.85))
    shield.addCurve(to: CGPoint(x: s*0.18, y: s*0.55), control1: CGPoint(x: s*0.28, y: s*0.82), control2: CGPoint(x: s*0.18, y: s*0.7))
    shield.addLine(to: CGPoint(x: s*0.18, y: s*0.35))
    shield.addLine(to: CGPoint(x: s*0.5, y: s*0.18))
    shield.addLine(to: CGPoint(x: s*0.82, y: s*0.35))
    shield.addLine(to: CGPoint(x: s*0.82, y: s*0.55))
    shield.addCurve(to: CGPoint(x: s*0.5, y: s*0.85), control1: CGPoint(x: s*0.82, y: s*0.7), control2: CGPoint(x: s*0.72, y: s*0.82))
    shield.closeSubpath()

    ctx.saveGState()
    ctx.addPath(shield)
    ctx.clip()
    let colors = [
        NSColor(red: 1.0, green: 0.65, blue: 0.2, alpha: 1.0).cgColor,
        NSColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1.0).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: s*0.5, y: s*0.85), end: CGPoint(x: s*0.5, y: s*0.18), options: [])
    ctx.restoreGState()

    ctx.setStrokeColor(NSColor(red: 1.0, green: 0.75, blue: 0.4, alpha: 0.6).cgColor)
    ctx.setLineWidth(s*0.02)
    ctx.addPath(shield)
    ctx.strokePath()

    // Eye
    let eyeY = s * 0.52
    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: s*0.34, y: eyeY))
    eye.addQuadCurve(to: CGPoint(x: s*0.66, y: eyeY), control: CGPoint(x: s*0.5, y: eyeY + s*0.16))
    eye.addQuadCurve(to: CGPoint(x: s*0.34, y: eyeY), control: CGPoint(x: s*0.5, y: eyeY - s*0.16))
    eye.closeSubpath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(eye)
    ctx.fillPath()

    // Iris — blue
    ctx.setFillColor(NSColor(red: 0.15, green: 0.4, blue: 0.9, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: s*0.5 - s*0.065, y: eyeY - s*0.065, width: s*0.13, height: s*0.13))

    // Pupil
    ctx.setFillColor(NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(x: s*0.5 - s*0.035, y: eyeY - s*0.035, width: s*0.07, height: s*0.07))

    // Highlight
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
    ctx.fillEllipse(in: CGRect(x: s*0.5 + s*0.01, y: eyeY + s*0.01, width: s*0.025, height: s*0.025))

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }

    let name = size <= 512 ? "icon_\(Int(size))x\(Int(size)).png" : "icon_512x512@2x.png"
    try? png.write(to: URL(fileURLWithPath: "\(iconDir)/\(name)"))
    if size <= 512 && size > 16 {
        let half = Int(size / 2)
        try? png.write(to: URL(fileURLWithPath: "\(iconDir)/icon_\(half)x\(half)@2x.png"))
    }
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconDir, "-o", "WatchDogger.app/Contents/Resources/AppIcon.icns"]
try? p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Icon OK" : "Icon FAIL")
