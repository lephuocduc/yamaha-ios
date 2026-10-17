import Foundation
import CallKit
import Combine
import UIKit

// MARK: - Quản lý cuộc gọi & thông báo tích hợp cùm tay lái xe Yamaha
public final class CallNotificationManager: NSObject, ObservableObject, CXCallObserverDelegate {
    public static let shared = CallNotificationManager()
    
    @Published public var isCallRinging: Bool = false
    @Published public var isCallConnected: Bool = false
    @Published public var callerName: String = "Cuộc gọi đến"
    
    private let callObserver = CXCallObserver()
    private let callController = CXCallController()
    private var currentCallUUID: UUID?
    
    public override init() {
        super.init()
        callObserver.setDelegate(self, queue: .main)
    }
    
    // MARK: - Lắng nghe thay đổi trạng thái cuộc gọi từ hệ thống iOS (Cellular, Zalo, Messenger, WhatsApp, v.v.)
    public func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if call.hasEnded {
                self.isCallRinging = false
                self.isCallConnected = false
                self.currentCallUUID = nil
                self.callerName = "Cuộc gọi kết thúc"
                YamahaCCUManager.shared?.log("[Cuộc gọi] ⏹ Cuộc gọi đã kết thúc")
            } else if !call.hasConnected && !call.isOutgoing {
                self.isCallRinging = true
                self.isCallConnected = false
                self.currentCallUUID = call.uuid
                self.callerName = "Cuộc gọi đến"
                YamahaCCUManager.shared?.log("[Cuộc gọi] 📞 Cuộc gọi đến đang đổ chuông! (Nhấn (+) trên cùm xe để nghe, (-) để từ chối)")
            } else if call.hasConnected {
                self.isCallRinging = false
                self.isCallConnected = true
                self.currentCallUUID = call.uuid
                self.callerName = "Đang đàm thoại"
                YamahaCCUManager.shared?.log("[Cuộc gọi] 🟢 Cuộc gọi đã được kết nối/đang đàm thoại")
            }
        }
    }
    
    // MARK: - Tiếp nhận / Trả lời cuộc gọi khi bấm phím (+) trên cùm tay lái xe
    public func answerCall() {
        guard let uuid = currentCallUUID ?? callObserver.calls.first(where: { !$0.hasConnected && !$0.isOutgoing && !$0.hasEnded })?.uuid else {
            YamahaCCUManager.shared?.log("[Cuộc gọi] Bấm (+) nhưng không tìm thấy cuộc gọi đang đổ chuông")
            return
        }
        
        let answerAction = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: answerAction)
        
        callController.request(transaction) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    YamahaCCUManager.shared?.log("[Cuộc gọi] ⚠️ Lệnh trả lời (+) báo lỗi: \(error.localizedDescription). (Mẹo: Có thể dùng nút nhận cuộc gọi trên tai nghe mũ bảo hiểm hoặc bật 'Tự động trả lời cuộc gọi' trong Trợ năng iOS)")
                } else {
                    self?.isCallRinging = false
                    self?.isCallConnected = true
                    YamahaCCUManager.shared?.log("[Cuộc gọi] ✓ Đã gửi lệnh tiếp nhận cuộc gọi (+) thành công")
                }
            }
        }
    }
    
    // MARK: - Từ chối / Kết thúc cuộc gọi khi bấm phím (-) trên cùm tay lái xe
    public func rejectCall() {
        guard let uuid = currentCallUUID ?? callObserver.calls.first(where: { !$0.hasEnded })?.uuid else {
            YamahaCCUManager.shared?.log("[Cuộc gọi] Bấm (-) nhưng không tìm thấy cuộc gọi để từ chối")
            return
        }
        
        let endAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endAction)
        
        callController.request(transaction) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    YamahaCCUManager.shared?.log("[Cuộc gọi] ⚠️ Lệnh từ chối (-) báo lỗi: \(error.localizedDescription)")
                } else {
                    self?.isCallRinging = false
                    self?.isCallConnected = false
                    self?.currentCallUUID = nil
                    YamahaCCUManager.shared?.log("[Cuộc gọi] ✓ Đã gửi lệnh từ chối / ngắt cuộc gọi (-) thành công")
                }
            }
        }
    }
}
