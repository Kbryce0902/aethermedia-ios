import SwiftUI

/// Glass styling presets for AetherMedia
public enum GlassStyle {
    case card
    case navBar
    case floatingPill
    case badge
    case playerOverlay
}

/// View modifier rendering Apple Liquid Glass / frosted material effects with accessibility fallbacks
public struct LiquidGlassModifier: ViewModifier {
    public let style: GlassStyle
    public let cornerRadius: CGFloat
    
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    
    public init(style: GlassStyle = .card, cornerRadius: CGFloat = 20) {
        self.style = style
        self.cornerRadius = cornerRadius
    }
    
    public func body(content: Content) -> some View {
        if reduceTransparency {
            // High-contrast solid fallback for accessibility
            content
                .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        } else {
            // Apple Liquid Glass appearance using ultraThinMaterial and specular borders
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.25 : 0.6),
                                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                    radius: style == .navBar ? 16 : 8,
                    x: 0,
                    y: style == .navBar ? 6 : 4
                )
        }
    }
}

public extension View {
    func liquidGlass(style: GlassStyle = .card, cornerRadius: CGFloat = 20) -> some View {
        self.modifier(LiquidGlassModifier(style: style, cornerRadius: cornerRadius))
    }
}
