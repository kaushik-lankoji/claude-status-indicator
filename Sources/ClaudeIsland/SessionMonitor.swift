import Foundation
import IslandCore

/// Watches the session folder and keeps it honest: sessions whose claude
/// process is gone are dropped, and interrupted turns (Esc) go back to idle,
/// since Claude Code fires no hook for those.
final class SessionMonitor {
    /// Active (non-idle) sessions, most urgent first, plus the ones that just changed phase.
    var onUpdate: (([Session], [Session]) -> Void)?

    private var known: [String: [String]] = [:]
    private var loaded = false
    private var lastActive: [Session] = []
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var reloadQueued = false
    private var transcriptChecks: [String: (Date, Double)] = [:]

    func start() {
        Store.prepare()
        let fd = open(Store.sessionsDir.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleReload() }
            source.setCancelHandler { close(fd) }
            source.resume()
            self.source = source
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sweep() }
        sweep()
        reload()
    }

    /// The person has seen a finished session.
    func acknowledge(_ id: String) {
        Store.update(id) { s in
            guard s.phase == .done else { return }
            s.move(to: .idle, at: Date().timeIntervalSince1970)
            s.clearActivity()
        }
        reload()
    }

    /// What counts as a change worth announcing: a new phase, or a new prompt within one.
    private static func key(_ s: Session) -> [String] {
        [s.phase.rawValue, String(s.since), s.request?.id ?? ""]
    }

    func refresh() { reload() }

    private func scheduleReload() {
        guard !reloadQueued else { return }
        reloadQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.reloadQueued = false
            self?.reload()
        }
    }

    private func reload() {
        let all = Store.all()
        var changed: [Session] = []
        if loaded {
            for s in all where s.phase != .idle {
                if known[s.id] == Self.key(s) { continue }
                changed.append(s)
            }
        }
        known = Dictionary(all.map { ($0.id, Self.key($0)) }, uniquingKeysWith: { a, _ in a })
        let active = all.filter { $0.phase != .idle }.sorted(by: Self.urgency)
        guard !loaded || active != lastActive || !changed.isEmpty else { return }
        loaded = true
        lastActive = active
        onUpdate?(active, changed)
    }

    private static func urgency(_ a: Session, _ b: Session) -> Bool {
        func rank(_ s: Session) -> Int {
            switch s.phase {
            case .attention: return 0
            case .done: return 1
            case .working: return 2
            case .idle: return 3
            }
        }
        return rank(a) != rank(b) ? rank(a) < rank(b) : a.since > b.since
    }

    private func sweep() {
        let now = Date().timeIntervalSince1970
        for s in Store.all() {
            let gone = s.pid.map { !Proc.isAlive($0) } ?? (now - s.updated > 6 * 3600)
            if gone {
                Store.locked {
                    if Store.load(s.id)?.updated == s.updated { Store.remove(s.id) }
                }
                transcriptChecks[s.id] = nil
                continue
            }
            if (s.phase == .working || s.phase == .attention), wasInterrupted(s) {
                Store.update(s.id) { latest in
                    guard latest.updated == s.updated else { return }
                    latest.move(to: .idle, at: now)
                    latest.clearActivity()
                }
            }
        }
        reload()
    }

    /// Esc leaves a "[Request interrupted by user]" entry as the last message in the transcript.
    private func wasInterrupted(_ s: Session) -> Bool {
        guard let path = s.transcript,
              let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        else { return false }
        if let last = transcriptChecks[s.id], last == (modified, s.updated) { return false }
        transcriptChecks[s.id] = (modified, s.updated)

        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        let window: UInt64 = 128 * 1024
        handle.seek(toFileOffset: size > window ? size - window : 0)
        let tail = handle.readDataToEndOfFile()

        let lines = tail.split(separator: UInt8(ascii: "\n"))
        for line in lines.reversed() {
            guard let entry = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = entry["type"] as? String, type == "user" || type == "assistant",
                  (entry["isSidechain"] as? Bool) != true else { continue }
            guard type == "user",
                  String(decoding: line, as: UTF8.self).contains("[Request interrupted by user") else { return false }
            // Only an interrupt from this turn counts, not one left over from the last.
            let stamp = (entry["timestamp"] as? String).flatMap(Self.parseDate)?.timeIntervalSince1970 ?? 0
            return stamp > (s.turnStart ?? s.since)
        }
        return false
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
