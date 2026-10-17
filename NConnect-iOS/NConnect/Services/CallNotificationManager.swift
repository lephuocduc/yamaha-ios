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
                YamahaCCUManager.shared?.log("[Cuộc gọi] ⏹ Cuộc gọi đã kết thúc")
            } else if !call.hasConnected && !call.isOutgoing {
                self.isCallRinging = true
                self.isCallConnected = false
                self.currentCallUUID = call.uuid
                
                // Cố gắng lấy tên người gọi hoặc số điện thoại
                if let detectedCaller = self.fetchCallerIdFromPrivateFramework(), !detectedCaller.isEmpty {
                    self.callerName = detectedCaller
                } else if self.callerName.isEmpty || self.callerName == "Cuộc gọi kết thúc" {
                    self.callerName = "Cuộc gọi đến"
                }
                
                YamahaCCUManager.shared?.log("[Cuộc gọi] 📞 Cuộc gọi đến từ '\(self.callerName)' đang đổ chuông!")
            } else if call.hasConnected {
                self.isCallRinging = false
                self.isCallConnected = true
                self.currentCallUUID = call.uuid
                YamahaCCUManager.shared?.log("[Cuộc gọi] 🟢 Đang đàm thoại với '\(self.callerName)'")
            }
        }
    }
    
    // MARK: - Kích hoạt cuộc gọi đến thủ công hoặc qua URL Scheme / Test
    public func triggerIncomingCall(callerName: String) {
        DispatchQueue.main.async {
            self.callerName = callerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cuộc gọi đến" : callerName
            self.isCallRinging = true
            self.isCallConnected = false
            YamahaCCUManager.shared?.log("[Cuộc gọi] 📞 Kích hoạt hiển thị cuộc gọi: \(self.callerName)")
        }
    }
    
    // MARK: - Trích xuất tên người gọi / số điện thoại từ TelephonyUtilities (hỗ trợ TrollStore / Sideload)
    private func fetchCallerIdFromPrivateFramework() -> String? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities", RTLD_NOW) else {
            return nil
        }
        defer { dlclose(handle) }
        
        guard let callCenterClass = NSClassFromString("TUCallCenter") as? NSObject.Type else {
            return nil
        }
        
        let center = callCenterClass.perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue()
        guard let callCenter = center as? NSObject else { return nil }
        
        if let incoming = callCenter.perform(NSSelectorFromString("incomingCall"))?.takeUnretainedValue() as? NSObject {
            if let name = incoming.perform(NSSelectorFromString("displayName"))?.takeUnretainedValue() as? String, !name.isEmpty {
                return name
            }
            if let number = incoming.perform(NSSelectorFromString("destinationId"))?.takeUnretainedValue() as? String, !number.isEmpty {
                return number
            }
        }
        
        if let currentCalls = callCenter.perform(NSSelectorFromString("currentCalls"))?.takeUnretainedValue() as? [NSObject] {
            for call in currentCalls {
                if let name = call.perform(NSSelectorFromString("displayName"))?.takeUnretainedValue() as? String, !name.isEmpty {
                    return name
                }
                if let number = call.perform(NSSelectorFromString("destinationId"))?.takeUnretainedValue() as? String, !number.isEmpty {
                    return number
                }
            }
        }
        return nil
    }
    
    // MARK: - Tiếp nhận / Trả lời cuộc gọi khi bấm phím (+) trên cùm tay lái xe
    public func answerCall() {
        guard let uuid = currentCallUUID ?? callObserver.calls.first(where: { !$0.hasConnected && !$0.isOutgoing && !$0.hasEnded })?.uuid else {
            YamahaCCUManager.shared?.log("[Cuộc gọi] Bấm (+) -> Chuyển sang trạng thái đàm thoại")
            DispatchQueue.main.async {
                self.isCallRinging = false
                self.isCallConnected = true
            }
            return
        }
        
        let answerAction = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: answerAction)
        
        callController.request(transaction) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    YamahaCCUManager.shared?.log("[Cuộc gọi] ⚠️ Lệnh trả lời (+) báo lỗi: \(error.localizedDescription)")
                }
                self?.isCallRinging = false
                self?.isCallConnected = true
                YamahaCCUManager.shared?.log("[Cuộc gọi] ✓ Đã nhận cuộc gọi")
            }
        }
    }
    
    // MARK: - Từ chối / Kết thúc cuộc gọi khi bấm phím (-) trên cùm tay lái xe
    public func rejectCall() {
        guard let uuid = currentCallUUID ?? callObserver.calls.first(where: { !$0.hasEnded })?.uuid else {
            YamahaCCUManager.shared?.log("[Cuộc gọi] Bấm (-) -> Kết thúc cuộc gọi")
            DispatchQueue.main.async {
                self.isCallRinging = false
                self.isCallConnected = false
                self.currentCallUUID = nil
            }
            return
        }
        
        let endAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endAction)
        
        callController.request(transaction) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    YamahaCCUManager.shared?.log("[Cuộc gọi] ⚠️ Lệnh kết thúc (-) báo lỗi: \(error.localizedDescription)")
                }
                self?.isCallRinging = false
                self?.isCallConnected = false
                self?.currentCallUUID = nil
                YamahaCCUManager.shared?.log("[Cuộc gọi] ✓ Đã ngắt / từ chối cuộc gọi")
            }
        }
    }
}

