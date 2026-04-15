import SwiftUI

enum MoodboundDesign {
    static let tint = Color(red: 0.14, green: 0.66, blue: 0.72)
    static let accent = Color(red: 0.96, green: 0.45, blue: 0.43)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let border = Color(.separator)
    static let backgroundTop = Color(.systemGroupedBackground)
    static let backgroundBottom = Color(.systemGroupedBackground)
    static let cornerRadius: CGFloat = 8
}

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .tint(MoodboundDesign.tint)
    }
}

struct MoodCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(MoodboundDesign.surface)
            .overlay(
                RoundedRectangle(cornerRadius: MoodboundDesign.cornerRadius, style: .continuous)
                    .stroke(MoodboundDesign.border, lineWidth: colorScheme == .dark ? 0.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: MoodboundDesign.cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 14, y: 4)
    }
}

struct PressableScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func appBackground() -> some View {
        modifier(AppBackground())
    }

    func moodCard() -> some View {
        modifier(MoodCard())
    }
}
