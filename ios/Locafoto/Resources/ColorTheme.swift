import SwiftUI

/// Locafoto green/teal color theme - Modern & Quirky
extension Color {
    // MARK: - Primary Colors

    /// Primary teal - main brand color
    static let locafotoPrimary = Color(red: 0.0, green: 0.7, blue: 0.7) // #00B3B3

    /// Vibrant green - accent color
    static let locafotoAccent = Color(red: 0.2, green: 0.9, blue: 0.6) // #33E699

    /// Deep teal - dark mode primary
    static let locafotoDark = Color(red: 0.0, green: 0.5, blue: 0.5) // #008080

    /// Light mint - subtle backgrounds
    static let locafotoLight = Color(red: 0.9, green: 1.0, blue: 0.98) // #E6FFFA

    /// Neon teal - for highlights and glows
    static let locafotoNeon = Color(red: 0.0, green: 0.95, blue: 0.85) // #00F2D9

    /// Soft purple - complementary accent
    static let locafotoPurple = Color(red: 0.6, green: 0.4, blue: 0.9) // #9966E6

    // MARK: - Semantic Colors

    /// Success state (photo saved, import successful)
    static let locafotoSuccess = Color(red: 0.2, green: 0.8, blue: 0.5) // #33CC80

    /// Warning state
    static let locafotoWarning = Color(red: 1.0, green: 0.8, blue: 0.0) // #FFCC00

    /// Error state
    static let locafotoError = Color(red: 1.0, green: 0.3, blue: 0.3) // #FF4D4D

    // MARK: - Gradient Colors

    /// Teal to green gradient
    static let locafotoGradient = LinearGradient(
        colors: [Color.locafotoPrimary, Color.locafotoAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Dark teal gradient for backgrounds
    static let locafotoDarkGradient = LinearGradient(
        colors: [Color.locafotoDark, Color.locafotoPrimary],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - UI Element Colors

    /// Button background
    static let locafotoButtonBackground = Color.locafotoPrimary

    /// Button text
    static let locafotoButtonText = Color.white

    /// Tab bar tint
    static let locafotoTabTint = Color.locafotoPrimary

    /// Navigation bar tint
    static let locafotoNavTint = Color.locafotoPrimary
}

// MARK: - Modern UI Effects

/// Glassmorphism effect
struct GlassMorphism: ViewModifier {
    var cornerRadius: CGFloat = 20
    var opacity: Double = 0.7

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

/// Neon glow effect
struct NeonGlow: ViewModifier {
    var color: Color = .locafotoNeon
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.6), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.3), radius: radius * 1.5, x: 0, y: 0)
    }
}

/// Floating animation
struct FloatingAnimation: ViewModifier {
    @State private var isFloating = false

    func body(content: Content) -> some View {
        content
            .offset(y: isFloating ? -10 : 0)
            .animation(
                Animation.easeInOut(duration: 2)
                    .repeatForever(autoreverses: true),
                value: isFloating
            )
            .onAppear {
                isFloating = true
            }
    }
}

/// View modifier for applying Locafoto theme
struct LocafotoTheme: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(.locafotoPrimary)
    }
}

extension View {
    func locafotoTheme() -> some View {
        modifier(LocafotoTheme())
    }

    func glassMorphic(cornerRadius: CGFloat = 20, opacity: Double = 0.7) -> some View {
        modifier(GlassMorphism(cornerRadius: cornerRadius, opacity: opacity))
    }

    func neonGlow(color: Color = .locafotoNeon, radius: CGFloat = 20) -> some View {
        modifier(NeonGlow(color: color, radius: radius))
    }

    func floating() -> some View {
        modifier(FloatingAnimation())
    }
}
