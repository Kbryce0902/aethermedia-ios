import SwiftUI
import UIKit

public enum GlassButtonVariant {
    case prominentPlay
    case secondary
    case destructive
    case iconOnly
}

/// Frosted glass button adhering to Apple Human Interface Guidelines and touch targets (≥ 44pt)
public struct GlassButton: View {
    public let title: String
    public let systemImage: String?
    public let variant: GlassButtonVariant
    public let action: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init(
        title: String = "",
        systemImage: String? = nil,
        variant: GlassButtonVariant = .secondary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 8) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(variant == .prominentPlay ? .title3.bold() : .body.weight(.semibold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(variant == .prominentPlay ? .headline.bold() : .subheadline.weight(.semibold))
                }
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, variant == .iconOnly ? 14 : 20)
            .padding(.vertical, 14) // Guarantees min 48pt touch height
            .frame(minHeight: 48)
            .background(backgroundView)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(ScaleButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(title.isEmpty ? (systemImage ?? "Button") : title)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .prominentPlay:
            LinearGradient(
                colors: [Color.white, Color(white: 0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .secondary, .iconOnly:
            Color.clear
                .liquidGlass(style: .floatingPill, cornerRadius: 24)
        case .destructive:
            Color.red.opacity(0.85)
        }
    }
    
    private var foregroundColor: Color {
        switch variant {
        case .prominentPlay:
            return .black
        case .secondary, .iconOnly:
            return .primary
        case .destructive:
            return .white
        }
    }
    
    private var borderColor: Color {
        switch variant {
        case .prominentPlay:
            return Color.white.opacity(0.8)
        case .secondary, .iconOnly:
            return Color.white.opacity(0.2)
        case .destructive:
            return Color.red.opacity(0.3)
        }
    }
    
    private var shadowColor: Color {
        switch variant {
        case .prominentPlay:
            return Color.white.opacity(0.25)
        case .secondary, .iconOnly:
            return Color.black.opacity(0.12)
        case .destructive:
            return Color.red.opacity(0.3)
        }
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
