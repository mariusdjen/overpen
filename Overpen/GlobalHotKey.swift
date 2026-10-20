import AppKit
import Carbon

/// The one shortcut that works from any app. Carbon hot keys need no Accessibility permission and work in the sandbox.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onPress: (() -> Void)?
    private(set) var current: Shortcut?
    private(set) var isTaken = false
    private var reference: EventHotKeyRef?
    private var handlerInstalled = false

    /// Registers the shortcut. Returns false when another app already uses it.
    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        unregister()
        current = shortcut
        installHandler()
        guard let shortcut else { isTaken = false; return true }
        let id = EventHotKeyID(signature: OSType(0x4F56504E), id: 1) // "OVPN"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &reference)
        isTaken = status != noErr
        return !isTaken
    }

    /// Used while the user records a new shortcut, so pressing the current one does not toggle the pen.
    func pause() { unregister() }

    func resume() { register(current) }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.shared.onPress?() }
            return noErr
        }, 1, &type, nil, nil)
    }
}
