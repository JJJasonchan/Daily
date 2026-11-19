import AppKit
import DailyCore
import QuartzCore
import SwiftUI

struct TodayMetadataSpring {
    var progress = 0.0
    var velocity = 0.0
    var target = 0.0

    var isStill: Bool { progress == target && velocity == 0 }

    mutating func advance(by seconds: Double) {
        guard seconds > 0, !isStill else { return }
        let frequency = sqrt(75.0)
        let offset = progress - target
        let oldVelocity = velocity
        let decay = exp(-10 * seconds)
        let cosine = cos(frequency * seconds)
        let sine = sin(frequency * seconds)
        progress = target + decay * (offset * cosine + (oldVelocity + 10 * offset) / frequency * sine)
        velocity = decay * (oldVelocity * cosine - (10 * oldVelocity + 175 * offset) / frequency * sine)
        if abs(progress - target) < 0.0001, abs(velocity) < 0.001 {
            progress = target
            velocity = 0
        }
    }
}

@MainActor
@Observable
final class TodayMetadataAnimation: NSObject {
    private(set) var progress: [UUID: Double] = [:]
    @ObservationIgnored private var springs: [UUID: TodayMetadataSpring] = [:]
    @ObservationIgnored private var target: UUID?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastFrame: CFTimeInterval?
    @ObservationIgnored private weak var view: NSView?

    func setTarget(_ id: UUID?, reduceMotion: Bool) {
        let time = CACurrentMediaTime()
        if displayLink != nil { advance(to: time) }
        if let target, target != id { springs[target]?.target = 0 }
        if let id {
            var spring = springs[id] ?? TodayMetadataSpring()
            spring.target = 1
            springs[id] = spring
        }
        target = id
        if reduceMotion {
            springs = id.map { [$0: TodayMetadataSpring(progress: 1, target: 1)] } ?? [:]
        }
        publish()
        startIfNeeded()
    }

    func attach(to view: NSView) {
        guard self.view !== view else { return }
        stop()
        self.view = view
        startIfNeeded()
    }

    func detach(from view: NSView) {
        guard self.view === view else { return }
        stop()
        self.view = nil
    }

    func reset() {
        stop()
        target = nil
        springs.removeAll()
        progress.removeAll()
    }

    private func startIfNeeded() {
        guard displayLink == nil, springs.values.contains(where: { !$0.isStill }),
              let view, view.window != nil else { return }
        let link = view.displayLink(target: self, selector: #selector(frame(_:)))
        lastFrame = CACurrentMediaTime()
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func frame(_ link: CADisplayLink) {
        advance(to: CACurrentMediaTime())
    }

    private func advance(to time: CFTimeInterval) {
        let elapsed = time - (lastFrame ?? time)
        lastFrame = time
        for id in Array(springs.keys) {
            springs[id]?.advance(by: elapsed)
        }
        publish()
    }

    private func publish() {
        springs = springs.filter { $0.value.target != 0 || !$0.value.isStill }
        let next = springs.mapValues(\.progress)
        if progress != next { progress = next }
        if springs.values.allSatisfy(\.isStill) { stop() }
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrame = nil
    }
}

struct TodayMetadataDisplayDriver: NSViewRepresentable {
    let animation: TodayMetadataAnimation

    func makeNSView(context: Context) -> DriverView {
        DriverView(animation: animation)
    }

    func updateNSView(_ view: DriverView, context: Context) {}

    static func dismantleNSView(_ view: DriverView, coordinator: ()) {
        view.animation.detach(from: view)
    }

    final class DriverView: NSView {
        let animation: TodayMetadataAnimation

        init(animation: TodayMetadataAnimation) {
            self.animation = animation
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                animation.detach(from: self)
            } else {
                animation.attach(to: self)
            }
        }
    }
}

struct TodayTaskMetadata {
    let priority: String
    let date: String
    let assignee: String
    let isRolledOver: Bool

    init(task: DailyTask, calendar: Calendar = .autoupdatingCurrent) {
        priority = switch task.priority {
        case .high: "高优先级"
        case .medium: "中优先级"
        case .low: "低优先级"
        case nil: "未设优先级"
        }
        isRolledOver = task.rolloverCount > 0
        let key = isRolledOver ? task.originalDayKey : task.dayKey
        date = LocalDay(rawValue: key).date(in: calendar).formatted(.dateTime.month().day())
        assignee = task.assignee ?? "未分配"
    }

    var accessibilitySummary: String {
        let dateLabel = isRolledOver ? "原定日期" : "安排日期"
        return "\(priority)，\(dateLabel) \(date)，负责人 \(assignee)"
    }
}

struct TodayMetadataGeometry {
    let widths: [CGFloat]
    let origins: [CGFloat]
    let titleWidth: CGFloat

