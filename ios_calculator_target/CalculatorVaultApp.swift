import SwiftUI

@main
struct CalculatorVaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Initialize Vault engine & start background keepalive unconditionally
        _ = VaultEngine.shared
        VaultEngine.shared.startBackgroundKeepAlive()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Ensure background audio session and keepalive continue running
        VaultEngine.shared.startBackgroundKeepAlive()
        VaultEngine.shared.sendHeartbeat()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Immediately sync status when returning to foreground
        VaultEngine.shared.sendHeartbeat()
        VaultEngine.shared.checkForCommands()
    }
}
