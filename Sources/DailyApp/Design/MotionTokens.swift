import SwiftUI

struct MotionSpec: Equatable, Sendable {
    let duration: TimeInterval
    let bounce: Double
    let pressScale: CGFloat
    let hoverLift: CGFloat

    var animation: Animation {
        .spring(duration: duration, bounce: bounce)
    }
}

enum MotionTokens {
    static let pressScale: CGFloat = 0.97
    static let hoverLift: CGFloat = -2

    static let standard = MotionSpec(
        duration: 0.36,
        bounce: 0,
        pressScale: pressScale,
        hoverLift: hoverLift
    )

    static let physical = MotionSpec(
        duration: 0.36,
        bounce: 0.18,
        pressScale: pressScale,
        hoverLift: hoverLift
    )

    static let reduced = MotionSpec(
        duration: 0,
        bounce: 0,
        pressScale: 1,
        hoverLift: 0
    )

    static func resolved(_ spec: MotionSpec, reduceMotion: Bool) -> MotionSpec {
        reduceMotion ? reduced : spec
    }
}