    init(width: CGFloat, idealWidths: [CGFloat], progress: Double) {
        let compact = width < 440
        let gap: CGFloat = compact ? 4 : 6
        let margin: CGFloat = compact ? 10 : 14
        let budget = max(0, width - min(72, width * 0.28) - margin - 2 * gap)
        let ideals = idealWidths.map { min($0, compact ? 130 : 175) }
        let total = ideals.reduce(0, +)
        if total <= budget {
            widths = ideals
        } else {
            let minimums = ideals.map { min($0, budget / CGFloat(ideals.count), 28) }
            let minimumTotal = minimums.reduce(0, +)
            let factor = (budget - minimumTotal) / max(1, total - minimumTotal)
            widths = zip(ideals, minimums).map { ideal, minimum in
                minimum + (ideal - minimum) * factor
            }
        }
        let maxOverlap: CGFloat = compact ? 25 : 34
        let overlap = min(maxOverlap, max(0, min(widths[1], widths[2]) - 14))
        let shift = overlap * (1 - progress)
        let third = width - widths[2]
        let second = third - gap - widths[1]
        let first = second - gap - widths[0]
        origins = [first + 2 * shift, second + shift, third]
        titleWidth = max(0, origins[0] - margin)
    }
}

struct TodayMetadataLayout: Layout {
    let progress: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        let pills = subviews.dropFirst()
        let geometry = TodayMetadataGeometry(
            width: bounds.width,
            idealWidths: pills.map { $0.sizeThatFits(.unspecified).width },
            progress: progress
        )
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: geometry.titleWidth, height: bounds.height)
        )
        for (index, pill) in pills.enumerated() {
            pill.place(
                at: CGPoint(x: bounds.minX + geometry.origins[index], y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: geometry.widths[index], height: nil)
            )
        }
    }
}

struct TodayMetadataMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = colorScheme == .dark
            ? Color(red: 0.96, green: 0.87, blue: 0)
            : Color(red: 0.64, green: 0.55, blue: 0)
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for (index, start) in [12.0, 132, 252].enumerated() {
                var arc = Path()
                arc.addArc(center: center, radius: 9, startAngle: .degrees(start),
                           endAngle: .degrees(start + 91), clockwise: false)
                context.stroke(arc, with: .color(tint.opacity(index == 1 ? 0.38 : 1)),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                         with: .color(tint))
        }
        .frame(width: 28, height: 28)
    }
}

struct TodayMetadataSelection {
    var hovered: UUID?
    var focused: UUID?
    private var fixed: UUID?
    private var dismissedHover: UUID?
    private var dismissedFocus: UUID?

    var expanded: UUID? {
        (focused == dismissedFocus ? nil : focused)
            ?? (hovered == dismissedHover ? nil : hovered)
            ?? fixed
    }

    mutating func hover(_ id: UUID, inside: Bool) {
        if inside, hovered != id {
            hovered = id
            dismissedHover = nil
        } else if !inside, hovered == id {
            hovered = nil
            dismissedHover = nil
        }
    }

    mutating func focus(_ id: UUID?, viaPointer: Bool) {
        guard focused != id || viaPointer else { return }
        focused = id
        dismissedFocus = viaPointer ? id : nil
    }

    mutating func toggle(_ id: UUID, viaPointer: Bool) {
        if viaPointer { dismissedFocus = focused }
        if fixed == id {
            fixed = nil
            dismissedHover = hovered
            dismissedFocus = focused
        } else {
            fixed = id
            dismissedHover = nil
            if !viaPointer { dismissedFocus = nil }
        }
    }

    mutating func dismiss() {
        fixed = nil
        dismissedHover = hovered
        dismissedFocus = focused
    }

    mutating func keep(_ ids: Set<UUID>) {
        if let hovered, !ids.contains(hovered) { hover(hovered, inside: false) }
        if let focused, !ids.contains(focused) { focus(nil, viaPointer: false) }
        if let fixed, !ids.contains(fixed) { self.fixed = nil }
    }
}

struct TodayMetadataInteraction {
    let focus: FocusState<UUID?>.Binding
    let progress: Double
    let expanded: Bool
    let onHover: (Bool) -> Void
    let onToggle: (_ viaPointer: Bool) -> Void
    let onNavigate: (KeyEquivalent) -> Void
    let onDismiss: () -> Void
    let swipeOpen: Bool
    let onShowSwipe: () -> Void
    let onHideSwipe: () -> Void
}
