import Foundation
import Testing
import Networking
import TimelineGrid
@testable import AppFeature

@MainActor
@Suite("Info unter dem Foto")
struct InfoUnterFotoTests {
    private func info(_ name: String = "IMG_4504.heic") -> AssetInfo {
        var i = AssetInfo(id: "a", dateiname: name, aufgenommenLokal: .now)
        i.breite = 4032; i.hoehe = 2268; i.dateigroesse = 1_600_000
        i.iso = 125; i.brennweite = 1.57; i.blende = 1.8; i.belichtung = "1/100"
        return i
    }

    @Test("Format-Abzeichen aus der Dateiendung")
    func endung() {
        #expect(InfoUnterFoto.endung("IMG_1.heic") == "HEIC")
        #expect(InfoUnterFoto.endung("bild.jpg") == "JPEG")
        #expect(InfoUnterFoto.endung("ohne_endung") == nil)
    }

    @Test("Dateizeile: Megapixel, Maße, Größe")
    func dateizeile() throws {
        let zeile = try #require(InfoUnterFoto.dateiZeile(info()))
        #expect(zeile.hasPrefix("9,1 MP · 4032 × 2268 · "))
        var leer = info(); leer.breite = nil; leer.hoehe = nil; leer.dateigroesse = nil
        #expect(InfoUnterFoto.dateiZeile(leer) == nil)
    }

    @Test("Belichtungswerte in fester Reihenfolge, fehlende weggelassen")
    func belichtung() {
        #expect(InfoUnterFoto.belichtungsWerte(info()) == ["ISO 125", "1,6 mm", "ƒ1,8", "1/100 s"])
        var teil = info(); teil.iso = nil; teil.belichtung = nil
        #expect(InfoUnterFoto.belichtungsWerte(teil) == ["1,6 mm", "ƒ1,8"])
    }
}

@MainActor
@Suite("Zählen")
struct ZaehlTests {
    @Test("Einzahl: 1 Objekt")
    func einzahl() {
        #expect(TimelineStore.untertitel(anzahl: 1, lokal: 0) == "1 Objekt")
        #expect(TimelineStore.untertitel(anzahl: 2, lokal: 0) == "2 Objekte")
    }
}

@MainActor
@Suite("Vorschau-Leiste")
struct VorschauLeisteTests {
    let quelle = BeispielQuelle(anzahl: 1_000)

    @Test("Fenster der Leiste rückt mit und endet erst am Rand der Bibliothek")
    func fenster() {
        let mitte = DetailPosition(section: quelle.sections.count / 2, index: 0)
        let f = DetailView.fenster(um: mitte, quelle: quelle, radius: 120)
        #expect(f.contains(mitte))
        #expect(f.count == 241)
        let anfang = DetailView.fenster(um: DetailPosition(section: 0, index: 0), quelle: quelle, radius: 120)
        #expect(anfang.first == DetailPosition(section: 0, index: 0))
        #expect(anfang.count == 121)
    }
}

@MainActor
@Suite("Reihenfolge wie Apple")
struct ReihenfolgeTests {
    let quelle = BeispielQuelle(anzahl: 1_000)

    @Test("In „Fotos“ ältere links, sonst Neuestes zuerst")
    func reihenfolge() {
        let mitte = DetailPosition(section: quelle.sections.count / 2, index: 0)
        let liste = DetailView.fenster(um: mitte, quelle: quelle, radius: 5)
        let apple = DetailView.fenster(um: mitte, quelle: quelle, radius: 5, aeltereLinks: true)
        #expect(apple == liste.reversed())
        // Links vom aktuellen Foto liegt in „Fotos“ das ältere (davor in der Liste = neuer).
        let i = apple.firstIndex(of: mitte)!
        #expect(apple[i - 1] == DetailView.danach(mitte, quelle: quelle))
        #expect(DetailView.fenster(um: mitte, quelle: quelle, radius: 5, aeltereLinks: false) == liste)
    }
}
