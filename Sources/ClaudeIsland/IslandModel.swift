import AppKit
import IslandCore

struct Metrics: Equatable {
    /// Height of the dock's top row, which sits inside the menu bar.
    var header: CGFloat
    /// Gap above it that centres it in the menu bar.
    var inset: CGFloat
    /// Screen x of the dock's left edge when it sits beside the notch; nil means centred on the screen.
    var left: CGFloat?
    var scale: CGFloat

    static let expandedWidth: CGFloat = 320
    static let moreHeight: CGFloat = 24
    static let maxRows = 4

    /// Lands on whole device pixels so Clawd stays crisp.
    var pixel: CGFloat { scale >= 2 ? 1.5 : 2 }

    static func rowHeight(_ s: Session) -> CGFloat { s.phase == .attention ? 92 : 48 }

    static func of(_ screen: NSScreen) -> Metrics {
        let notch = screen.safeAreaInsets.top
        let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, notch, 24)
        let header = min(26, max(22, bar - 6))
        var left: CGFloat?
        if notch > 0, let right = screen.auxiliaryTopRightArea {
            left = screen.frame.maxX - right.width + 10 // just right of the camera housing
        }
        return Metrics(header: header, inset: (bar - header) / 2, left: left, scale: screen.backingScaleFactor)
    }
}

final class IslandModel: ObservableObject {
    /// Non-idle sessions, most urgent first.
    @Published var sessions: [Session] = [] {
        didSet { if !sessions.isEmpty { lastCount = sessions.count } }
    }
    @Published var hovering = false
    @Published var popout = false
    @Published var metrics = Metrics(header: 26, inset: 3, left: nil, scale: 2)

    /// Keeps the dock's width steady while it fades away.
    private var lastCount = 1

    var primary: Session? { sessions.first }
    var isVisible: Bool { primary != nil }

    private var needsYou: [Session] { sessions.filter { $0.phase == .attention } }

    var isExpanded: Bool {
        isVisible && (hovering || popout || !needsYou.isEmpty)
    }

    /// Hovering shows everything; otherwise only what needs you, or the session that just finished.
    private var wanted: [Session] {
        if hovering { return sessions }
        if !needsYou.isEmpty { return needsYou }
        return popout ? Array(sessions.prefix(1)) : []
    }

    var rows: [Session] { isExpanded ? Array(wanted.prefix(Metrics.maxRows)) : [] }
    var hiddenCount: Int { isExpanded ? max(0, wanted.count - Metrics.maxRows) : 0 }

    private var compactWidth: CGFloat {
        let count = sessions.isEmpty ? lastCount : sessions.count
        let status: CGFloat = count > 1 ? CGFloat(min(count, 4)) * 11 + 4 : 40
        return 12 + CGFloat(Clawd.columns) * metrics.pixel + 10 + status + 12
    }

    var size: CGSize {
        guard isVisible else { return CGSize(width: compactWidth * 0.6, height: metrics.header) }
        guard isExpanded else { return CGSize(width: compactWidth, height: metrics.header) }
        let body = rows.reduce(0) { $0 + Metrics.rowHeight($1) }
        let more = hiddenCount > 0 ? Metrics.moreHeight : 0
        return CGSize(width: Metrics.expandedWidth, height: metrics.header + body + more + 6)
    }

    var cornerRadius: CGFloat { isExpanded ? 20 : metrics.header / 2 }
}
