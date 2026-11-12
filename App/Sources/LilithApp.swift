import SwiftUI
import AppFeature

@main
struct LilithApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        RootView.einrichten()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}

#if os(iOS)
/// Nur für Hintergrund-Uploads: iOS weckt Lilith, wenn sie fertig sind.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        BackupZentrale.hintergrundUploadsGeweckt(completionHandler)
    }
}
#endif
