import AppKit

/// The icon in the menu bar and its menu.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    override init() {
        super.init()
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.accessibilityDescription = "Overpen"
        item.button?.image = image
        menu.delegate = self
        item.menu = menu
    }

    /// Tints the icon while the pen is on.
    func refresh() {
        item.button?.contentTintColor = OverlayController.shared.isActive ? NSColor(named: "AccentColor") : nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let overlay = OverlayController.shared

        let toggle = add(overlay.isActive ? String(localized: "Stop Drawing") : String(localized: "Start Drawing"),
                         #selector(toggleDrawing))
        apply(Preferences.shared.shortcut(for: .toggle), to: toggle)

        let clear = add(String(localized: "Clear Drawings"), #selector(clearDrawings))
        clear.isEnabled = overlay.hasDrawings

        menu.addItem(.separator())
        let settings = add(String(localized: "Settings…"), #selector(openSettings))
        settings.keyEquivalent = ","
        add(String(localized: "About Overpen"), #selector(openAbout))
        menu.addItem(.separator())
        let quit = add(String(localized: "Quit Overpen"), #selector(quit))
        quit.keyEquivalent = "q"
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func apply(_ shortcut: Shortcut?, to item: NSMenuItem) {
        guard let shortcut, let key = KeyNames.menuEquivalent(for: shortcut.keyCode) else { return }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = shortcut.flags
    }

    @objc private func toggleDrawing() { OverlayController.shared.toggle() }
    @objc private func clearDrawings() { OverlayController.shared.clear() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSMutableAttributedString(string: String(localized: "Draw over anything on your screen.") + "\n")
        let link = NSAttributedString(string: "github.com/mariusdjen/overpen", attributes: [
            .link: URL(string: "https://github.com/mariusdjen/overpen")!,
        ])
        credits.append(link)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        credits.addAttributes([.paragraphStyle: style, .font: NSFont.systemFont(ofSize: 11)],
                              range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
