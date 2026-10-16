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
            UIApplication.shared.isIdleTimerDisabled = true
            ccuManager.onZoomIn = { [weak streamRenderer] in
                streamRenderer?.zoomIn()
            }
            ccuManager.onZoomOut = { [weak streamRenderer] in
                streamRenderer?.zoomOut()
            }
            startStreamingLoop()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            streamTimer?.invalidate()
        }
    }
    
    // MARK: - Vòng lặp stream hình ảnh bản đồ lên màn hình TFT (1.5s/khung hình)
    private func startStreamingLoop() {
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            let rawSpeed = navEngine.currentSpeedKmh
            let displaySpeed = rawSpeed >= 2.5 ? rawSpeed : 0.0
            
            streamRenderer.renderLiveMapFrame(
                location: navEngine.currentLocation,
                activeRoute: navEngine.activeRoute,
                instruction: navEngine.currentInstruction,
                speedKmh: displaySpeed,
                telemetry: ccuManager.telemetry
            ) { [weak ccuManager] frameData in
                guard let data = frameData, let ccu = ccuManager else { return }
                if ccu.isMFiConnected || ccu.state == .streaming {
                    ccu.sendLiveMapFrameToTFT(data)
                }
            }
        }
    }
}
