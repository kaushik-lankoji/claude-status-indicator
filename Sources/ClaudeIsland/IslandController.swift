import AppKit
import SwiftUI
import IslandCore

/// A borderless panel pinned over the notch. It never takes focus, and only
/// catches the mouse while the pointer is actually over the island.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Allow sitting over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class IslandHostingView: NSHostingView<IslandView> {
    var menuProvider: (() -> NSMenu)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class IslandController: NSObject {
    private let model = IslandModel()
    private let monitor = SessionMonitor()
    private let panel = IslandPanel()
    private var hosting: IslandHostingView!
    private var screen: NSScreen?

    private var pointerTimer: Timer?
    private var enteredAt: Date?
    private var leftAt: Date?
    private var popoutTask: DispatchWorkItem?

    private static let canvas = CGSize(width: 400, height: 560)

    private var soundOn: Bool {
        get { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sound") }
    }

    func start() {
        hosting = IslandHostingView(rootView: IslandView(model: model, actions: IslandActions(
            open: { [weak self] in self?.open($0) },
            decide: { [weak self] in self?.decide($0, $1) })))
        hosting.menuProvider = { [weak self] in self?.menu() ?? NSMenu() }
        panel.contentView = hosting
        place(force: true)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)

        monitor.onUpdate = { [weak self] sessions, changed in self?.update(sessions, changed) }
        monitor.start()
    }

    // MARK: Placement

    @objc private func screensChanged() { place(force: true) }

    /// Sit on whichever display you're working on.
    private func place(force: Bool = false) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        guard force || screen != self.screen else { return }
        self.screen = screen
        model.metrics = Metrics.of(screen)
        let size = Self.canvas
        let x = model.metrics.left.map { $0 - IslandView.shadowRoom } ?? screen.frame.midX - size.width / 2
        panel.setFrame(NSRect(x: x, y: screen.frame.maxY - size.height, width: size.width, height: size.height),
                       display: true)
    }

    // MARK: State

    private func update(_ sessions: [Session], _ changed: [Session]) {
        if !model.hovering { place() }
        model.sessions = sessions
        trackPointer(sessions.isEmpty == false)

        if changed.contains(where: { $0.phase == .attention }) {
            play("Ping")
        }
        // Looking at the terminal already? Claude Code's own prompt is right there, so don't hold it back.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for s in changed where s.request != nil && s.terminal != nil && s.terminal == front {
            decide(s, .terminal)
        }

        let finished = changed.filter { $0.phase == .done }
        if !finished.isEmpty {
            play(finished.contains { $0.failed == true } ? "Funk" : "Glass")
            popOut()
            // Already looking at the terminal? Then a moment on screen is enough.
            for s in finished where s.terminal != nil && s.terminal == front {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.acknowledge(s, onlyIfSince: s.since)
                }
            }
        }
    }

    private func popOut() {
        popoutTask?.cancel()
        model.popout = true
        let task = DispatchWorkItem { [weak self] in self?.model.popout = false }
        popoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: task)
    }

    private func acknowledge(_ s: Session, onlyIfSince since: Double? = nil) {
        guard let current = model.sessions.first(where: { $0.id == s.id }), current.phase == .done,
              since == nil || current.since == since else { return }
        monitor.acknowledge(s.id)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let id = app.bundleIdentifier else { return }
        if !model.hovering { place() }
        for s in model.sessions where s.terminal == id {
            if s.phase == .done { acknowledge(s) }
            if s.request != nil { decide(s, .terminal) }
        }
    }

    /// Answer a held permission prompt. `.terminal` hands it back to Claude Code's own prompt.
    private func decide(_ s: Session, _ verdict: Store.Verdict) {
        guard let request = s.request else { return }
        Store.decide(request.id, verdict)
        // Show the new state at once; the hook confirms it a moment later.
        Store.update(s.id) { latest in
            guard latest.request?.id == request.id else { return }
            latest.request = nil
            if verdict != .terminal {
                latest.move(to: .working, at: Date().timeIntervalSince1970)
                latest.clearActivity()
            }
        }
        monitor.refresh()
    }

    /// Jump to the terminal the session lives in.
    private func open(_ s: Session) {
        if s.phase == .done { acknowledge(s) }
        if s.request != nil { decide(s, .terminal) }
        guard let id = s.terminal,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private func play(_ name: String) {
        guard soundOn, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.5
        sound.play()
    }

    // MARK: Pointer

    /// Polls the pointer while the island is up: lets clicks through everywhere
    /// except the island itself, and expands it on hover.
    private func trackPointer(_ on: Bool) {
        if on, pointerTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.pointerMoved() }
            RunLoop.main.add(timer, forMode: .common)
            pointerTimer = timer
        } else if !on, let timer = pointerTimer {
            timer.invalidate()
            pointerTimer = nil
            panel.ignoresMouseEvents = true
            model.hovering = false
            enteredAt = nil
            leftAt = nil
        }
    }

    private func pointerMoved() {
        guard let screen else { return }
        let size = model.size
        let island = NSRect(x: model.metrics.left ?? screen.frame.midX - size.width / 2,
                            y: screen.frame.maxY - model.metrics.inset - size.height,
                            width: size.width, height: size.height).insetBy(dx: -6, dy: -6)
        let inside = island.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        let now = Date()
        if inside {
            leftAt = nil
            if !model.hovering {
                enteredAt = enteredAt ?? now
                if now.timeIntervalSince(enteredAt!) > 0.15 { model.hovering = true }
            }
        } else {
            enteredAt = nil
            if model.hovering {
                leftAt = leftAt ?? now
                if now.timeIntervalSince(leftAt!) > 0.3 { model.hovering = false }
            }
        }
    }

    // MARK: Menu

    private func menu() -> NSMenu {
        let menu = NSMenu()
        let sound = NSMenuItem(title: "Sounds", action: #selector(toggleSound), keyEquivalent: "")
        sound.target = self
        sound.state = soundOn ? .on : .off
        menu.addItem(sound)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Claude Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleSound() { soundOn.toggle() }
}
