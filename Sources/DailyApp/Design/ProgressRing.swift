import SwiftUI

struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 76
    var lineWidth: CGFloat = 7
    var tint: Color = .primary
    var showsLabel = true
    var completed = 0
    var total = 0

    private let racingRed = Color.red  // system red, semantic color

    var body: some View {
        if total <= 0 {
            emptyRing
        } else if !showsLabel {
            miniView
        } else {
            gaugeView
        }
    }

    // MARK: - Mini (sidebar)

    private var miniView: some View {
        Text("\(completed)/\(total)")
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .accessibilityLabel("进度 \(completed) / \(total)")
    }

    // MARK: - Empty

    private var emptyRing: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.10), lineWidth: lineWidth)
                .opacity(0.4)
            Text("📝")
                .font(.system(size: size * 0.28))
        }
        .frame(width: size, height: size)
    }

    // MARK: - Semicircular Gauge

    private var gaugeView: some View {
        let displayTotal = total
        let radius = Double(size) / 2 - Double(lineWidth) / 2 - 4
        let center = CGPoint(x: size / 2, y: size / 2)

        return ZStack {
            // Background semicircular arc (bottom half: 180° to 360°)
            SemicircleArc(center: center, radius: radius,
                          startAngle: .degrees(180), endAngle: .degrees(360))
                .stroke(tint.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Red filled arc — covers from 180° to the needle position
            if completed > 0 {
                let endDeg = 180 + (Double(min(completed, displayTotal)) / Double(max(displayTotal, 1))) * 180
                SemicircleArc(center: center, radius: radius,
                              startAngle: .degrees(180), endAngle: .degrees(endDeg))
                    .stroke(racingRed, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // Tick marks — one per task, placed along the arc
            if displayTotal > 0 {
                ForEach(1...displayTotal, id: \.self) { i in
                    tickMark(index: i, total: displayTotal, radius: radius, center: center)
                }
            }

            // Needle pointer
            if completed > 0 {
                needle(angle: needleDegrees, radius: radius, center: center)
            }

            // Center: completed count
            Text("\(completed)")
                .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .offset(y: size * 0.06)

            // Endpoint labels: 0 on left, total on right
            endpointLabel("0", at: 180, radius: radius, center: center)
            endpointLabel("\(displayTotal)", at: 360, radius: radius, center: center)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("仪表盘进度")
        .accessibilityValue("已完成 \(completed) 项，共 \(total) 项")
    }

    // MARK: - Tick

    private func tickMark(index: Int, total: Int, radius: Double, center: CGPoint) -> some View {
        let angleDeg = 180 + (Double(index) / Double(max(total, 1))) * 180
        let rad = Angle.degrees(angleDeg).radians
        let inner = radius - 5
        let outer = radius + 2

        return Path { path in
            path.move(to: CGPoint(x: center.x + cos(rad) * inner, y: center.y + sin(rad) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(rad) * outer, y: center.y + sin(rad) * outer))
        }
        .stroke(tint.opacity(0.25), lineWidth: 1.2)
    }

    // MARK: - Endpoint label

    private func endpointLabel(_ text: String, at degrees: Double, radius: Double, center: CGPoint) -> some View {
        let rad = Angle.degrees(degrees).radians
        let offset: CGFloat = 16
        return Text(text)
            .font(.system(size: size * 0.095, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .position(
                x: center.x + cos(rad) * (radius + offset),
                y: center.y + sin(rad) * (radius + offset)
            )
    }

    // MARK: - Needle

    private var needleDegrees: Double {
        guard total > 0, completed > 0 else { return 180 }
        let capped = min(completed, total)
        return 180 + (Double(capped) / Double(total)) * 180
    }

    private func needle(angle: Double, radius: Double, center: CGPoint) -> some View {
        let rad = Angle.degrees(angle).radians
        let needleLength = radius - 6

        return Path { path in
            // pivot point slightly below center
            path.move(to: CGPoint(x: center.x, y: center.y + 4))
            path.addLine(to: CGPoint(
                x: center.x + cos(rad) * needleLength,
                y: center.y + sin(rad) * needleLength
            ))
        }
        .stroke(Color.primary, lineWidth: 2)
    }
}

// MARK: - Semicircle Arc (explicit center & radius)

private struct SemicircleArc: Shape {
    let center: CGPoint
    let radius: Double
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: startAngle, endAngle: endAngle,
                    clockwise: false)
        return path
    }
}
