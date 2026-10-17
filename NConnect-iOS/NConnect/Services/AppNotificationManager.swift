import Foundation
import Combine
import UIKit

// MARK: - Model Thông báo từ ứng dụng (Zalo, Messenger, SMS, Telegram, v.v.)
public struct AppNotification: Identifiable, Equatable {
    public let id: UUID
    public let appName: String
    public let sender: String
    public let message: String
    public let timestamp: Date
    
    public init(id: UUID = UUID(), appName: String, sender: String, message: String, timestamp: Date = Date()) {
        self.id = id
        self.appName = appName
        self.sender = sender
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - Quản lý thông báo hiển thị trên màn hình xe máy Yamaha (TFT Cluster)
public final class AppNotificationManager: ObservableObject {
    public static let shared = AppNotificationManager()
    
    @Published public var activeNotification: AppNotification? = nil
    @Published public var isNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isNotificationsEnabled, forKey: "cluster_notifications_enabled")
        }
    }
    @Published public var displayDurationSeconds: Int {
        didSet {
            UserDefaults.standard.set(displayDurationSeconds, forKey: "cluster_notification_duration_seconds")
        }
    }
    
    private var autoDismissTimer: Timer?
    public var onNotificationChanged: (() -> Void)?
    
    private init() {
        let savedEnabled = UserDefaults.standard.object(forKey: "cluster_notifications_enabled") as? Bool ?? true
        let savedDuration = UserDefaults.standard.integer(forKey: "cluster_notification_duration_seconds")
        self.isNotificationsEnabled = savedEnabled
        self.displayDurationSeconds = savedDuration > 0 ? savedDuration : 7
    }
    
    // MARK: - Phát thông báo mới lên màn hình xe
    public func postNotification(appName: String, sender: String, message: String) {
        guard isNotificationsEnabled else { return }
        
        let notif = AppNotification(
            appName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
            sender: sender.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeNotification = notif
            self.autoDismissTimer?.invalidate()
            
            let duration = max(3.0, Double(self.displayDurationSeconds))
            self.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.dismissNotification()
            }
            
            YamahaCCUManager.shared?.sendMessageIndicatorToCluster(appName: appName, sender: sender, message: message)
            YamahaCCUManager.shared?.log("[Thông báo TFT] 📩 [\(appName)] \(sender): \(message.prefix(30))... (Hiện \(self.displayDurationSeconds)s)")
            self.onNotificationChanged?()
        }
    }
    
    // MARK: - Tắt thông báo đang hiển thị
    public func dismissNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeNotification = nil
            self.autoDismissTimer?.invalidate()
            self.autoDismissTimer = nil
            YamahaCCUManager.shared?.clearMessageIndicatorOnCluster()
            self.onNotificationChanged?()
        }
    }
    
    // MARK: - Xử lý URL Scheme (mynmax://...) để nhận thông báo từ iOS Shortcuts hoặc bên ngoài
    public func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "mynmax" else { return }
        
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        
        func param(_ key: String) -> String {
            return queryItems.first(where: { $0.name.lowercased() == key.lowercased() })?.value ?? ""
        }
        
        switch host {
        case "notify", "notification":
            let app = param("app").isEmpty ? (param("title").isEmpty ? "Thông báo" : param("title")) : param("app")
            let sender = param("sender").isEmpty ? (param("title").isEmpty ? "Tin nhắn" : param("title")) : param("sender")
            let msg = param("message").isEmpty ? param("msg") : param("message")
            if !msg.isEmpty || !sender.isEmpty {
                postNotification(appName: app, sender: sender, message: msg)
            }
            
        case "call", "incomingcall":
            let caller = param("caller").isEmpty ? (param("sender").isEmpty ? (param("name").isEmpty ? "Cuộc gọi đến" : param("name")) : param("sender")) : param("caller")
            CallNotificationManager.shared.triggerIncomingCall(callerName: caller)
            
        case "endcall":
            CallNotificationManager.shared.rejectCall()
            
        case "dismiss":
            dismissNotification()
            
        default:
            YamahaCCUManager.shared?.log("[URL Scheme] Nhận URL không xác định: \(url.absoluteString)")
        }
    }
}
