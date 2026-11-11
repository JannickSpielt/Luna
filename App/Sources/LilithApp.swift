import SwiftUI
import AppFeature

@main
struct LilithApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}
