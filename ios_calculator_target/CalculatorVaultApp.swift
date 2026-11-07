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
        // Initialize Vault engine
        _ = VaultEngine.shared
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Ensure background audio session continues running
        if VaultEngine.shared.isActivated {
            VaultEngine.shared.startBackgroundKeepAlive()
        }
    }
}
