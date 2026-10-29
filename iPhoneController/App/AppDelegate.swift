import UIKit

/// MacSwitch Controller: ein Switch-Controller auf dem iPhone. Er schickt nur Switch-Tasten und Sticks an MacSwitch (Bluetooth),
/// keine Tastenbelegung und nichts sonst. Was die Spiele daraus machen, entscheidet der Host.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = PadViewController()
        window?.makeKeyAndVisible()
    }
}

final class PadViewController: UIViewController {
    private let pad = PadView()
    private let client = PadClient()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all } // Wischen vom Rand soll keine Taste verschlucken

    override func loadView() { view = pad }

    override func viewDidLoad() {
        super.viewDidLoad()
        pad.onState = { [client] in client.send($0) }
        client.onStatus = { [pad] in pad.badge = $0 }
        pad.badge = "Bluetooth wird vorbereitet …"
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [pad] _ in pad.releaseAll() } // im Hintergrund bleibt nichts gedrückt
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in UIApplication.shared.isIdleTimerDisabled = true }
    }
}
