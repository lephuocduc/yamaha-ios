import SwiftUI

public struct ContentView: View {
    @StateObject private var ccuManager = YamahaCCUManager()
    @StateObject private var navEngine = NavigationEngine()
    
    private let streamRenderer = TFTStreamRenderer()
    @State private var streamTimer: Timer?
    
    public init() {}
    
    public var body: some View {
        TabView {
            MainDashboardView(ccuManager: ccuManager, navEngine: navEngine)
                .tabItem {
                    Label("Trang chủ", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
            
            LiveNavigationView(navEngine: navEngine, ccuManager: ccuManager)
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
    
    // MARK: - Vòng lặp stream hình ảnh lên màn hình TFT (1-2 FPS tiết kiệm pin & vừa đủ cho dẫn đường xe máy)
    private func startStreamingLoop() {
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard ccuManager.state == .connected || ccuManager.state == .streaming else { return }
            
            // 1. Gửi gói tin cập nhật Turn-by-Turn
            if navEngine.isNavigating {
                let turnPacket = ccuManager.streetCross.buildTurnByTurnPacket(instruction: navEngine.currentInstruction)
                ccuManager.sendFrameDataToTFT([turnPacket])
            }
            
            // 2. Render khung hình JPEG
            if let frameData = streamRenderer.renderNavigationFrame(
                instruction: navEngine.currentInstruction,
                telemetry: ccuManager.telemetry
            ) {
                let packets = ccuManager.streetCross.encodeJPEGFrameForTFT(frameData)
                ccuManager.sendFrameDataToTFT(packets)
            }
        }
    }
}
