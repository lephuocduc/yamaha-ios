import SwiftUI

@main
struct NConnectApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    AppNotificationManager.shared.handleIncomingURL(url)
                }
        }
    }
}
