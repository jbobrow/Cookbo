#if os(iOS)
import UIKit

/// On iPhone the app stays upright, except cook mode, which can turn
/// sideways. iPad keeps every orientation.
enum OrientationLock {
    /// A count, not a flag: one cook mode can appear before another has
    /// finished disappearing (say, when a timer's link opens it again).
    private static var openCookModes = 0

    static var supported: UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        return openCookModes > 0 ? .allButUpsideDown : .portrait
    }

    /// Lets cook mode turn sideways. UIKit then turns it to match the phone:
    /// sideways if it was opened by turning the phone, or whenever the phone
    /// is turned while it's open.
    static func cookModeOpened() {
        openCookModes += 1
        refreshSupportedOrientations()
    }

    /// Back to upright for everything else; UIKit turns the screen back.
    static func cookModeClosed() {
        openCookModes = max(openCookModes - 1, 0)
        refreshSupportedOrientations()
    }

    private static func refreshSupportedOrientations() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        refresh()
        // Again once cook mode has finished sliding up, since UIKit doesn't
        // rotate in the middle of a presentation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { refresh() }
    }

    private static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The recipe page watches the phone's own orientation to open cook mode
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationLock.supported
    }
}
#endif
