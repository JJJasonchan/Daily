import AppKit
import SwiftUI

extension View {
    func fluidTooltip(
        _ title: String,
        shortcut: String? = nil,
        isHovered: Bool,
        isFocused: Bool,
        isEnabled: Bool = true
    ) -> some View {
        modifier(FluidTooltipSource(
            title: title,
            shortcut: shortcut,
            isHovered: isHovered,
            isFocused: isFocused,
            isEnabled: isEnabled,
            highlight: nil
        ))
    }

    func fluidRowHighlight(
        isHovered: Bool,
        isFocused: Bool,
        isEnabled: Bool,
        @ViewBuilder highlight: () -> some View
    ) -> some View {
        modifier(FluidTooltipSource(
            title: "",
            shortcut: nil,
            isHovered: isHovered,
            isFocused: isFocused,
            isEnabled: isEnabled,
            highlight: AnyView(highlight())
        ))
    }

    func fluidTooltipScope(leadingInset: CGFloat, height: CGFloat) -> some View {
        modifier(FluidTooltipScope(style: .tooltip(leadingInset: leadingInset, height: height)))
    }

    func fluidRowHighlightScope(cornerRadius: CGFloat) -> some View {
        modifier(FluidTooltipScope(style: .rowHighlight(cornerRadius: cornerRadius)))
    }
}

private enum FluidTooltipStyle {
    case tooltip(leadingInset: CGFloat, height: CGFloat)
    case rowHighlight(cornerRadius: CGFloat)
}

private struct FluidTooltipEntry {
    let id: UUID
    let title: String
    let shortcut: String?
    let anchor: Anchor<CGRect>
    let isHovered: Bool
    let isFocused: Bool
    let highlight: AnyView?
}

private struct FluidTooltipEntriesKey: PreferenceKey {
    static var defaultValue: [FluidTooltipEntry] { [] }

    static func reduce(value: inout [FluidTooltipEntry], nextValue: () -> [FluidTooltipEntry]) {
        value.append(contentsOf: nextValue())
    }
}

private extension EnvironmentValues {
    @Entry var fluidTooltipDismissRequest: Binding<Int> = .constant(0)
}

private struct FluidTooltipSource: ViewModifier {
    @Environment(\.fluidTooltipDismissRequest) private var dismissRequest
    @State private var id = UUID()

    let title: String
    let shortcut: String?
    let isHovered: Bool
    let isFocused: Bool
    let isEnabled: Bool
    let highlight: AnyView?

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: FluidTooltipEntriesKey.self, value: .bounds) { anchor in
                guard isEnabled else { return [] }
                return [FluidTooltipEntry(
                    id: id,
                    title: title,
                    shortcut: shortcut,
                    anchor: anchor,
                    isHovered: isHovered,
                    isFocused: isFocused,
                    highlight: highlight
                )]
            }
            .onKeyPress(.escape) {
                guard isEnabled, isFocused else { return .ignored }
                dismissRequest.wrappedValue += 1
                return .handled
            }
    }
}

private struct FluidTooltipScope: ViewModifier {
    @State private var dismissRequest = 0

    let style: FluidTooltipStyle

