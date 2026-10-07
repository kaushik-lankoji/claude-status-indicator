import SwiftUI
import IslandCore

extension Color {
    static let doneGreen = Color(red: 0.42, green: 0.80, blue: 0.53)
    static let failRed = Color(red: 0.93, green: 0.42, blue: 0.38)
}

struct IslandActions {
    var open: (Session) -> Void
    var decide: (Session, Store.Verdict) -> Void
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    var actions: IslandActions

    /// Room left of the dock so its shadow isn't clipped by the window.
    static let shadowRoom: CGFloat = 16
    private var beside: Bool { model.metrics.left != nil }

    var body: some View {
        let size = model.size
        let shape = RoundedRectangle(cornerRadius: model.cornerRadius, style: .continuous)
        let calling = model.primary?.phase == .attention

        ZStack(alignment: .top) {
            if calling {
                shape.fill(Clawd.color)
                    .blur(radius: 12)
                    .modifier(Breathe())
                    .transition(.opacity)
            }
            shape.fill(Color.black)
            shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            content(width: size.width)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(model.isExpanded ? 0.3 : 0.15), radius: model.isExpanded ? 14 : 6, y: 4)
        .opacity(model.isVisible ? 1 : 0)
        .padding(.top, model.metrics.inset)
        .padding(.leading, beside ? Self.shadowRoom : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: beside ? .topLeading : .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: size)
        .animation(.easeInOut(duration: 0.3), value: calling)
    }

    private func content(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(width: width)
            if model.isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, s in
                        SessionRow(session: s, actions: actions)
                            .overlay(alignment: .top) {
                                if index > 0 { Color.white.opacity(0.07).frame(height: 0.5).padding(.horizontal, 16) }
                            }
                    }
                    if model.hiddenCount > 0 {
                        Text("+\(model.hiddenCount) more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(height: Metrics.moreHeight)
                    }
                }
                .frame(width: Metrics.expandedWidth)
                .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func header(width: CGFloat) -> some View {
        let pixel = model.metrics.pixel
        return HStack(spacing: 0) {
            if let s = model.primary {
                Clawd(phase: s.phase, since: s.since, pixel: pixel, animating: model.isVisible)
                    .offset(y: -pixel) // centre the standing body, not the hop headroom
                    .frame(width: CGFloat(Clawd.columns) * pixel)
                if model.isExpanded, model.sessions.count > 1 {
                    Text("\(model.sessions.count) sessions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                        .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 10)
                }
                Status(sessions: model.sessions)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: model.metrics.header)
        .contentShape(Rectangle())
        .onTapGesture { if let s = model.primary { actions.open(s) } }
    }
}

/// Right side of the dock: a clock for one working session, otherwise one dot per session.
private struct Status: View {
    let sessions: [Session]

    var body: some View {
        ZStack {
            if let only = sessions.first, sessions.count == 1 {
                single(only)
                    .id(only.phase)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                HStack(spacing: 5) {
                    ForEach(sessions.prefix(4)) { s in
                        Dot(phase: s.phase, failed: s.failed == true)
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: sessions.first?.phase)
    }

    @ViewBuilder private func single(_ s: Session) -> some View {
        switch s.phase {
        case .working:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Session.clock(context.date.timeIntervalSince1970 - (s.turnStart ?? s.since)))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .attention:
            Dot(phase: .attention, failed: false)
        case .done:
            Image(systemName: s.failed == true ? "exclamationmark" : "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(s.failed == true ? Color.failRed : Color.doneGreen)
        case .idle:
            EmptyView()
        }
    }
}

private struct Dot: View {
    let phase: Phase
    let failed: Bool
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(phase == .attention && on ? 1.35 : 1)
            .opacity(phase == .attention && !on ? 0.6 : 1)
            .onAppear {
                guard phase == .attention else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = true }
            }
    }

    private var color: Color {
        switch phase {
        case .attention: return Clawd.color
        case .working: return .white.opacity(0.4)
        case .done: return failed ? .failRed : .doneGreen
        case .idle: return .gray
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let actions: IslandActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(session.project)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            if let sub = session.subline {
                Text(sub)
                    .font(session.request != nil ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(session.request != nil ? .middle : .tail)
                    .padding(.top, 2)
            }
            if session.phase == .attention {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if session.request != nil {
                        Button("Deny") { actions.decide(session, .deny) }
                            .buttonStyle(PillStyle(primary: false))
                        Button("Allow") { actions.decide(session, .allow) }
                            .buttonStyle(PillStyle(primary: true))
                    } else {
                        Button(session.reason == "plan" ? "Review in terminal" : "Open terminal") { actions.open(session) }
                            .buttonStyle(PillStyle(primary: true))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, session.phase == .attention ? 11 : 0)
        .frame(width: Metrics.expandedWidth, height: Metrics.rowHeight(session), alignment: session.phase == .attention ? .top : .center)
        .contentShape(Rectangle())
        .onTapGesture { if session.phase != .attention { actions.open(session) } }
    }
}

private struct PillStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(primary ? Color.black.opacity(0.85) : Color.white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(minWidth: 64, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(primary ? Clawd.color : Color.white.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A soft orange breath around the dock while Claude is waiting on you.
private struct Breathe: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.9 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
