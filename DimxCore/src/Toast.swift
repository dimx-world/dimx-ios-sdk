import UIKit

/// A short message at the bottom of the screen that goes away by itself -
/// what Android has built in and iOS does not. It lives in a window of its
/// own, above the app's, because a view added to the app window gets buried
/// by the next presentation: `present(ARViewCtrl)` adds its transition view
/// on the following run-loop pass, over whatever was there, and a toast shown
/// as the AR screen opens lasted the half second until then. The window
/// passes touches through, so the screen under it works as before. A second
/// toast replaces the first rather than stacking under it.
///
/// Main thread only.
enum Toast {
    private static let duration: TimeInterval = 3.5

    /// A window that owns no touches: hit-testing falls through to the app's.
    private final class PassthroughWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            return nil
        }
    }

    private static var window: PassthroughWindow?
    private static var current: UIView?

    static func show(_ message: String) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            Logger.warn("Toast: no window scene for [\(message)]")
            return
        }
        Logger.info("Toast: \(message)")

        let window = window ?? makeWindow(scene)
        window.windowScene = scene
        window.isHidden = false

        current?.removeFromSuperview()

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let toast = UIView()
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toast.layer.cornerRadius = 12
        toast.alpha = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.addSubview(label)

        let host = window.rootViewController!.view!
        host.addSubview(toast)
        current = toast

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: toast.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -16),
            toast.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -48),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: 24),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -24),
        ])

        UIView.animate(withDuration: 0.25) { toast.alpha = 1 }
        UIView.animate(withDuration: 0.4, delay: duration, options: [], animations: { toast.alpha = 0 }) { _ in
            toast.removeFromSuperview()
            if current === toast {
                current = nil
                // Hidden rather than dropped: an empty window costs nothing,
                // and the next toast reuses it.
                Toast.window?.isHidden = true
            }
        }
    }

    private static func makeWindow(_ scene: UIWindowScene) -> PassthroughWindow {
        let window = PassthroughWindow(windowScene: scene)
        // Above alerts, so a toast raised beside one is still seen.
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        let root = UIViewController()
        root.view.backgroundColor = .clear
        window.rootViewController = root
        Toast.window = window
        return window
    }
}
