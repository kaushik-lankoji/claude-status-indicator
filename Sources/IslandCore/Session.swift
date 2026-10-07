import Foundation

public enum Phase: String, Codable, Sendable {
    case idle, working, attention, done
}

/// One Claude Code session, as last reported by its hooks.
public struct Session: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var phase: Phase
    public var cwd: String
    public var transcript: String?
    /// The `claude` process that owns this session.
    public var pid: Int32?
    /// Bundle id of the app hosting the terminal (Warp, Terminal, iTerm, VS Code...).
    public var terminal: String?
    /// When the current phase began.
    public var since: Double
    /// When a hook last touched this session.
    public var updated: Double
    /// When the current turn (prompt) began.
    public var turnStart: Double?
    /// Tool being run, or waiting for approval.
    public var tool: String?
    /// Short human detail: a command, a file name, a question, a summary.
    public var detail: String?
    /// Why attention is needed: permission, question, plan, input.
    public var reason: String?
    /// The turn ended on an API error rather than finishing.
    public var failed: Bool?

    public init(id: String, cwd: String, now: Double) {
        self.id = id
        self.phase = .idle
        self.cwd = cwd
        self.since = now
        self.updated = now
    }

    public var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "Claude" : name
    }

    public mutating func move(to phase: Phase, at now: Double) {
        if self.phase != phase {
            self.phase = phase
            since = now
        }
    }

    public mutating func clearActivity() {
        tool = nil
        detail = nil
        reason = nil
        failed = nil
    }
}