    func body(content: Content) -> some View {
        content
            .environment(\.fluidTooltipDismissRequest, $dismissRequest)
            .overlayPreferenceValue(FluidTooltipEntriesKey.self) { entries in
                GeometryReader { geometry in
                    FluidTooltipOverlay(
                        rows: entries.map {
                            FluidTooltipRow(
                                id: $0.id,
                                title: $0.title,
                                shortcut: $0.shortcut,
                                bounds: geometry[$0.anchor],
                                isHovered: $0.isHovered,
                                isFocused: $0.isFocused,
                                highlight: $0.highlight
                            )
                        },
                        style: style,
                        dismissRequest: dismissRequest
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

private struct FluidTooltipRow: Identifiable {
    let id: UUID
    let title: String
    let shortcut: String?
    let bounds: CGRect
    let isHovered: Bool
    let isFocused: Bool
    let highlight: AnyView?
}

private struct FluidTooltipOverlay: View {
    private struct Interest: Equatable {
        var hovered: UUID?
        var focused: UUID?
    }

    private struct Placement: Equatable {
        let id: UUID
        let frame: CGRect
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targetID: UUID?
    @State private var previousHover: UUID?
    @State private var previousFocus: UUID?
    @State private var dismissedInterest: Interest?
    @State private var capsuleFrame: CGRect?
    @State private var isVisible = false

    let rows: [FluidTooltipRow]
    let style: FluidTooltipStyle
    let dismissRequest: Int

    private var interest: Interest {
        Interest(
            hovered: rows.last(where: \.isHovered)?.id,
            focused: rows.last(where: \.isFocused)?.id
        )
    }

    private var activeInterest: Interest {
        dismissedInterest == interest ? Interest() : interest
    }

    private var placement: Placement? {
        guard let row = rows.first(where: { $0.id == targetID }) else { return nil }
        switch style {
        case .rowHighlight:
            return Placement(id: row.id, frame: row.bounds)
        case let .tooltip(inset, height):
            let maxWidth = row.bounds.width - inset - FluidTooltipCapsule.trailingInset
            guard maxWidth > FluidTooltipCapsule.padding * 2 else { return nil }
            let frame = CGRect(
                x: row.bounds.minX + inset,
                y: row.bounds.midY - height / 2,
                width: min(FluidTooltipCapsule.width(for: row), maxWidth),
                height: height
            )
            return Placement(id: row.id, frame: frame)
        }
    }

    var body: some View {
        ZStack {
            FluidTooltipCapsule(frame: capsuleFrame ?? .zero, rows: rows, style: style)
                .opacity(isVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: activeInterest) {
            guard dismissedInterest != interest else { return }
            let next = activeInterest
            let focusChanged = next.focused != previousFocus
            previousFocus = next.focused

            if next.hovered != previousHover, let hovered = next.hovered {
                previousHover = hovered
                targetID = hovered
                return
            }
            if focusChanged, let focused = next.focused {
                previousHover = next.hovered
                targetID = focused
                return
            }
            if next.hovered == nil && previousHover != nil {
                try? await Task.sleep(for: .milliseconds(75))
                guard !Task.isCancelled else { return }
            }
            previousHover = next.hovered
            targetID = next.hovered ?? next.focused
        }
        .onChange(of: interest) { _, _ in
            dismissedInterest = nil
        }
        .onChange(of: dismissRequest) { _, _ in
            dismissedInterest = interest
            previousHover = nil
            previousFocus = nil
            targetID = nil
            withAnimation(nil) {
                isVisible = false
                capsuleFrame = nil
            }
        }
        .onChange(of: placement) { previous, next in
            updateCapsule(from: previous, to: next)
        }
        .task(id: isVisible) {
            guard !isVisible else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard !Task.isCancelled, !isVisible else { return }
            capsuleFrame = nil
        }
    }

    private func updateCapsule(from previous: Placement?, to next: Placement?) {
        if let previous, next == nil, !rows.contains(where: { $0.id == previous.id }) {
            withAnimation(nil) {
                isVisible = false
                capsuleFrame = nil
            }
            return
        }
        if let next {
            let shouldSlide = !reduceMotion && capsuleFrame != nil && previous?.id != next.id
            let slide = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.43)
            withAnimation(shouldSlide ? slide : nil) {
                capsuleFrame = next.frame
            }
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            isVisible = next != nil
        }
    }
}

private struct FluidTooltipCapsule: View, Animatable {
    static let padding: CGFloat = 10
    static let trailingInset: CGFloat = 4
    private static let spacing: CGFloat = 8
    private static let fontSize: CGFloat = 13

    nonisolated var frame: CGRect
    let rows: [FluidTooltipRow]
    let style: FluidTooltipStyle

    nonisolated var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(frame.minX, frame.midY), frame.width) }
        set {
            frame.origin.x = newValue.first.first
            frame.origin.y = newValue.first.second - frame.height / 2
            frame.size.width = newValue.second
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // Inverse offsets keep each label at its row while the clipping capsule moves.
            ForEach(rows.filter { abs($0.bounds.midY - frame.midY) < frame.height }) {
                trackContent(for: $0)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .background(Color(red: 30 / 255, green: 30 / 255, blue: 35 / 255))
        .clipShape(clippingShape)
        .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
        .position(x: frame.midX, y: frame.midY)
    }

    private var clippingShape: AnyShape {
        switch style {
        case .tooltip:
            AnyShape(Capsule())
        case let .rowHighlight(cornerRadius):
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func trackContent(for row: FluidTooltipRow) -> some View {
        switch style {
        case .rowHighlight:
            row.highlight
                .frame(width: row.bounds.width, height: row.bounds.height)
                .position(
                    x: row.bounds.midX - frame.minX,
                    y: row.bounds.midY - frame.minY
                )
        case let .tooltip(inset, _):
            let labelWidth = max(0, row.bounds.width - inset - Self.trailingInset - Self.padding * 2)
            HStack(spacing: Self.spacing) {
                Text(verbatim: row.title)
                    .foregroundStyle(Color(white: 0.95))
                    .lineLimit(1)
                if let shortcut = row.shortcut {
                    Text(verbatim: shortcut)
                        .foregroundStyle(Color(white: 0.65))
                        .fixedSize()
                }
            }
            .font(.system(size: Self.fontSize, weight: .semibold))
            .frame(width: labelWidth, height: frame.height, alignment: .leading)
            .position(
                x: row.bounds.minX + inset + Self.padding + labelWidth / 2 - frame.minX,
                y: row.bounds.midY - frame.minY
            )
        }
    }

    static func width(for row: FluidTooltipRow) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let titleWidth = (row.title as NSString).size(withAttributes: attributes).width
        let shortcutWidth = row.shortcut.map {
            ($0 as NSString).size(withAttributes: attributes).width + spacing
        } ?? 0
        return ceil(titleWidth + shortcutWidth + padding * 2)
    }
}
