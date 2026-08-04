import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.white : MiniMatchColors.ink)
            .tint(isEnabled ? Color.white : MiniMatchColors.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                isEnabled
                    ? color.opacity(configuration.isPressed ? 0.78 : 1)
                    : MiniMatchColors.surface
            )
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                if !isEnabled {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(MiniMatchColors.ink, lineWidth: 2)
                }
            }
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
