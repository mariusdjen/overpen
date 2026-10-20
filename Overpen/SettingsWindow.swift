import AppKit
import SwiftUI

/// Native settings window with toolbar tabs.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private static let tabKey = "settingsTab"
    private let tabs = NSTabViewController()

    var isVisible: Bool { window?.isVisible == true }

    private init() {
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.tab(String(localized: "General"), symbol: "gearshape", view: GeneralSettings()))
        tabs.addTabViewItem(Self.tab(String(localized: "Shortcuts"), symbol: "keyboard", view: ShortcutSettings()))
        tabs.addTabViewItem(Self.tab(String(localized: "Pen"), symbol: "pencil.and.scribble", view: PenSettings()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        // Reopen on the tab the user looked at last.
        let saved = UserDefaults.standard.integer(forKey: Self.tabKey)
        if saved < tabs.tabViewItems.count { tabs.selectedTabViewItemIndex = saved }
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(tabs.selectedTabViewItemIndex, forKey: Self.tabKey)
    }

    required init?(coder: NSCoder) { nil }

    private static func tab<V: View>(_ label: String, symbol: String, view: V) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view.frame(width: 520))
        controller.sizingOptions = .preferredContentSize
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    func show() {
        if OverlayController.shared.isActive { OverlayController.shared.stop() }
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }
}
