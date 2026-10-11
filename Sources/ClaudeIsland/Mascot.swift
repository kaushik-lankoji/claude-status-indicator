import AppKit
import SwiftUI
import IslandCore

extension Agent {
    var color: Color {
        switch self {
        case .claude: return Color(red: 0.843, green: 0.467, blue: 0.341)
        case .codex: return Color(red: 0.47, green: 0.56, blue: 1.0)
        }
    }
}

/// Each agent's little mascot, drawn as a 16-column pixel sprite.
///
/// Clawd (Claude Code):            Codex, a cloud with its prompt:
///     ..############..                ...####..####...
///     ..############..                ..############..
///     ..##.######.##..    eyes        .##.##########.#.     the `>` and `_`
///     ..##.######.##..                ################      are cut out so the
///     ################    arms        ###..###########      dock shows through
///     ..############..                ################
///     ..############..                .##############.
///     ...#.#....#.#...    legs        ..############..
///     ...#.#....#.#...                ...##########...
///
/// Frames are pre-rendered and swapped on a Core Animation layer, so animating
/// them costs next to nothing; redrawing through SwiftUI every beat did not.
struct Mascot: NSViewRepresentable {
    var agent: Agent
    var phase: Phase
    var since: Double
    var pixel: CGFloat
    var animating: Bool

    static let columns = 16
    static let rows = 11 // 9 for the body, 2 of headroom for hopping

    static func width(pixel: CGFloat) -> CGFloat { CGFloat(columns) * pixel }

    func makeNSView(context: Context) -> SpriteView { SpriteView() }

    func updateNSView(_ view: SpriteView, context: Context) {
        view.configure(agent: agent, phase: phase, since: since, pixel: pixel, animating: animating)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpriteView, context: Context) -> CGSize? {
        CGSize(width: Self.width(pixel: pixel), height: CGFloat(Self.rows) * pixel)
    }

    final class SpriteView: NSView {
        private let sprite = CALayer()
        private var timer: Timer?
        private var agent = Agent.claude
        private var phase = Phase.idle
        private var since = 0.0
        private var pixel: CGFloat = 2
        private var frames: [Frame: CGImage] = [:]
        private var shown: Frame?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            sprite.magnificationFilter = .nearest
            sprite.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(sprite)
        }

        required init?(coder: NSCoder) { fatalError() }

        func configure(agent: Agent, phase: Phase, since: Double, pixel: CGFloat, animating: Bool) {
            if pixel != self.pixel { frames = [:] }
            self.agent = agent
            self.phase = phase
            self.since = since
            self.pixel = pixel
            draw()
            let wanted = animating && phase != .idle
            if wanted, timer == nil {
                let timer = Timer(timeInterval: 1.0 / 8, repeats: true) { [weak self] _ in self?.draw() }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            } else if !wanted, let timer {
                timer.invalidate()
                self.timer = nil
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            frames = [:]
            shown = nil
            draw()
        }

        override func layout() {
            super.layout()
            sprite.frame = bounds
        }

        private func draw() {
            let now = Date().timeIntervalSince1970
            let frame = Frame(agent: agent, phase: phase, tick: Int(now * 8), elapsed: now - since)
            guard frame != shown else { return }
            shown = frame
            sprite.contents = image(for: frame)
            sprite.contentsScale = window?.backingScaleFactor ?? 2
        }

        private func image(for frame: Frame) -> CGImage? {
            if let cached = frames[frame] { return cached }
            let scale = window?.backingScaleFactor ?? 2
            let unit = pixel * scale
            let width = Int((CGFloat(Mascot.columns) * unit).rounded())
            let height = Int((CGFloat(Mascot.rows) * unit).rounded())
            guard let gc = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            gc.setFillColor(NSColor(frame.agent.color).cgColor)
            let top = 2 - frame.hop
            for (x, y) in frame.cells {
                // CoreGraphics counts rows from the bottom.
                let row = Mascot.rows - 1 - (y + top)
                gc.fill(CGRect(x: CGFloat(x) * unit, y: CGFloat(row) * unit, width: unit, height: unit))
            }
            let image = gc.makeImage()
            frames[frame] = image
            return image
        }
    }

    /// One drawable pose of one mascot. Hashable so frames can be cached.
    struct Frame: Hashable {
        let agent: Agent
        let hop: Int
        private let clawd: Clawd
        private let codex: Codex

