import SwiftUI

public struct ContentView: View {
    @StateObject private var ccuManager = YamahaCCUManager()
    @StateObject private var navEngine = NavigationEngine()
    @StateObject private var streamRenderer = TFTStreamRenderer()
    
    @State private var selectedTab: Int = 0
    @State private var streamTimer: Timer?
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            MainDashboardView(ccuManager: ccuManager, navEngine: navEngine, streamRenderer: streamRenderer)
                .tabItem {
                    Label("Trang chủ", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .tag(0)
            
            LiveNavigationView(navEngine: navEngine, ccuManager: ccuManager, streamRenderer: streamRenderer)
                .tabItem {
                    Label("Bản đồ", systemImage: "map.fill")
                }
                .tag(1)
            
            SettingsView(ccuManager: ccuManager)
                .tabItem {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .accentColor(.cyan)
        .preferredColorScheme(.dark)
        .onReceive(navEngine.$isNavigating) { navigating in
            if navigating {
                withAnimation {
                    selectedTab = 1
                }
            }
        }
        .onAppear {
            // Cho phép màn hình tắt tự động theo cài đặt của máy
            UIApplication.shared.isIdleTimerDisabled = false
            ccuManager.onZoomIn = { [weak streamRenderer, weak ccuManager] in
                if CallNotificationManager.shared.isCallRinging {
                    ccuManager?.log("Phím cùm xe (+): Đang có cuộc gọi đến -> Trả lời cuộc gọi!")
                    CallNotificationManager.shared.answerCall()
                } else {
                    streamRenderer?.zoomIn()
                }
            }
            ccuManager.onZoomOut = { [weak streamRenderer, weak ccuManager] in
                if CallNotificationManager.shared.isCallRinging || CallNotificationManager.shared.isCallConnected {
                    ccuManager?.log("Phím cùm xe (-): Đang có cuộc gọi -> Từ chối / Kết thúc cuộc gọi!")
                    CallNotificationManager.shared.rejectCall()
                } else {
                    streamRenderer?.zoomOut()
                }
            }
            ccuManager.onStopRoute = { [weak navEngine] in
                navEngine?.stopNavigation()
            }
            streamRenderer.ccuManager = ccuManager
            let initRoad = navEngine.currentRoadName.isEmpty ? navEngine.currentInstruction.nextRoadName : navEngine.currentRoadName
            if !initRoad.isEmpty {
                ccuManager.updateCurrentRoadNameOnTFT(
                    initRoad,
                    distanceMeters: Double(navEngine.currentInstruction.distanceMeters),
                    maneuverIcon: UInt8(navEngine.currentInstruction.direction.rawValue)
                )
            }
            navEngine.onRoadNameChanged = { [weak ccuManager, weak navEngine] road in
                guard let nav = navEngine else { return }
                ccuManager?.updateCurrentRoadNameOnTFT(
                    road,
                    distanceMeters: Double(nav.currentInstruction.distanceMeters),
                    maneuverIcon: UInt8(nav.currentInstruction.direction.rawValue)
                )
            }
            navEngine.onNavigationStopped = { [weak ccuManager] in
                ccuManager?.stopNavigationOnTFT()
            }
            streamRenderer.startBackgroundStreaming(ccuManager: ccuManager, navEngine: navEngine)
        }
        .onDisappear {
            streamRenderer.stopBackgroundStreaming()
        }
    }
}
