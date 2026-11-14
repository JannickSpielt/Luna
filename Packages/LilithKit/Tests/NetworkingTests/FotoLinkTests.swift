import Foundation
import Testing
@testable import Networking

@Suite("Widget-Link")
struct FotoLinkTests {
    @Test("Link hin und zurück")
    func hinUndZurueck() throws {
        let foto = WidgetFoto(id: "3f2a-11", aufgenommen: Date(timeIntervalSince1970: 1_763_000_000), stadt: "Offenburg")
        let url = FotoLink.url(foto)
        #expect(url.absoluteString == "luna://foto/3f2a-11?zeit=1763000000")
        let gelesen = try #require(FotoLink.lies(url))
        #expect(gelesen.id == "3f2a-11")
        #expect(gelesen.aufgenommen == foto.aufgenommen)
    }

    @Test("Fremde oder kaputte Links werden ignoriert")
    func fremd() {
        #expect(FotoLink.lies(URL(string: "https://foto/abc?zeit=1")!) == nil)
        #expect(FotoLink.lies(URL(string: "luna://album/abc?zeit=1")!) == nil)
        #expect(FotoLink.lies(URL(string: "luna://foto/abc")!) == nil)
        #expect(FotoLink.lies(URL(string: "luna://foto/?zeit=1")!) == nil)
    }
}
