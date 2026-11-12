import ActivityKit
import SwiftUI
import WidgetKit
import LiveAktivitaet

@main
struct LilithWidgets: WidgetBundle {
    var body: some Widget {
        UploadLiveActivity()
    }
}

/// Fortschritt großer Uploads auf dem Sperrbildschirm und in der Dynamic Island.
struct UploadLiveActivity: Widget {
    /// Kirschrot (dunkle Variante #FF4D6A), die Live-Aktivität liegt auf dunklem Grund.
    private let nachtrose = Color(red: 1.0, green: 0x4D / 255.0, blue: 0x6A / 255.0)
    private let mondlicht = Color(red: 0.92, green: 0.85, blue: 0.71)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UploadAktivitaet.self) { kontext in
            // Sperrbildschirm
            HStack(spacing: 14) {
                Image(systemName: kontext.state.fertig ? "moon.fill" : "moon.haze.fill")
                    .font(.title2)
                    .foregroundStyle(mondlicht)
                VStack(alignment: .leading, spacing: 6) {
                    Text(kontext.state.fertig ? "Hochgeladen" : "Lilith lädt hoch")
                        .font(.headline)
                    ProgressView(value: kontext.state.anteil)
                        .tint(nachtrose)
                    Text(kontext.state.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.75))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { kontext in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.haze.fill").foregroundStyle(mondlicht)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(kontext.state.text).monospacedDigit().font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: kontext.state.anteil).tint(nachtrose)
                }
            } compactLeading: {
                Image(systemName: "moon.haze.fill").foregroundStyle(mondlicht)
            } compactTrailing: {
                Text("\(kontext.state.erledigt)/\(kontext.state.gesamt)").monospacedDigit().font(.caption2)
            } minimal: {
                ProgressView(value: kontext.state.anteil)
                    .progressViewStyle(.circular)
                    .tint(nachtrose)
            }
        }
    }
}
