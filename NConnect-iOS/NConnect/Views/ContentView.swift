import SwiftUI

public struct ContentView: View {
    @StateObject private var ccuManager = YamahaCCUManager()
    @StateObject private var navEngine = NavigationEngine()
    @StateObject private var streamRenderer = TFTStreamRenderer()
    
    @State private var streamTimer: Timer?
    
    public init() {}
    
    public var body: some View {
        TabView {
            MainDashboardView(ccuManager: ccuManager, navEngine: navEngine, streamRenderer: streamRenderer)
                .tabItem {
                    Label("Trang chủ", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
            
            LiveNavigationView(navEngine: navEngine, ccuManager: ccuManager, streamRenderer: streamRenderer)
                .tabItem {
                    Label("Bản đồ", systemImage: "map.fill")
                }
            
            SettingsView(ccuManager: ccuManager)
                .tabItem {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                }
        }
        .accentColor(.cyan)
        .preferredColorScheme(.dark)
        .onAppear {
            // Cho phép màn hình tắt tự động theo cài đặt của máy
            UIApplication.shared.isIdleTimerDisabled = false
            ccuManager.onZoomIn = { [weak streamRenderer] in
                streamRenderer?.zoomIn()
            }
            ccuManager.onZoomOut = { [weak streamRenderer] in
                streamRenderer?.zoomOut()
            }
            ccuManager.updateCurrentRoadNameOnTFT(navEngine.currentRoadName)
            navEngine.onRoadNameChanged = { [weak ccuManager] road in
                ccuManager?.updateCurrentRoadNameOnTFT(road)
            }
            streamRenderer.startBackgroundStreaming(ccuManager: ccuManager, navEngine: navEngine)
        }
        .onDisappear {
            streamRenderer.stopBackgroundStreaming()
        }
    }
}
