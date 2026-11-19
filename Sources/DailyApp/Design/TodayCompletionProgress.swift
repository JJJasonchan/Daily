import SwiftUI

struct TodayCompletionProgress: Equatable, Sendable {
    let completed: Int
    let total: Int

    init(completed: Int, total: Int) {
        self.completed = max(completed, 0)
        self.total = max(total, 0)
    }

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(completed) / Double(total), 1)
    }

    var percentageText: String {
        "\(Int((fraction * 100).rounded()))%"
    }

    var countText: String {
        "\(completed) / \(total) tasks"
    }

    var accessibilityValue: String {
        "今日完成 \(completed) 项，共 \(total) 项，\(percentageText)"
    }
}

struct TodayCompletionRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: TodayCompletionProgress
    let motion: MotionSpec

    @State private var celebrating = false
    @State private var confettiTrigger = 0

    private var resolvedMotion: MotionSpec {
        MotionTokens.resolved(motion, reduceMotion: reduceMotion)
    }

    private var isComplete: Bool {
        progress.total > 0 && progress.completed >= progress.total
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(ColorTokens.accent.opacity(0.16), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(
                        ColorTokens.accentGradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(
                        color: ColorTokens.accent.opacity(isComplete ? 0.55 : 0.18),
                        radius: isComplete ? 12 : 4
                    )

                VStack(spacing: 1) {
                    Text("今日完成")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(progress.percentageText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isComplete ? ColorTokens.accent : Color.primary)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 106, height: 106)
            .scaleEffect(celebrating && !reduceMotion ? 1.07 : 1)
            .overlay {
                ConfettiBurst(trigger: confettiTrigger)
            }

            Text(progress.countText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.secondary)
        }
        .animation(resolvedMotion.animation, value: progress)
        .animation(.spring(duration: 0.5, bounce: 0.45), value: celebrating)
        .onChange(of: progress.fraction) { old, new in
            guard new >= 1, old < 1 else { return }
            guard !reduceMotion else { return }
            celebrating = true
            confettiTrigger += 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(520))
                celebrating = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日完成")
        .accessibilityValue(progress.accessibilityValue)
    }
}
