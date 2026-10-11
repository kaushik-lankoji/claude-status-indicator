import Foundation

public enum Proc {
    public static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public static func info(_ pid: pid_t) -> (parent: pid_t, name: String)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (info.kp_eproc.e_ppid, name)
    }

    /// Hooks run as `sh -c <command>` under the agent's process.
    /// Walk up past any shells to find the agent itself.
    public static func owningAgent() -> pid_t? {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env"]
        var pid = getppid()
        for _ in 0..<6 {
            guard pid > 1, let info = info(pid) else { return nil }
            let name = info.name.hasPrefix("-") ? String(info.name.dropFirst()) : info.name
            if !shells.contains(name) { return pid }
            pid = info.parent
        }
        return nil
    }

    /// Path of the running executable.
    public static func path(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The app a process lives in, found by walking up its parents until one is inside a `.app` bundle.
    /// This is how we know a Codex session belongs to the Codex app, or a Claude one to Warp.
    public static func hostApp(of pid: pid_t) -> String? {
        var current = pid
        for _ in 0..<12 {
            guard current > 1 else { return nil }
            if let path = path(current), let range = path.range(of: ".app/") {
                let bundle = String(path[..<range.lowerBound]) + ".app"
                if let id = Bundle(path: bundle)?.bundleIdentifier { return id }
            }
            guard let parent = info(current)?.parent else { return nil }
            current = parent
        }
        return nil
    }
}
