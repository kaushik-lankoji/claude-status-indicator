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
                shape.fill(model.primary?.provider.color ?? .clear)
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
        let both = model.lanes.count > 1
        return VStack(spacing: 0) {
            header(width: width)
            if model.isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, s in
                        SessionRow(session: s, showsAgent: both, actions: actions)
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

    /// One agent: its mascot beside its status. With two agents the second is mirrored,
    /// so the pair reads  🦀 4:57 │ ● ☁  and each side keeps its own mood.
    private func header(width: CGFloat) -> some View {
        let pixel = model.metrics.pixel
        let lanes = model.lanes
        let centre = model.isExpanded && model.sessions.count > 1

        func mascot(_ lane: Lane) -> some View {
            Mascot(agent: lane.agent, phase: lane.lead.phase, since: lane.lead.since, pixel: pixel,
                   animating: model.isVisible)
                .offset(y: -pixel) // centre the standing body, not the hop headroom
                .frame(width: Mascot.width(pixel: pixel))
        }

        return HStack(spacing: 0) {
            if let first = lanes.first {
                mascot(first)
                if lanes.count > 1 {
                    Status(sessions: first.sessions, agent: first.agent).padding(.leading, 10)
                    Group {
                        if centre {
                            Text("\(model.sessions.count) sessions")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.38))
                        } else {
                            Color.white.opacity(0.14).frame(width: 1, height: 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Status(sessions: lanes[1].sessions, agent: lanes[1].agent).padding(.trailing, 10)
                    mascot(lanes[1])
                } else {
                    if centre {
                        Text("\(model.sessions.count) sessions")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.38))
                            .frame(maxWidth: .infinity)
                    } else {
                        Spacer(minLength: 10)
                    }
                    Status(sessions: first.sessions, agent: first.agent)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: model.metrics.header)
        .contentShape(Rectangle())
        .onTapGesture { if let s = model.primary { actions.open(s) } }
    }
}

/// An agent's status: a clock for one working session, otherwise one dot per session.
private struct Status: View {
    let sessions: [Session]
    let agent: Agent

    var body: some View {
        ZStack {
            if let only = sessions.first, sessions.count == 1 {
                single(only)
                    .id(only.phase)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            } else {
                HStack(spacing: 5) {
                    ForEach(sessions.prefix(4)) { s in
                        Dot(phase: s.phase, failed: s.failed == true, agent: agent)
                    }
                }
            }
        }
        .frame(minWidth: sessions.count > 1 ? nil : 40, alignment: .trailing)
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
            Dot(phase: .attention, failed: false, agent: agent)
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
    let agent: Agent
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
        case .attention: return agent.color
        case .working: return .white.opacity(0.4)
        case .done: return failed ? .failRed : .doneGreen
        case .idle: return .gray
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let showsAgent: Bool
    let actions: IslandActions

    private var attention: Bool { session.phase == .attention }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if showsAgent {
                    Text(session.provider.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(session.provider.color)
                }
                Text(session.project)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: showsAgent ? 90 : 110, alignment: .trailing)
            }
            if let sub = session.subline {
                Text(sub)
                    .font(session.request != nil ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(session.request != nil ? .middle : .tail)
                    .padding(.top, 2)
            }
            if attention {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if session.request != nil {
                        Button("Deny") { actions.decide(session, .deny) }
                            .buttonStyle(PillStyle(primary: false, tint: session.provider.color))
                        Button("Allow") { actions.decide(session, .allow) }
                            .buttonStyle(PillStyle(primary: true, tint: session.provider.color))
                    } else {
                        Button(openLabel) { actions.open(session) }
                            .buttonStyle(PillStyle(primary: true, tint: session.provider.color))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, attention ? 11 : 0)
        .frame(width: Metrics.expandedWidth, height: Metrics.rowHeight(session), alignment: attention ? .top : .center)
        .contentShape(Rectangle())
        .onTapGesture { if !attention { actions.open(session) } }
    }

    private var openLabel: String {
        if session.provider == .codex { return session.reason == "plan" ? "Review in Codex" : "Open Codex" }
        return session.reason == "plan" ? "Review in terminal" : "Open terminal"
    }
}

private struct PillStyle: ButtonStyle {
    let primary: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(primary ? Color.black.opacity(0.85) : Color.white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(minWidth: 64, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(primary ? tint : Color.white.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A soft breath of the agent's colour around the dock while it's waiting on you.
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
