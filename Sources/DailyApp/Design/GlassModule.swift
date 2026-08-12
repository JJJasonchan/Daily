import SwiftUI

struct GlassModule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var interactive = true
    var tint: Color?
    var cornerRadius: CGFloat = 16

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(
                    shape.strokeBorder(
                        colorScheme == .dark ? Color.white : Color.black,
                        lineWidth: contrast == .increased ? 2 : 1
                    )
                    .opacity(contrast == .increased ? 0.72 : 0.28)
                )
        } else {
            content
                .glassEffect(
                    Glass.regular
                        .tint(tint)
                        .interactive(interactive && !reduceMotion),
                    in: shape
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(contrast == .increased ? 0.58 : 0.34),
                                .clear,
                                .black.opacity(contrast == .increased ? 0.30 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: contrast == .increased ? 1.5 : 0.75
                    )
                )
        }
    }
}

extension View {
    func glassModule(
        interactive: Bool = true,
        tint: Color? = nil,
        cornerRadius: CGFloat = 16
    ) -> some View {
        modifier(
            GlassModule(
                interactive: interactive,
                tint: tint,
                cornerRadius: cornerRadius
            )
        )
    }
}
