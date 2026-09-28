// Draws the app icon (dark squircle + purple holographic orb). Run: swift Scripts/MakeIcon.swift <out.png>
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let rgb = CGColorSpaceCreateDeviceRGB()
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
func radial(_ colors: [CGColor], _ locs: [CGFloat], at p: CGPoint, r: CGFloat) {
    let g = CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: locs)!
    ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
}

// macOS grid: 824pt tile centered on 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0, 0, 0, 0.45))
ctx.addPath(shape); ctx.setFillColor(c(0.05, 0.03, 0.10)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: rgb, colors: [c(0.14, 0.07, 0.26), c(0.03, 0.02, 0.07)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
let o = CGPoint(x: 512, y: 512)
radial([c(0.61, 0.36, 1, 0.55), c(0.61, 0.36, 1, 0)], [0, 1], at: o, r: 400)  // halo
// Orbit rings
ctx.setLineWidth(6)
for (i, tilt) in [CGFloat(-0.35), 0.5].enumerated() {
    ctx.saveGState()
    ctx.translateBy(x: o.x, y: o.y); ctx.rotate(by: tilt)
    ctx.setStrokeColor(c(0.78, 0.62, 1, i == 0 ? 0.7 : 0.45))
    ctx.strokeEllipse(in: CGRect(x: -330, y: -95, width: 660, height: 190))
    ctx.restoreGState()
}
// Core sphere
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: o.x - 210, y: o.y - 210, width: 420, height: 420)); ctx.clip()
radial([c(0.95, 0.88, 1), c(0.72, 0.48, 1), c(0.42, 0.18, 0.85), c(0.16, 0.05, 0.38)], [0, 0.25, 0.7, 1],
       at: CGPoint(x: o.x - 70, y: o.y + 80), r: 330)
ctx.restoreGState()
radial([c(1, 1, 1, 0.9), c(1, 1, 1, 0)], [0, 1], at: CGPoint(x: o.x - 80, y: o.y + 95), r: 70)  // highlight
ctx.restoreGState()
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
