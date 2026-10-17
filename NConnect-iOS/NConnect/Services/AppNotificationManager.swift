import Foundation
import Combine

public struct AppNotification: Identifiable, Equatable {
    public let id: UUID
    public let appName: String
    public let sender: String
    public let message: String
    public let timestamp: Date
    
    public init(id: UUID = UUID(), appName: String = "", sender: String = "", message: String = "", timestamp: Date = Date()) {
        self.id = id
        self.appName = appName
        self.sender = sender
        self.message = message
        self.timestamp = timestamp
    }
}

public final class AppNotificationManager: ObservableObject {
    public static let shared = AppNotificationManager()
    
    @Published public var activeNotification: AppNotification? = nil
    @Published public var isNotificationsEnabled: Bool = false
    @Published public var displayDurationSeconds: Int = 7
    public var onNotificationChanged: (() -> Void)?
    
    private init() {}
    
    public func postNotification(appName: String, sender: String, message: String) {}
    public func dismissNotification() {}
    public func handleIncomingURL(_ url: URL) {}
}
