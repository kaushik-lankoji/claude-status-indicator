import AppKit
import IslandCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = IslandController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let me = NSRunningApplication.current
        let twins = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if twins.contains(where: { $0.processIdentifier != me.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        Store.prepare()
        try? String(getpid()).write(to: Store.pidFile, atomically: true, encoding: .utf8)
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if (try? String(contentsOf: Store.pidFile, encoding: .utf8)) == String(getpid()) {
            try? FileManager.default.removeItem(at: Store.pidFile)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
