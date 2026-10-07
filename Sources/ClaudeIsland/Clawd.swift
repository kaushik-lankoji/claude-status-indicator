import AppKit
import SwiftUI
import IslandCore

/// Clawd, the little Claude Code critter, drawn as a 16×9 pixel sprite.
///
///     ..############..
///     ..############..
///     ..##.######.##..    eyes
///     ..##.######.##..
///     ################    arms
///     ..############..
///     ..############..
///     ...#.#....#.#...    legs
///     ...#.#....#.#...
///
/// Frames are pre-rendered and swapped on a Core Animation layer, so animating
/// him costs next to nothing; redrawing through SwiftUI every beat did not.
struct Clawd: NSViewRepresentable {
    var phase: Phase
    var since: Double
    var pixel: CGFloat
    var animating: Bool

    static let color = Color(red: 0.843, green: 0.467, blue: 0.341)
    static let columns = 16
    static let rows = 11 // 9 for the body, 2 of headroom for hopping

    func makeNSView(context: Context) -> SpriteView { SpriteView() }

    func updateNSView(_ view: SpriteView, context: Context) {
        view.configure(phase: phase, since: since, pixel: pixel, animating: animating)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpriteView, context: Context) -> CGSize? {
        CGSize(width: CGFloat(Self.columns) * pixel, height: CGFloat(Self.rows) * pixel)
    }

    final class SpriteView: NSView {
        private let sprite = CALayer()
        private var timer: Timer?
        private var phase = Phase.idle
        private var since = 0.0
        private var pixel: CGFloat = 2
        private var frames: [Pose: CGImage] = [:]
        private var shown: Pose?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            sprite.magnificationFilter = .nearest
            sprite.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
            layer?.addSublayer(sprite)
        }

        required init?(coder: NSCoder) { fatalError() }

        func configure(phase: Phase, since: Double, pixel: CGFloat, animating: Bool) {
            if pixel != self.pixel { frames = [:] }
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
            let pose = Pose(phase: phase, tick: Int(now * 8), elapsed: now - since)
            guard pose != shown else { return }
            shown = pose
            sprite.contents = image(for: pose)
            sprite.contentsScale = window?.backingScaleFactor ?? 2
        }

        private func image(for pose: Pose) -> CGImage? {
            if let cached = frames[pose] { return cached }
            let scale = window?.backingScaleFactor ?? 2
            let unit = pixel * scale
            let width = Int((CGFloat(Clawd.columns) * unit).rounded())
            let height = Int((CGFloat(Clawd.rows) * unit).rounded())
            guard let gc = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            gc.setFillColor(NSColor(Clawd.color).cgColor)
            let top = 2 - pose.hop
            for (x, y) in pose.cells {
                // CoreGraphics counts rows from the bottom.
                let row = Clawd.rows - 1 - (y + top)
                gc.fill(CGRect(x: CGFloat(x) * unit, y: CGFloat(row) * unit, width: unit, height: unit))
            }
            let image = gc.makeImage()
            frames[pose] = image
            return image
        }
    }

    struct Pose: Hashable {
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
}
