import Foundation

/// Sessions live as small JSON files in ~/.claude-island/sessions.
/// Hooks write them, the app watches the folder. Writes are atomic and serialized with a lock.
public enum Store {
    public static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-island", isDirectory: true)
    public static let sessionsDir = root.appendingPathComponent("sessions", isDirectory: true)
    public static let decisionsDir = root.appendingPathComponent("decisions", isDirectory: true)
    public static let pidFile = root.appendingPathComponent("app.pid")

    public static func prepare() {
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: decisionsDir, withIntermediateDirectories: true)
    }

    public static func locked<T>(_ body: () throws -> T) rethrows -> T {
        prepare()
        let fd = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        return try body()
    }

    public static func load(_ id: String) -> Session? {
        guard let url = url(for: id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public static func save(_ session: Session) {
        guard let dst = url(for: session.id),
              let data = try? JSONEncoder().encode(session) else { return }
        let tmp = sessionsDir.appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp)
            if rename(tmp.path, dst.path) != 0 {
                try? FileManager.default.removeItem(at: tmp)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    public static func remove(_ id: String) {
        guard let url = url(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public static func all() -> [Session] {
        let files = (try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return files.compactMap { url in
            guard url.pathExtension == "json", !url.lastPathComponent.hasPrefix("."),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Session.self, from: data)
        }
    }

    /// Read-modify-write a session under the lock. No-op if it no longer exists.
    public static func update(_ id: String, _ body: (inout Session) -> Void) {
        locked {
            guard var session = load(id) else { return }
            body(&session)
            save(session)
        }
    }

    // MARK: Decisions

    /// How the dock answered a permission prompt. `terminal` hands it back to Claude Code's own prompt.
    public enum Verdict: String, Codable, Sendable {
        case allow, deny, terminal
    }

    public static func decide(_ requestID: String, _ verdict: Verdict) {
        guard let dst = decisionURL(requestID), let data = try? JSONEncoder().encode(verdict) else { return }
        prepare()
        let tmp = decisionsDir.appendingPathComponent(".\(UUID().uuidString).tmp")
        guard (try? data.write(to: tmp)) != nil else { return }
        if rename(tmp.path, dst.path) != 0 { try? FileManager.default.removeItem(at: tmp) }
    }

    public static func decision(for requestID: String) -> Verdict? {
        guard let url = decisionURL(requestID), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Verdict.self, from: data)
    }

    public static func discardDecision(for requestID: String) {
        if let url = decisionURL(requestID) { try? FileManager.default.removeItem(at: url) }
    }

    private static func url(for id: String) -> URL? { file(in: sessionsDir, id) }

    private static func decisionURL(_ id: String) -> URL? { file(in: decisionsDir, id) }

    private static func file(in dir: URL, _ id: String) -> URL? {
        let safe = id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return safe.isEmpty ? nil : dir.appendingPathComponent(safe + ".json")
    }
}
