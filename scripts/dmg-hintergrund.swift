import AppKit
// Hintergrund fürs DMG-Fenster (600 × 400 pt, @2x): Nachthimmel, links Platz für Luna, rechts für „Programme“,
// dazwischen ein Pfeil und darunter ein kurzer Hinweis.
let ziel = CommandLine.arguments[1]
let b = 600.0, h = 400.0, s = 2.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b * s), pixelsHigh: Int(h * s), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: b, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let nacht = NSColor(red: 0x12/255, green: 0x0E/255, blue: 0x10/255, alpha: 1)
let creme = NSColor(red: 0xF4/255, green: 0xED/255, blue: 0xE4/255, alpha: 1)
nacht.setFill(); NSRect(x: 0, y: 0, width: b, height: h).fill()
// ein paar ruhige Sterne
var zufall = SystemRandomNumberGenerator()
for _ in 0..<70 {
    let x = Double.random(in: 0..<b, using: &zufall), y = Double.random(in: 0..<h, using: &zufall)
    let r = Double.random(in: 0.4...1.2, using: &zufall)
    creme.withAlphaComponent(Double.random(in: 0.15...0.5, using: &zufall)).setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: r, height: r)).fill()
}
// Pfeil zwischen den Symbolen (Symbole liegen bei x 150 und 450, y 200 von oben)
let pfeil = NSBezierPath()
pfeil.move(to: NSPoint(x: 245, y: 200)); pfeil.line(to: NSPoint(x: 345, y: 200))
pfeil.move(to: NSPoint(x: 330, y: 212)); pfeil.line(to: NSPoint(x: 347, y: 200)); pfeil.line(to: NSPoint(x: 330, y: 188))
pfeil.lineWidth = 3; pfeil.lineCapStyle = .round; pfeil.lineJoinStyle = .round
creme.withAlphaComponent(0.7).setStroke(); pfeil.stroke()
func text(_ t: String, _ groesse: CGFloat, _ gewicht: NSFont.Weight, _ alpha: CGFloat, y: CGFloat) {
    let a = NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: groesse, weight: gewicht),
                                                      .foregroundColor: creme.withAlphaComponent(alpha)])
    a.draw(at: NSPoint(x: (b - a.size().width) / 2, y: y))
}
text("Luna", 26, .semibold, 1, y: h - 70)
text("Zum Installieren Luna auf „Programme“ ziehen", 14, .regular, 0.7, y: 60)
text("Beim ersten Start: Rechtsklick auf Luna → Öffnen", 12, .regular, 0.45, y: 38)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ziel))
