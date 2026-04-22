import SwiftUI
import UIKit

struct SwipeBackGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackGestureController {
        SwipeBackGestureController()
    }

    func updateUIViewController(_ uiViewController: SwipeBackGestureController, context: Context) {
        uiViewController.enableIfPossible()
    }
}

final class SwipeBackGestureController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enableIfPossible()
    }

    func enableIfPossible() {
        guard let navigationController else { return }
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = nil
    }
}

private struct UnifiedSwipeBackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            SwipeBackGestureEnabler()
                .frame(width: 0, height: 0)
        )
    }
}

extension View {
    func enableUnifiedSwipeBack() -> some View {
        modifier(UnifiedSwipeBackModifier())
    }
}
