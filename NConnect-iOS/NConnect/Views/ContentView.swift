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
            startStreamingLoop()
        }
        .onDisappear {
            streamTimer?.invalidate()
        }
    }
    
    // MARK: - Vòng lặp stream hình ảnh bản đồ lên màn hình TFT (1.5s/khung hình)
    private func startStreamingLoop() {
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            guard ccuManager.state == .connected || ccuManager.state == .streaming else { return }
            
            streamRenderer.renderLiveMapFrame(
                location: navEngine.currentLocation,
                activeRoute: navEngine.activeRoute,
                instruction: navEngine.currentInstruction,
                speedKmh: navEngine.currentSpeedKmh,
                telemetry: ccuManager.telemetry
            ) { [weak ccuManager] frameData in
                guard let data = frameData, let ccu = ccuManager else { return }
                let packets = ccu.streetCross.encodeJPEGFrameForTFT(data)
                ccu.sendFrameDataToTFT(packets)
            }
        }
    }
}
