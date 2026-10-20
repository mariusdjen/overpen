import AppKit
import SwiftUI

struct GeneralSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overpen").font(.title2.weight(.semibold))
                        if let toggle = prefs.shortcut(for: .toggle) {
                            Text("Draw over anything on your screen. Press \(toggle.display) to start, or use the pen icon in the menu bar.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Draw over anything on your screen. Use the pen icon in the menu bar to start.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
                Toggle("Clear drawings when the pen turns off", isOn: $prefs.clearWhenStopping)
                Toggle("Show a short message when the pen turns on", isOn: $prefs.showHint)
            }

            Section("Tips") {
                Label("Hold Shift while dragging to draw a frame.", systemImage: "rectangle.dashed")
                Label("Turn off clearing to keep your drawings on screen while you work.", systemImage: "eye")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ShortcutSettings: View {
    @ObservedObject private var prefs = Preferences.shared
    @State private var globalTaken = GlobalHotKey.shared.isTaken

    var body: some View {
        Form {
            Section {
                row(.toggle)
                if globalTaken {
                    Text("Another app already uses this shortcut. Choose another one.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Works from any app.").font(.callout).foregroundStyle(.secondary)
            }

            Section {
                row(.undo)
                row(.clear)
                row(.stop)
            } header: {
                Text("While drawing")
            }

            Section {
                ForEach([Action.color1, .color2, .color3, .color4]) { action in
                    LabeledContent {
                        ShortcutRecorder(action: action)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(nsColor: prefs.color(at: action.colorIndex ?? 0)))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                            Text(action.title)
                        }
                    }
                }
            } header: {
                Text("Colors")
            }

            HStack {
                Spacer()
                Button("Restore Defaults") { prefs.restoreDefaultShortcuts() }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(prefs.$shortcuts) { _ in
            DispatchQueue.main.async { globalTaken = GlobalHotKey.shared.isTaken }
        }
    }

    private func row(_ action: Action) -> some View {
        LabeledContent(action.title) { ShortcutRecorder(action: action) }
    }
}

struct PenSettings: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Colors") {
                ForEach(0..<4, id: \.self) { index in
                    ColorPicker(selection: colorBinding(index), supportsOpacity: false) {
                        Text("Color \(index + 1)")
                    }
                }
                HStack {
                    Spacer()
                    Button("Restore Colors") { prefs.colors = Preferences.defaultColors }
                }
            }

            Section("Line") {
                LabeledContent("Thickness") {
                    HStack {
                        Slider(value: $prefs.lineWidth, in: 2...20, step: 1).frame(width: 200)
                        Text("\(Int(prefs.lineWidth)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LinePreview(colors: (0..<4).map { Color(nsColor: prefs.color(at: $0)) }, width: prefs.lineWidth)
                    .frame(height: 70)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: prefs.color(at: index)) },
            set: { prefs.colors[index] = NSColor($0).hexString }
        )
    }
}

/// Four sample strokes so the user sees the colors and thickness right away.
private struct LinePreview: View {
    let colors: [Color]
    let width: Double

    var body: some View {
        Canvas { context, size in
            let step = size.width / CGFloat(colors.count)
            for (i, color) in colors.enumerated() {
                let x = step * CGFloat(i) + 18
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height * 0.7))
                path.addCurve(to: CGPoint(x: x + step - 36, y: size.height * 0.3),
                              control1: CGPoint(x: x + step * 0.3, y: size.height * 0.05),
                              control2: CGPoint(x: x + step * 0.45, y: size.height * 0.95))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
    }
}

/// Click, then press the new keys. Esc cancels, Delete removes the shortcut.
struct ShortcutRecorder: View {
    let action: Action
    @ObservedObject private var prefs = Preferences.shared
    @State private var recording = false
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        HStack(spacing: 6) {
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(size: 13, weight: recording ? .regular : .medium))
                    .foregroundStyle(recording ? Color.secondary : Color.primary)
                    .frame(minWidth: 96)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: recording ? 2 : 1))
            }
            .buttonStyle(.plain)
            .help(Text("Click, then press the new shortcut"))

            Button {
                prefs.setShortcut(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(Text("Remove shortcut"))
            .opacity(prefs.shortcut(for: action) != nil && !recording ? 1 : 0)
            .disabled(prefs.shortcut(for: action) == nil || recording)
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if recording {
            let symbols = Shortcut.symbols(for: liveModifiers)
            return symbols.isEmpty ? String(localized: "Press keys") : symbols
        }
        return prefs.shortcut(for: action)?.display ?? String(localized: "None")
    }

    private func toggleRecording() { recording ? stopRecording() : startRecording() }

    private func startRecording() {
        recording = true
        message = nil
        liveModifiers = []
        GlobalHotKey.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                liveModifiers = event.modifierFlags.intersection(Shortcut.relevantModifiers)
                return nil
            }
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let shortcut = Shortcut(event: event)
        let plain = shortcut.flags.isEmpty
        if plain && Int(event.keyCode) == 53 && action != .stop {
            stopRecording()
            return
        }
        if plain && (Int(event.keyCode) == 51 || Int(event.keyCode) == 117) {
            prefs.setShortcut(nil, for: action)
            stopRecording()
            return
        }
        if action.isGlobal && !shortcut.hasCommandLikeModifier {
            NSSound.beep()
            message = String(localized: "Add ⌘, ⌥ or ⌃")
            return
        }
        prefs.setShortcut(shortcut, for: action)
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { GlobalHotKey.shared.resume() }
        recording = false
        liveModifiers = []
    }
}
