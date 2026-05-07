import SwiftUI

@main
struct AbyssLTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettingsStore()

    var body: some Scene {
        WindowGroup("AbyssL Translator", id: "translator") {
            MainWindowView(settings: settings)
                .environmentObject(settings)
                .frame(minWidth: 880, minHeight: 700)
                .onAppear {
                    appDelegate.configure(settings: settings)
                }
        }
        .commands {
            CommandMenu(String(localized: "menu.translation", bundle: .module)) {
                Button(String(localized: "menu.translateNow", bundle: .module)) {
                    NotificationCenter.default.post(name: .abysslTranslateNow, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
