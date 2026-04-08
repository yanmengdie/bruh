import SwiftUI
import UIKit

struct AppBackIcon: View {
    var body: some View {
        Image(systemName: "chevron.left")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color(red: 0.52, green: 0.54, blue: 0.57))
    }
}

struct AppBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppBackIcon()
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44, alignment: .leading)
    }
}

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
