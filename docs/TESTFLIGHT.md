# Lilith auf das eigene iPhone bringen

Es gibt zwei Wege. Für beide brauchst du eine Apple-ID, für TestFlight zusätzlich ein kostenpflichtiges Apple-Entwicklerkonto (99 € im Jahr).

## Weg 1: Direkt aus Xcode aufs iPhone (kostenlos)

Geht mit jeder Apple-ID. Die App läuft dann 7 Tage, danach musst du sie neu aufspielen.

1. In Xcode unter **Einstellungen → Accounts** deine Apple-ID hinzufügen.
2. Deine Team-ID heraussuchen: Sie steht dort neben dem Team („Personal Team“), zehn Zeichen wie `AB12CD34EF`.
3. Projekt mit deiner Team-ID erzeugen und öffnen:

   ```bash
   cd ~/Lilith/App && LILITH_TEAM=AB12CD34EF xcodegen && open Lilith.xcodeproj
   ```

4. iPhone per Kabel anschließen, oben als Ziel auswählen, auf ▶︎ klicken.
5. Beim ersten Mal auf dem iPhone unter **Einstellungen → Allgemein → VPN und Geräteverwaltung** dem Entwickler vertrauen. Ab iOS 16 muss außerdem der **Entwicklermodus** an sein (Einstellungen → Datenschutz & Sicherheit).

Hinweis: Mit einem kostenlosen Konto muss die Bundle-ID einmalig sein. Ist `app.lilith.Lilith` schon vergeben, in `App/project.yml` bei `PRODUCT_BUNDLE_IDENTIFIER` etwas Eigenes eintragen, z. B. `de.deinname.lilith`.

## Weg 2: TestFlight (Entwicklerkonto nötig)

Damit installierst du Lilith wie eine normale App über die TestFlight-App, auch auf mehreren Geräten und für Familie, 90 Tage pro Version.

1. Im [Apple Developer Portal](https://developer.apple.com/account) unter **Identifiers** die Bundle-ID `app.lilith.Lilith` anlegen (oder deine eigene).
2. In [App Store Connect](https://appstoreconnect.apple.com) unter **Apps → +** eine neue App anlegen: Name „Lilith“, Plattformen iOS und macOS, dieselbe Bundle-ID.
3. Projekt mit deiner Team-ID erzeugen (siehe oben, Schritt 3).
4. In Xcode oben als Ziel **Any iOS Device** wählen, dann **Product → Archive**.
5. Im Fenster „Organizer“ auf **Distribute App → TestFlight & App Store** klicken und den Anweisungen folgen.
6. Nach der Verarbeitung (meist 10–30 Minuten) erscheint der Build in App Store Connect unter **TestFlight**. Dich selbst unter „Interne Tests“ hinzufügen, dann kommt eine Einladung in die TestFlight-App.

Vor jedem neuen Build `CURRENT_PROJECT_VERSION` in `App/project.yml` um eins erhöhen.

## Was schon vorbereitet ist

- **App-Icon** in allen Größen für iPhone, iPad und Mac (inkl. dunkel und getönt).
- **Datenschutz-Angaben** (`App/Resources/PrivacyInfo.xcprivacy`): kein Tracking, keine gesammelten Daten. Die einzige genutzte „Pflicht-API“ ist UserDefaults für die eigenen Einstellungen.
- **Verschlüsselung:** `ITSAppUsesNonExemptEncryption = NO` in `App/Info.plist`. Lilith nutzt nur die Verschlüsselung von iOS (HTTPS, Schlüsselbund), deshalb fragt App Store Connect nicht bei jedem Build nach.
- **Berechtigungstexte** für Face ID (App-Sperre) und lokales Netzwerk (Server im Heimnetz).

## Für eine spätere Veröffentlichung im App Store

Apple prüft jede App. Weil Lilith einen eigenen Immich-Server braucht, verlangt die Prüfung einen **Demo-Zugang**. Möglich ist der öffentliche Demo-Server von Immich oder ein eigenes Testkonto auf deinem Server. Zusätzlich nötig sind eine Datenschutzerklärung (Webseite), Screenshots und eine Beschreibung.
