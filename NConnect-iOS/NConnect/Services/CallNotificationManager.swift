import Foundation
import Combine

public final class CallNotificationManager: NSObject, ObservableObject {
    public static let shared = CallNotificationManager()
    
    @Published public var isCallRinging: Bool = false
    @Published public var isCallConnected: Bool = false
    @Published public var callerName: String = ""
    
    public override init() {
        super.init()
    }
    
    public func triggerIncomingCall(callerName: String) {}
    public func answerCall() {}
    public func rejectCall() {}
}

