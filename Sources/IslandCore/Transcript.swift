import Foundation

public enum Transcript {
    /// Who Codex routes approvals to in this session: "user", or "auto_review" when its own
    /// reviewer decides. Codex records it on every turn, so the newest mention wins.
    public static func approvalsReviewer(at path: String) -> String? {
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return nil }

        let key = Data("\"approvals_reviewer\":\"".utf8)
        let chunk: UInt64 = 1 << 20
        let overlap = UInt64(key.count + 32)
        var end = size
        // Long turns bury the turn's header under tool output, so walk back a megabyte at a time.
        while end > 0, size - end < 64 << 20 {
            let start = end > chunk ? end - chunk : 0
            guard (try? file.seek(toOffset: start)) != nil,
                  let data = try? file.read(upToCount: Int(end - start)) else { return nil }
            if let hit = data.range(of: key, options: .backwards) {
                let value = data[hit.upperBound...].prefix { $0 != UInt8(ascii: "\"") }
                if let text = String(data: value, encoding: .utf8), !text.isEmpty { return text }
            }
            if start == 0 { break }
            end = start + overlap
        }
        return nil
    }
}
