import AppKit
import IslandCore

struct Metrics: Equatable {
    var notchWidth: CGFloat
    var barHeight: CGFloat
    var hasNotch: Bool
    var scale: CGFloat = 2

    static let ear: CGFloat = 7
    static let rowHeight: CGFloat = 46
    static let panelWidth: CGFloat = 360

    /// Lands on whole device pixels so Clawd stays crisp.
    var pixel: CGFloat { scale >= 2 && barHeight < 30 ? 1.5 : 2 }
    var wing: CGFloat { CGFloat(Clawd.columns) * pixel + 22 }

    static func of(_ screen: NSScreen) -> Metrics {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return Metrics(notchWidth: screen.frame.width - left.width - right.width,
                           barHeight: screen.safeAreaInsets.top, hasNotch: true,
                           scale: screen.backingScaleFactor)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return Metrics(notchWidth: 0, barHeight: max(menuBar, 24), hasNotch: false,
                       scale: screen.backingScaleFactor)
    }
}

final class IslandModel: ObservableObject {
    /// Non-idle sessions, most urgent first.
    @Published var sessions: [Session] = [] {
        didSet { if let first = sessions.first { lastShown = first } }
    }
    @Published var hovering = false
    @Published var popout = false
    @Published var metrics = Metrics(notchWidth: 0, barHeight: 24, hasNotch: false)

    /// Keeps the last session on screen while the island fades away.
    private(set) var lastShown: Session?

    var primary: Session? { sessions.first }
    var shown: Session? { primary ?? lastShown }
    var isVisible: Bool { primary != nil }

    var isExpanded: Bool {
        guard let primary else { return false }
        return hovering || popout || primary.phase == .attention
    }

    var rows: [Session] {
        guard isExpanded, let primary else { return [] }
        return hovering ? Array(sessions.prefix(4)) : [primary]
    }

    var compactWidth: CGFloat {
        metrics.notchWidth + 2 * metrics.wing + 2 * Metrics.ear + (metrics.hasNotch ? 0 : 8)
    }

    var size: CGSize {
        guard isVisible else {
            let width = metrics.hasNotch ? metrics.notchWidth + 2 * Metrics.ear : compactWidth * 0.6
            return CGSize(width: width, height: metrics.barHeight)
        }
        guard isExpanded else { return CGSize(width: compactWidth, height: metrics.barHeight) }
        return CGSize(width: max(compactWidth, Metrics.panelWidth + 2 * Metrics.ear),
                      height: metrics.barHeight + CGFloat(rows.count) * Metrics.rowHeight + 8)
    }

    var cornerRadius: CGFloat {
        isExpanded ? 22 : min(14, metrics.barHeight * 0.42)
    }
}
