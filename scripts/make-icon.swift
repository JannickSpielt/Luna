#!/usr/bin/env swift
// Zeichnet das Lilith-App-Icon: eine Mondsichel, deren Schattenseite eine Kamerablende ist.
// Aufruf:  swift scripts/make-icon.swift <Ausgabeordner>
// Erzeugt icon-light.png, icon-dark.png, icon-tinted.png (je 1024 × 1024) und mac-<Größe>.png.
import AppKit
import CoreGraphics
import Foundation

enum Variante { case hell, dunkel, getoent }

func farbe(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func grau(_ wert: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: wert, green: wert, blue: wert, alpha: alpha)
}

func zeichne(_ variante: Variante, groesse: Int) -> CGImage {
    let s = CGFloat(groesse)
    let ctx = CGContext(data: nil, width: groesse, height: groesse, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    // Koordinaten wie in Grafikprogrammen: y nach unten.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    let raum = CGColorSpace(name: CGColorSpace.sRGB)!

    // 1. Hintergrund: Nachthimmel mit rosigem Schimmer oben links.
    switch variante {
    case .hell:
        let verlauf = CGGradient(colorsSpace: raum, colors: [farbe(0x6B1F3E), farbe(0x2A1220), farbe(0x140A10)] as CFArray,
                                 locations: [0, 0.55, 1])!
        ctx.drawRadialGradient(verlauf, startCenter: CGPoint(x: 300, y: 220), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 512), endRadius: 900, options: [.drawsAfterEndLocation])
    case .dunkel:
        let verlauf = CGGradient(colorsSpace: raum, colors: [farbe(0x3A1426), farbe(0x0E080B)] as CFArray,
                                 locations: [0, 1])!
        ctx.drawRadialGradient(verlauf, startCenter: CGPoint(x: 300, y: 220), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 512), endRadius: 900, options: [.drawsAfterEndLocation])
    case .getoent:
        ctx.setFillColor(grau(0))
        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    }

    // 2. Ein paar Sterne, sehr dezent.
    if variante != .getoent {
        let sterne: [(CGFloat, CGFloat, CGFloat)] = [(196, 248, 5), (820, 190, 4), (868, 760, 3.5), (232, 812, 3), (742, 318, 2.5), (152, 520, 2.5)]
        for (x, y, r) in sterne {
            ctx.setFillColor(farbe(0xF3E6C8, variante == .hell ? 0.55 : 0.4))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    let mitte = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 318
    let mond = CGRect(x: mitte.x - radius, y: mitte.y - radius, width: radius * 2, height: radius * 2)
    // Der Schatten (verdeckende Scheibe), der aus dem Vollmond eine Sichel macht.
    let schattenMitte = CGPoint(x: mitte.x + 132, y: mitte.y - 86)
    let schattenRadius: CGFloat = 282

    // 3. Schattenseite des Mondes: die Blende. Sechs Lamellen um eine sechseckige Öffnung.
    ctx.saveGState()
    ctx.addEllipse(in: mond)
    ctx.clip()
    ctx.addEllipse(in: CGRect(x: schattenMitte.x - schattenRadius, y: schattenMitte.y - schattenRadius,
                              width: schattenRadius * 2, height: schattenRadius * 2))
    ctx.clip()
    // Schattenseite leicht aufhellen („Erdschein“), damit die Blende eine Fläche hat.
    ctx.setFillColor(variante == .getoent ? grau(0.12) : farbe(0xE46A8C, 0.07))
    ctx.fill(mond)
    let lamellenFarbe: CGColor = variante == .getoent ? grau(0.4) : farbe(0xE46A8C, variante == .hell ? 0.38 : 0.3)
    // Klassisches Blendensymbol: Von jeder Ecke des Sechsecks läuft eine Kante gerade nach außen weiter.
    let oeffnung: CGFloat = 96
    let ecken = (0..<6).map { i -> CGPoint in
        let winkel = CGFloat(i) * .pi / 3 + .pi / 6
        return CGPoint(x: schattenMitte.x + cos(winkel) * oeffnung, y: schattenMitte.y + sin(winkel) * oeffnung)
    }
    for i in 0..<6 {
        let a = ecken[i], b = ecken[(i + 1) % 6]
        let laenge = hypot(b.x - a.x, b.y - a.y)
        let richtung = CGPoint(x: (b.x - a.x) / laenge, y: (b.y - a.y) / laenge)
        ctx.move(to: a)
        ctx.addLine(to: CGPoint(x: a.x + richtung.x * 420, y: a.y + richtung.y * 420))
    }
    ctx.setStrokeColor(lamellenFarbe)
    ctx.setLineWidth(11)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // 4. Die Sichel: Mondscheibe ohne Schatten, mit warmem Mondlicht-Verlauf.
    ctx.saveGState()
    let sichel = CGMutablePath()
    sichel.addEllipse(in: mond)
    sichel.addEllipse(in: CGRect(x: schattenMitte.x - schattenRadius, y: schattenMitte.y - schattenRadius,
                                 width: schattenRadius * 2, height: schattenRadius * 2))
    ctx.addPath(sichel)
    ctx.clip(using: .evenOdd)
    // Wo der Schatten über den Mond hinausragt, würde even-odd ihn füllen: zusätzlich auf den Mond begrenzen.
    ctx.addEllipse(in: mond)
    ctx.clip()
    if variante == .getoent {
        ctx.setFillColor(grau(1))
        ctx.fill(mond)
    } else {
        let licht = CGGradient(colorsSpace: raum, colors: [farbe(0xFBF1DC), farbe(0xEBD9B4), farbe(0xC9A46A)] as CFArray,
                               locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(licht, start: CGPoint(x: 260, y: 240), end: CGPoint(x: 620, y: 860), options: [])
    }
    ctx.restoreGState()

    // 5. Ein Hauch Leuchten um die Sichel.
    if variante != .getoent {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 60, color: farbe(0xEBD9B4, variante == .hell ? 0.35 : 0.25))
        ctx.addPath(sichel)
        ctx.setStrokeColor(farbe(0xEBD9B4, 0.01))
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
    }

    return ctx.makeImage()!
}

/// Mac-Icon für macOS 15: abgerundete Form mit Rand und Schatten, wie Apple es vorgibt
/// (824 × 824 Fläche in 1024 × 1024, Eckradius ca. 185).
func zeichneMac(groesse: Int) -> CGImage {
    let s = CGFloat(groesse)
    let ctx = CGContext(data: nil, width: groesse, height: groesse, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    let form = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: grau(0, 0.35))
    ctx.addPath(form)
    ctx.setFillColor(farbe(0x140A10))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(form)
    ctx.clip()
    let inhalt = zeichne(.hell, groesse: 1024)
    ctx.draw(inhalt, in: CGRect(x: 100, y: 100, width: 824, height: 824))
    return ctx.makeImage()!
}

func speichere(_ bild: CGImage, _ pfad: String) {
    let rep = NSBitmapImageRep(cgImage: bild)
    guard let daten = rep.representation(using: .png, properties: [:]) else { fatalError("PNG fehlgeschlagen") }
    try! daten.write(to: URL(fileURLWithPath: pfad))
}

let ziel = CommandLine.arguments.dropFirst().first ?? "."
try FileManager.default.createDirectory(atPath: ziel, withIntermediateDirectories: true)
speichere(zeichne(.hell, groesse: 1024), "\(ziel)/icon-light.png")
speichere(zeichne(.dunkel, groesse: 1024), "\(ziel)/icon-dark.png")
speichere(zeichne(.getoent, groesse: 1024), "\(ziel)/icon-tinted.png")
for g in [16, 32, 64, 128, 256, 512, 1024] {
    speichere(zeichneMac(groesse: g), "\(ziel)/mac-\(g).png")
}
print("Icons gespeichert in \(ziel)")
