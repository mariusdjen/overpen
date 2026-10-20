import AppKit
import Combine
import ServiceManagement

/// User settings, saved in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    static let defaultColors = ["#B67FE8", "#FF4B3E", "#FFD533", "#FFFFFF"]

    @Published var shortcuts: [Action: Shortcut] { didSet { saveShortcuts() } }
    @Published var colors: [String] { didSet { defaults.set(colors, forKey: Keys.colors) } }
    @Published var lineWidth: Double { didSet { defaults.set(lineWidth, forKey: Keys.lineWidth) } }
    @Published var clearWhenStopping: Bool { didSet { defaults.set(clearWhenStopping, forKey: Keys.clearWhenStopping) } }
    @Published var showHint: Bool { didSet { defaults.set(showHint, forKey: Keys.showHint) } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let shortcuts = "shortcuts"
        static let colors = "colors"
        static let lineWidth = "lineWidth"
        static let clearWhenStopping = "clearWhenStopping"
        static let showHint = "showHint"
        static let launchedBefore = "launchedBefore"
    }

    private init() {
        if let data = defaults.data(forKey: Keys.shortcuts),
           let stored = try? JSONDecoder().decode([String: Shortcut?].self, from: data) {
            var result = Shortcut.defaults()
            for (key, value) in stored {
                guard let action = Action(rawValue: key) else { continue }
                result[action] = value
            }
            shortcuts = result
        } else {
            shortcuts = Shortcut.defaults()
        }
        let storedColors = defaults.stringArray(forKey: Keys.colors) ?? []
        colors = storedColors.count == 4 ? storedColors : Self.defaultColors
        lineWidth = defaults.object(forKey: Keys.lineWidth) as? Double ?? 6
        clearWhenStopping = defaults.object(forKey: Keys.clearWhenStopping) as? Bool ?? true
        showHint = defaults.object(forKey: Keys.showHint) as? Bool ?? true
    }

    /// True the very first time the app runs, then false.
    func consumeFirstLaunch() -> Bool {
        let first = !defaults.bool(forKey: Keys.launchedBefore)
        defaults.set(true, forKey: Keys.launchedBefore)
        return first
    }

    func shortcut(for action: Action) -> Shortcut? { shortcuts[action] }

    func setShortcut(_ shortcut: Shortcut?, for action: Action) {
        // A shortcut belongs to one action only: take it away from any other action first.
        if let shortcut {
            for (other, existing) in shortcuts where other != action && existing == shortcut {
                shortcuts[other] = nil
            }
        }
        shortcuts[action] = shortcut
    }

    func restoreDefaultShortcuts() { shortcuts = Shortcut.defaults() }

    func color(at index: Int) -> NSColor {
        NSColor(hex: colors[index]) ?? .systemPurple
    }

    private func saveShortcuts() {
        // Removed shortcuts are saved as null so they stay removed after a relaunch.
        var stored: [String: Shortcut?] = [:]
        for action in Action.allCases { stored[action.rawValue] = shortcuts[action] }
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Keys.shortcuts) }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
