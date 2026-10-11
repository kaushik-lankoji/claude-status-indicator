import Foundation

/// The coding agents the dock can show.
public enum Agent: String, Codable, CaseIterable, Sendable {
    case claude, codex

    public var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}
