import SwiftUI

struct SwipeBackGestureModifier: ViewModifier {
    let isEnabled: Bool
    let edgeWidth: CGFloat
    let minimumTranslation: CGFloat
    let onBack: () -> Void

    @State private var hasTriggered = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { value in
                        guard isEnabled, !hasTriggered else { return }
                        guard value.startLocation.x <= edgeWidth else { return }

                        let dx = value.translation.width
                        let dy = abs(value.translation.height)
                        guard dx > minimumTranslation, dx > dy else { return }

                        hasTriggered = true
                        onBack()
                    }
                    .onEnded { _ in
                        hasTriggered = false
                    }
            )
    }
}

extension View {
    func swipeBackGesture(
        isEnabled: Bool = true,
        edgeWidth: CGFloat = 32,
        minimumTranslation: CGFloat = 70,
        onBack: @escaping () -> Void
    ) -> some View {
        modifier(
            SwipeBackGestureModifier(
                isEnabled: isEnabled,
                edgeWidth: edgeWidth,
                minimumTranslation: minimumTranslation,
                onBack: onBack
            )
        )
    }
}
