import AppKit
import SwiftUI

/// One freehand line or one frame (Shift + drag).
final class Stroke {
    let color: NSColor
    let width: CGFloat
    let path = NSBezierPath()
    var frame: NSRect?
    var origin: NSPoint = .zero

    init(color: NSColor, width: CGFloat) {
        self.color = color
        self.width = width
    }

    var drawable: NSBezierPath {
        guard let frame else { return path }
        let radius = min(12, min(frame.width, frame.height) / 2)
        return NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
    }
}

final class CanvasView: NSView {
    var strokes: [Stroke] = []
    private var current: Stroke?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        for stroke in strokes + (current.map { [$0] } ?? []) {
            let path = stroke.drawable
            path.lineWidth = stroke.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            stroke.color.setStroke()
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let prefs = Preferences.shared
        let stroke = Stroke(color: prefs.color(at: OverlayController.shared.colorIndex), width: CGFloat(prefs.lineWidth))
        let point = convert(event.locationInWindow, from: nil)
        stroke.origin = point
        if event.modifierFlags.contains(.shift) {
            stroke.frame = NSRect(origin: point, size: .zero)
        } else {
            stroke.path.move(to: point)
            stroke.path.line(to: point)
        }
        current = stroke
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let stroke = current else { return }
        let p = convert(event.locationInWindow, from: nil)
        if stroke.frame != nil {
            stroke.frame = NSRect(x: min(p.x, stroke.origin.x), y: min(p.y, stroke.origin.y),
                                  width: abs(p.x - stroke.origin.x), height: abs(p.y - stroke.origin.y))
        } else {
            stroke.path.line(to: p)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let stroke = current else { return }
        strokes.append(stroke)
        current = nil
        OverlayController.shared.didFinishStroke(on: self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if !OverlayController.shared.handleKey(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        OverlayController.shared.handleKey(event)
    }

    func removeAll() {
        strokes.removeAll()
        current = nil
        needsDisplay = true
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns one transparent window per screen and the drawing state.
final class OverlayController {
    static let shared = OverlayController()

    private(set) var isActive = false
    private(set) var colorIndex = 0
    var onChange: (() -> Void)?

    private var windows: [OverlayWindow] = []
    /// Canvases in the order strokes were drawn, for undo across screens.
    private var history: [CanvasView] = []
    private let hint = HintPanel()

    var hasDrawings: Bool { canvases.contains { !$0.strokes.isEmpty } }

    private var canvases: [CanvasView] { windows.compactMap { $0.contentView as? CanvasView } }

    func start() {
        rebuildWindows()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuildWindows() }
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            w.ignoresMouseEvents = !isActive
            w.contentView = CanvasView(frame: NSRect(origin: .zero, size: screen.frame.size))
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            return w
        }
        history.removeAll()
    }

    func toggle() { isActive ? stop() : begin() }

    func begin() {
        guard !isActive else { return }
        isActive = true
        windows.forEach { $0.ignoresMouseEvents = false }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let window = windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
        NSCursor.crosshair.set()
        if Preferences.shared.showHint, let screen = window?.screen {
            let shortcut = Preferences.shared.shortcut(for: .stop)?.display
            hint.show(text: shortcut.map { String(localized: "Pen on. Press \($0) to stop.") } ?? String(localized: "Pen on."),
                      color: Preferences.shared.color(at: colorIndex), on: screen)
        }
        onChange?()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        windows.forEach { $0.ignoresMouseEvents = true }
        if Preferences.shared.clearWhenStopping { clear() }
        hint.hide()
        NSCursor.arrow.set()
        // Give the keyboard back to the app the user was in, unless our settings are open.
        if !SettingsWindowController.shared.isVisible {
            NSApp.hide(nil)
        }
        onChange?()
    }

    func clear() {
        canvases.forEach { $0.removeAll() }
        history.removeAll()
        onChange?()
    }

    func undo() {
        guard let canvas = history.popLast(), !canvas.strokes.isEmpty else { return }
        canvas.strokes.removeLast()
        canvas.needsDisplay = true
        onChange?()
    }

    func selectColor(_ index: Int) {
        colorIndex = index
        if isActive, Preferences.shared.showHint, let screen = NSApp.keyWindow?.screen ?? NSScreen.main {
            hint.show(text: String(localized: "Color \(index + 1)"), color: Preferences.shared.color(at: index), on: screen)
        }
    }

    func didFinishStroke(on canvas: CanvasView) {
        history.append(canvas)
        onChange?()
    }

    /// Shortcuts that only work while the pen is on.
    func handleKey(_ event: NSEvent) -> Bool {
        guard isActive, event.type == .keyDown else { return false }
        let prefs = Preferences.shared
        guard let action = Action.allCases.first(where: { !$0.isGlobal && prefs.shortcut(for: $0)?.matches(event) == true }) else {
            return false
        }
        switch action {
        case .undo: undo()
        case .clear: clear()
        case .stop: stop()
        case .toggle: break
        case .color1, .color2, .color3, .color4: selectColor(action.colorIndex ?? 0)
        }
        return true
    }
}

/// Small message at the top of the screen that fades out on its own.
final class HintPanel {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(text: String, color: NSColor, on screen: NSScreen) {
        let host = NSHostingView(rootView: HintView(text: text, color: Color(nsColor: color)))
        host.layout()
        let size = host.fittingSize
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 16)
        let panel = self.panel ?? makePanel()
        panel.contentView = host
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return p
    }
}

private struct HintView: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color(white: 0.1).opacity(0.88)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        .fixedSize()
    }
}
