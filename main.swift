import AppKit
import SwiftUI

// MARK: - Small pieces

func gaugeColor(_ percent: Double, severity: String, tint: Color) -> Color {
    if severity != "normal" || percent >= 90 { return Color(red: 1.0, green: 0.33, blue: 0.33) }
    if percent >= 70 { return .orange }
    return tint
}

struct Ring: View {
    let item: UsageItem?
    let tint: Color
    var body: some View {
        let pct = min(item?.percent ?? 0, 100)
        let color = item.map { gaugeColor($0.percent, severity: $0.severity, tint: tint) } ?? tint
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 3)
            Circle()
                .trim(from: 0, to: pct / 100)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.55), color],
                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: pct)
    }
}

struct MiniGauge: View {
    let item: UsageItem?
    let tint: Color
    var body: some View {
        HStack(spacing: 5) {
            Ring(item: item, tint: tint).frame(width: 14, height: 14)
            if let item {
                Text(item.short)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Text("\(Int(item.percent))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            } else {
                Text("—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}

struct BarRow: View {
    let item: UsageItem
    let tint: Color
    var body: some View {
        let color = gaugeColor(item.percent, severity: item.severity, tint: tint)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(resetText(item.resetsAt))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                Text("\(Int(item.percent))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .frame(width: 38, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [color.opacity(0.65), color],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(4, geo.size.width * min(item.percent, 100) / 100))
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: item.percent)
                }
            }
            .frame(height: 4)
        }
    }
}

struct ProviderChip: View {
    let provider: Provider
    let isSelected: Bool
    let isConnected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(provider.glyph)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? provider.tint : .white.opacity(0.5))
                Text(provider.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                Circle()
                    .fill(isConnected ? Color(red: 0.35, green: 0.85, blue: 0.55) : .orange)
                    .frame(width: 4, height: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? provider.tint.opacity(0.22) : .white.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? provider.tint.opacity(0.65) : .white.opacity(0.10),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Root view

struct IslandRootView: View {
    @ObservedObject var model: UsageModel
    let notchW: CGFloat
    let barH: CGFloat

    private var hovering: Bool { model.hovering }
    private var tint: Color { model.selected.tint }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: hovering ? 22 : 12,
            bottomTrailingRadius: hovering ? 22 : 12, topTrailingRadius: 0,
            style: .continuous
        )
    }

    private var island: some View {
        VStack(spacing: 0) {
            collapsedRow
            if hovering { details }
        }
        .background(
            shape.fill(Color.black)
                .overlay(
                    shape.fill(LinearGradient(
                        colors: [tint.opacity(hovering ? 0.12 : 0.05), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                )
                .overlay(shape.strokeBorder(.white.opacity(hovering ? 0.08 : 0), lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onHover { h in
            if h { model.refreshIfStale() }
            model.setHover(h)
        }
    }

    private var collapsedRow: some View {
        let state = model.current
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(model.selected.glyph)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                MiniGauge(item: state.items.first, tint: tint)
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: notchW)
            HStack(spacing: 6) {
                if state.items.count > 1 {
                    MiniGauge(item: state.items[1], tint: tint)
                } else {
                    Circle()
                        .fill(state.connected ? Color(red: 0.35, green: 0.85, blue: 0.55) : .orange)
                        .frame(width: 5, height: 5)
                    Text(state.connected ? "linked" : "login")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: barH)
    }

    private var details: some View {
        let state = model.current
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Provider.allCases) { p in
                    ProviderChip(
                        provider: p,
                        isSelected: model.selected == p,
                        isConnected: model.states[p]?.connected ?? false
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            model.selected = p
                        }
                    }
                }
                Spacer()
            }

            if state.items.isEmpty {
                statusBlock(state)
            } else {
                VStack(spacing: 10) {
                    ForEach(state.items) { BarRow(item: $0, tint: tint) }
                }
            }

            if let note = state.note, !state.items.isEmpty {
                Text(note)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }

            footer(state)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .transition(.opacity)
    }

    private func statusBlock(_ state: ProviderState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.note ?? (state.connected ? "Connected" : "Not connected"))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            if !state.connected {
                Button {
                    model.connect(model.selected)
                } label: {
                    Text("Connect in browser →")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(tint.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private static let staleAfter: TimeInterval = 6 * 3600

    private func footer(_ state: ProviderState) -> some View {
        let age = state.updatedAt.map { -$0.timeIntervalSinceNow } ?? 0
        return HStack(spacing: 10) {
            Text(agoText(state.updatedAt))
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(age > Self.staleAfter ? Color.orange : Color.white.opacity(0.35))
            Text("auto 60s")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.25))
            Spacer()
            footerButton(model.launchAtLogin ? "startup ✓" : "startup") {
                model.toggleLaunchAtLogin()
            }
            footerButton("refresh") { model.refresh() }
            footerButton("quit") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window controller

/// The window never resizes (that's what made hover janky) — it stays at max height
/// and this view lets clicks fall through everything below the visible island.
final class IslandHostingView: NSHostingView<IslandRootView> {
    var interactiveHeight: CGFloat = 34

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let fromTop = isFlipped ? p.y : bounds.height - p.y
        return fromTop <= interactiveHeight ? super.hitTest(point) : nil
    }

    required init(rootView: IslandRootView) { super.init(rootView: rootView) }
    @objc required dynamic init?(coder: NSCoder) { fatalError("not used") }
}

final class IslandController {
    let panel: NSPanel
    let model = UsageModel()
    private var screen: NSScreen?
    private var hostView: IslandHostingView?
    private var notchW: CGFloat = 172
    private var barH: CGFloat = 34
    private static let wing: CGFloat = 104
    private static let maxHeight: CGFloat = 420

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true

        model.onHoverChange = { [weak self] hovering in self?.setExpanded(hovering) }
        reposition()
        panel.orderFrontRegardless()
        model.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.model.refresh() }
    }

    func reposition() {
        guard let target = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        screen = target
        let inset = target.safeAreaInsets.top
        barH = inset > 0 ? inset : 34
        if inset > 0,
           let l = target.auxiliaryTopLeftArea, let r = target.auxiliaryTopRightArea {
            notchW = target.frame.width - l.width - r.width
        } else {
            notchW = 172
        }
        let root = IslandRootView(model: model, notchW: notchW, barH: barH)
        let host = IslandHostingView(rootView: root)
        host.interactiveHeight = model.hovering ? expandedHeight() : barH
        hostView = host
        panel.contentView = host

        let width = notchW + 2 * Self.wing
        panel.setFrame(
            NSRect(
                x: target.frame.midX - width / 2,
                y: target.frame.maxY - Self.maxHeight,
                width: width, height: Self.maxHeight
            ),
            display: true
        )
    }

    private func setExpanded(_ expanded: Bool) {
        hostView?.interactiveHeight = expanded ? expandedHeight() : barH
    }

    private func expandedHeight() -> CGFloat {
        let state = model.current
        guard !state.items.isEmpty else { return barH + 190 }
        let noteExtra: CGFloat = state.note != nil ? 18 : 0
        return barH + 140 + CGFloat(state.items.count) * 36 + noteExtra
    }
}

// MARK: - Main

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: IslandController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = IslandController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
