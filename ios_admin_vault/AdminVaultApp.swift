import SwiftUI

@main
struct AdminVaultApp: App {
    var body: some Scene {
        WindowGroup {
            AdminDashboardView()
                .preferredColorScheme(.dark)
        }
    }
}
