import SwiftUI

@main
struct CapsLockControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }

        Window("CapsLock Control", id: WindowIdentifier.keyLayout) {
            MainWindowView(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 780)

        Window("CapsLock Control 설정", id: WindowIdentifier.settings) {
            SettingsView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
    }
}
