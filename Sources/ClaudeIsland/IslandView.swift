import SwiftUI
import IslandCore

extension Color {
    static let doneGreen = Color(red: 0.42, green: 0.80, blue: 0.53)
    static let failRed = Color(red: 0.93, green: 0.42, blue: 0.38)
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    var open: (Session) -> Void

    var body: some View {
        let size = model.size
        let shape = IslandShape(ear: Metrics.ear, radius: model.cornerRadius)
        let calling = model.primary?.phase == .attention

        ZStack(alignment: .top) {
            if calling {
                Glow(shape: shape).transition(.opacity)
            }
            shape.fill(Color.black)
                .shadow(color: .black.opacity(model.isExpanded ? 0.25 : 0), radius: 12, y: 6)
            content(width: size.width)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .opacity(model.isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: size)
        .animation(.easeInOut(duration: 0.3), value: calling)
    }

    private func content(width: CGFloat) -> some View {
        let m = model.metrics
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let s = model.shown {
                    Clawd(phase: s.phase, since: s.since, pixel: m.pixel, animating: model.isVisible)
                        .offset(y: -m.pixel) // centre the standing body, not the hop headroom
                        .frame(width: m.wing)
                    Spacer(minLength: 0)
                    Indicator(session: s)
                        .frame(width: m.wing)
                }
            }
            .frame(width: max(0, width - 2 * Metrics.ear), height: m.barHeight)
            .contentShape(Rectangle())
            .onTapGesture { if let s = model.primary { open(s) } }

            if model.isExpanded {
                VStack(spacing: 0) {
                    ForEach(model.rows) { s in
                        SessionRow(session: s, showsDot: model.rows.count > 1)
                            .onTapGesture { open(s) }
                    }
                }
                .frame(width: Metrics.panelWidth)
                .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Right-hand wing: a clock while working, a heartbeat when Claude needs you, a check when done.
private struct Indicator: View {
    let session: Session

    var body: some View {
        ZStack {
            mark
                .id(session.phase)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: session.phase)
    }

    @ViewBuilder private var mark: some View {
        switch session.phase {
        case .working:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Session.clock(context.date.timeIntervalSince1970 - (session.turnStart ?? session.since)))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .attention:
            PulseDot()
        case .done:
            Image(systemName: session.failed == true ? "exclamationmark" : "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(session.failed == true ? Color.failRed : Color.doneGreen)
        case .idle:
            EmptyView()
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let showsDot: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showsDot {
                Circle().fill(dotColor).frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let sub = session.subline {
                    Text(sub)
                        .font(session.tool == "Bash" && session.detail != nil
                              ? .system(size: 11.5, design: .monospaced)
                              : .system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            Text(session.project)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .trailing)
                .fixedSize(horizontal: session.project.count < 16, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, 18)
        .frame(height: Metrics.rowHeight)
        .contentShape(Rectangle())
    }

    private var dotColor: Color {
        switch session.phase {
        case .attention, .working: return Clawd.color
        case .done: return session.failed == true ? .failRed : .doneGreen
        case .idle: return .gray
        }
    }
}

private struct PulseDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Clawd.color)
            .frame(width: 7, height: 7)
            .scaleEffect(on ? 1.15 : 0.75)
            .opacity(on ? 1 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// A soft orange breath around the island while Claude is waiting on you.
private struct Glow: View {
    let shape: IslandShape
    @State private var on = false

    var body: some View {
        shape.fill(Clawd.color)
            .blur(radius: 12)
            .opacity(on ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
