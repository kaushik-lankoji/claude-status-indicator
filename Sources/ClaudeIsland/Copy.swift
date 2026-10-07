import Foundation
import IslandCore

/// The words the island shows for a session.
extension Session {
    var headline: String {
        switch phase {
        case .working:
            switch tool {
            case nil: return "Thinking"
            case "Bash": return "Running a command"
            case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing"
            case "Read": return "Reading"
            case "Grep", "Glob": return "Searching"
            case "WebFetch", "WebSearch": return "Looking it up"
            case "Task", "Agent": return "Running an agent"
            case "TodoWrite": return "Planning"
            case let tool?: return "Using \(Self.pretty(tool))"
            }
        case .attention:
            switch reason {
            case "question": return "Claude has a question"
            case "plan": return "Plan ready for review"
            case "input": return "Needs your input"
            default:
                switch tool {
                case "Bash": return "Run this command?"
                case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Edit this file?"
                case "WebFetch": return "Open this site?"
                case let tool?: return "Allow \(Self.pretty(tool))?"
                case nil: return "Needs your approval"
                }
            }
        case .done:
            if failed == true { return "Stopped" }
            if let start = turnStart, since - start >= 1 {
                return "Done in \(Self.duration(since - start))"
            }
            return "Done"
        case .idle:
            return project
        }
    }

    var subline: String? {
        if let detail { return detail }
        switch phase {
        case .attention: return "Waiting in the terminal"
        case .done: return failed == true ? "Something went wrong" : nil
        default: return nil
        }
    }

    static func pretty(_ tool: String) -> String {
        // mcp__server__tool_name → "tool name"
        let name = tool.hasPrefix("mcp__") ? (tool.components(separatedBy: "__").last ?? tool) : tool
        return name.replacingOccurrences(of: "_", with: " ")
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
