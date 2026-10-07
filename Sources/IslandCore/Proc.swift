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

    /// Hooks run as `sh -c <command>` under the claude process.
    /// Walk up past any shells to find claude itself.
    public static func owningClaude() -> pid_t? {
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
}
