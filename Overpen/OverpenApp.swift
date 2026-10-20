import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let delegate = AppDelegate()

    private var statusMenu: StatusMenu?
    private var subscriptions = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlay = OverlayController.shared
        let menu = StatusMenu()
        statusMenu = menu
        overlay.onChange = { menu.refresh() }
        overlay.start()

        let prefs = Preferences.shared
        GlobalHotKey.shared.onPress = { OverlayController.shared.toggle() }
        GlobalHotKey.shared.register(prefs.shortcut(for: .toggle))
        prefs.$shortcuts
            .map { $0[.toggle] }
            .removeDuplicates()
            .dropFirst()
            .sink { GlobalHotKey.shared.register($0) }
            .store(in: &subscriptions)

        if prefs.consumeFirstLaunch() { SettingsWindowController.shared.show() }
    }

    /// Opening the app again from Finder or Spotlight shows the settings, since there is no window otherwise.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }
}
