import Foundation
import IslandCore

// Called by Claude Code hooks with the event JSON on stdin.
// Must stay fast, print nothing, and always exit 0 so it never gets in Claude's way.

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
      let name = event["hook_event_name"] as? String,
      let sessionID = event["session_id"] as? String else { exit(0) }

let now = Date().timeIntervalSince1970

func string(_ key: String, in dict: [String: Any]? = event) -> String? {
    guard let value = dict?[key] as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// First meaningful line, clipped. Prose also loses its markdown.
func oneLine(_ text: String?, prose: Bool = false, limit: Int = 160) -> String? {
    guard let text else { return nil }
    let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: prose ? "#*>`-_" : ""))
    let lines = text.split(whereSeparator: \.isNewline)
    // In prose, a heading is a poor summary; prefer the first real sentence.
    let body = prose ? lines.first { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && $0.contains(where: \.isLetter) } : nil
    var line = (body.map { [$0] } ?? lines)
        .map { $0.trimmingCharacters(in: edges) }
        .first { !$0.isEmpty } ?? ""
    if prose {
        line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    }
    if line.isEmpty { return nil }
    return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
}

func summary(tool: String, input: [String: Any]?) -> String? {
    switch tool {
    case "Bash":
        return oneLine(string("command", in: input))
    case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit":
        return (string("file_path", in: input) ?? string("notebook_path", in: input))
            .map { ($0 as NSString).lastPathComponent }
    case "Grep", "Glob":
        return oneLine(string("pattern", in: input))
    case "WebFetch":
        return string("url", in: input).map { URL(string: $0)?.host ?? $0 }
    case "WebSearch":
        return oneLine(string("query", in: input))
    case "Task", "Agent":
        return oneLine(string("description", in: input))
    default:
        return nil
    }
}

func terminalBundleID() -> String? {
    let env = ProcessInfo.processInfo.environment
    if let id = env["__CFBundleIdentifier"], !id.isEmpty { return id }
    switch env["TERM_PROGRAM"] {
    case "Apple_Terminal": return "com.apple.Terminal"
    case "iTerm.app": return "com.googlecode.iterm2"
    case "WarpTerminal": return "dev.warp.Warp-Stable"
    case "vscode": return "com.microsoft.VSCode"
    case "ghostty": return "com.mitchellh.ghostty"
    default: return nil
    }
}

var wakeApp = false

Store.locked {
    if name == "SessionEnd" {
        Store.remove(sessionID)
        return
    }

    var s = Store.load(sessionID) ?? Session(id: sessionID, cwd: string("cwd") ?? "", now: now)
    s.updated = now
    if let cwd = string("cwd") { s.cwd = cwd }
    if let transcript = string("transcript_path") { s.transcript = transcript }
    if s.pid.map({ !Proc.isAlive($0) }) ?? true { s.pid = Proc.owningClaude() }
    if s.terminal == nil { s.terminal = terminalBundleID() }

    let tool = string("tool_name")
    let toolInput = event["tool_input"] as? [String: Any]

    func work() {
        if s.phase == .idle || s.phase == .done { s.turnStart = now }
        s.move(to: .working, at: now)
        s.clearActivity()
    }

    func attention(_ reason: String, detail: String?) {
        s.move(to: .attention, at: now)
        s.reason = reason
        s.detail = detail
        s.failed = nil
    }

    switch name {
    case "SessionStart":
        wakeApp = true
        if string("source") != "compact" {
            s.move(to: .idle, at: now)
            s.clearActivity()
        }

    case "UserPromptSubmit":
        wakeApp = true
        let continuing = (event["is_continuation"] as? Bool) == true && s.phase == .working
        if !continuing { s.turnStart = now }
        s.move(to: .working, at: now)
        s.clearActivity()

    case "PreToolUse":
        switch tool {
        case "AskUserQuestion":
            let questions = toolInput?["questions"] as? [[String: Any]]
            attention("question", detail: oneLine(string("question", in: questions?.first), prose: true))
            s.tool = tool
        case "ExitPlanMode":
            attention("plan", detail: nil)
            s.tool = tool
        default:
            work()
            s.tool = tool
            s.detail = tool.flatMap { summary(tool: $0, input: toolInput) }
        }

    case "PostToolUse", "PostToolUseFailure":
        work()

    case "Notification":
        switch string("notification_type") {
        case "permission_prompt":
            let asked = tool ?? s.tool
            let detail = asked == s.tool ? s.detail : nil
            attention("permission", detail: detail)
            s.tool = asked
        case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
            attention("input", detail: oneLine(string("message"), prose: true))
        case "elicitation_complete", "elicitation_response":
            if s.phase == .attention { work() }
        default:
            break
        }

    case "Stop":
        s.move(to: .done, at: now)
        s.clearActivity()
        s.detail = oneLine(string("last_assistant_message"), prose: true)

    case "StopFailure":
        s.move(to: .done, at: now)
        s.clearActivity()
        s.failed = true
        s.detail = oneLine(string("error_message"), prose: true) ?? string("error_type")

    default:
        break
    }

    Store.save(s)
}

// Bring the island up if it isn't running yet.
if wakeApp {
    let running = (try? String(contentsOf: Store.pidFile, encoding: .utf8))
        .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .flatMap { Proc.info($0) }?.name == "ClaudeIsland"
    let app = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent() // MacOS
        .deletingLastPathComponent() // Contents
        .deletingLastPathComponent() // Claude Island.app
    if !running, app.pathExtension == "app" {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", app.path]
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        try? open.run()
    }
}

exit(0)