        init(agent: Agent, phase: Phase, tick: Int, elapsed: Double) {
            self.agent = agent
            switch agent {
            case .claude:
                clawd = Clawd(phase: phase, tick: tick, elapsed: elapsed)
                codex = Codex(phase: .idle, tick: 0, elapsed: 0)
                hop = clawd.hop
            case .codex:
                clawd = Clawd(phase: .idle, tick: 0, elapsed: 0)
                codex = Codex(phase: phase, tick: tick, elapsed: elapsed)
                hop = codex.hop
            }
        }

        var cells: [(Int, Int)] { agent == .claude ? clawd.cells : codex.cells }
    }

    struct Clawd: Hashable {
        enum Arms { case down, up }
        enum Legs { case planted, liftLeft, liftRight }

        var arms = Arms.down
        var legs = Legs.planted
        var eyesClosed = false
        var hop = 0

        init(phase: Phase, tick: Int, elapsed: Double) {
            let blink = tick % 30 == 0
            switch phase {
            case .working:
                // Scuttle in place.
                switch (tick / 2) % 4 {
                case 0: legs = .liftLeft
                case 2: legs = .liftRight
                default: break
                }
                eyesClosed = blink
            case .attention:
                // Hop, then wave both arms, on a one-second loop.
                let step = tick % 8
                hop = [1, 2, 1, 0, 0, 0, 0, 0][step]
                arms = [.up, .up, .up, .down, .up, .down, .up, .down][step]
            case .done:
                // One happy hop, then rest.
                if elapsed < 1.25 {
                    let step = min(Int(elapsed * 8), 9)
                    hop = [0, 1, 2, 2, 1, 0, 0, 0, 0, 0][step]
                    arms = step < 8 ? .up : .down
                    eyesClosed = true
                } else {
                    eyesClosed = blink
                }
            case .idle:
                break
            }
        }

        var cells: [(Int, Int)] {
            var cells: [(Int, Int)] = []
            for y in 0...6 {
                for x in 2...13 {
                    let eye = (x == 4 || x == 11) && (y == 3 || (y == 2 && !eyesClosed))
                    if !eye { cells.append((x, y)) }
                }
            }
            switch arms {
            case .down: cells += [(0, 4), (1, 4), (14, 4), (15, 4)]
            case .up: cells += [(0, 2), (1, 3), (14, 3), (15, 2)]
            }
            for x in [3, 5, 10, 12] {
                cells.append((x, 7))
                let lifted = (legs == .liftLeft && (x == 3 || x == 10)) || (legs == .liftRight && (x == 5 || x == 12))
                if !lifted { cells.append((x, 8)) }
            }
            return cells
        }
    }

    /// A cloud with the Codex prompt cut into it. It floats while working, flashes `!` when it needs you,
    /// and shows a check when it's done.
    struct Codex: Hashable {
        enum Face { case prompt, alert, check }

        var face = Face.prompt
        var cursor = true
        var hop = 0

        init(phase: Phase, tick: Int, elapsed: Double) {
            switch phase {
            case .working:
                // Bob gently while the cursor types.
                hop = (tick / 4) % 2
                cursor = tick % 4 < 2
            case .attention:
                let step = tick % 8
                hop = [1, 2, 1, 0, 0, 0, 0, 0][step]
                face = .alert
            case .done:
                if elapsed < 1.25 {
                    let step = min(Int(elapsed * 8), 9)
                    hop = [0, 1, 2, 2, 1, 0, 0, 0, 0, 0][step]
                    face = .check
                } else {
                    cursor = tick % 16 < 8
                }
            case .idle:
                break
            }
        }

        private static let rows: [ClosedRange<Int>] = [
            3...12, 2...13, 1...14, 0...15, 0...15, 0...15, 1...14, 2...13, 3...12,
        ]

        private var holes: Set<[Int]> {
            switch face {
            case .prompt:
                var cells = [[4, 2], [5, 3], [6, 4], [5, 5], [4, 6]]
                if cursor { cells += [[8, 6], [9, 6], [10, 6], [11, 6]] }
                return Set(cells)
            case .alert:
                return [[7, 2], [8, 2], [7, 3], [8, 3], [7, 4], [8, 4], [7, 6], [8, 6]]
            case .check:
                return [[4, 4], [5, 5], [6, 6], [7, 5], [8, 4], [9, 3], [10, 2]]
            }
        }

        var cells: [(Int, Int)] {
            let holes = holes
            var cells: [(Int, Int)] = []
            for (y, span) in Self.rows.enumerated() {
                for x in span where !holes.contains([x, y]) {
                    // Two humps on top instead of one flat edge.
                    if y == 0, x == 7 || x == 8 { continue }
                    cells.append((x, y))
                }
            }
            return cells
        }
    }
}
