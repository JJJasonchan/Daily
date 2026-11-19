import SwiftUI

/// 克制版“全部完成”庆祝：从进度环位置撒出一小撮彩纸，尊重“减少动态效果”。
struct ConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 每自增一次触发一次撒花。
    let trigger: Int
    var particleCount: Int = 16

    @State private var particles: [ConfettiParticle] = []
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                let t = progress
                shard(particle)
                    .offset(
                        x: CGFloat(cos(particle.angle) * particle.distance * t),
                        y: CGFloat(sin(particle.angle) * particle.distance * t + particle.gravity * t * t)
                    )
                    .rotationEffect(.degrees(particle.spin * t))
                    .opacity(t >= 1 ? 0 : 1 - t)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            burst()
        }
    }

    private func shard(_ particle: ConfettiParticle) -> some View {
        Capsule()
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size * 0.45)
    }

    private func burst() {
        guard !reduceMotion else { return }
        particles = (0..<particleCount).map { _ in
            ConfettiParticle(
                angle: .random(in: -.pi ... 0),
                distance: .random(in: 70...170),
                spin: .random(in: -720...720),
                gravity: .random(in: 260...400),
                color: ConfettiParticle.palette.randomElement() ?? ColorTokens.accent,
                size: .random(in: 5...9)
            )
        }
        progress = 0
        withAnimation(.easeOut(duration: 1.15)) {
            progress = 1
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let angle: Double
    let distance: Double
    let spin: Double
    let gravity: Double
    let color: Color
    let size: Double

    static let palette: [Color] = [
        ColorTokens.accent,
        ColorTokens.accent.opacity(0.75),
        Color(red: 0.99, green: 0.78, blue: 0.35), // 柔金
        Color(red: 0.45, green: 0.83, blue: 0.72)  // 柔青
    ]
}
