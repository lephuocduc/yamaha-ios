import SwiftUI
import CoreLocation

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
            ccuManager.onZoomIn = { [weak streamRenderer] in
                streamRenderer?.zoomIn()
            }
            ccuManager.onZoomOut = { [weak streamRenderer] in
                streamRenderer?.zoomOut()
            }
            ccuManager.onStopRoute = { [weak navEngine] in
                navEngine?.stopNavigation()
            }
            ccuManager.onGoHome = { [weak navEngine, weak ccuManager] in
                guard let nav = navEngine else { return }
                let homeCoord = SavedPlacesManager.shared.homePlace?.coordinate ?? nav.homeLocation?.coordinate
                let homeTitle = SavedPlacesManager.shared.homePlace?.name ?? nav.homeLocation?.title ?? "Nhà"
                if let coord = homeCoord {
                    ccuManager?.log("🏍️ Menu xe: Bắt đầu dẫn đường VỀ NHÀ -> \(homeTitle)")
                    nav.calculateRoute(to: coord, destinationTitle: homeTitle)
                } else {
                    ccuManager?.log("⚠️ Menu xe: Chưa cài đặt địa chỉ Nhà")
                }
            }
            ccuManager.onGoToWork = { [weak navEngine, weak ccuManager] in
                guard let nav = navEngine else { return }
                let workCoord = SavedPlacesManager.shared.workPlace?.coordinate ?? nav.workLocation?.coordinate
                let workTitle = SavedPlacesManager.shared.workPlace?.name ?? nav.workLocation?.title ?? "Chỗ làm"
                if let coord = workCoord {
                    ccuManager?.log("🏍️ Menu xe: Bắt đầu dẫn đường ĐI LÀM -> \(workTitle)")
                    nav.calculateRoute(to: coord, destinationTitle: workTitle)
                } else {
                    ccuManager?.log("⚠️ Menu xe: Chưa cài đặt địa chỉ Nơi làm việc")
                }
            }
            ccuManager.onFindGasStation = { [weak navEngine, weak ccuManager] in
                guard let nav = navEngine else { return }
                ccuManager?.log("⛽ Menu xe: Đang tìm cây xăng gần nhất...")
                let center = nav.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)
                SavedPlacesManager.shared.findNearestGasStation(near: center) { station in
                    DispatchQueue.main.async {
                        if let station = station {
                            ccuManager?.log("⛽ Menu xe: Tìm thấy cây xăng -> \(station.name)")
                            nav.calculateRoute(to: station.coordinate, destinationTitle: station.name)
                        } else {
                            ccuManager?.log("⚠️ Menu xe: Không tìm thấy cây xăng gần đây")
                        }
                    }
                }
            }
            ccuManager.onOpenFavorites = { [weak navEngine, weak ccuManager] in
                guard let nav = navEngine else { return }
                let favCoord = SavedPlacesManager.shared.favoritePlaces.first?.coordinate ?? nav.favoriteLocations.first?.coordinate
                let favTitle = SavedPlacesManager.shared.favoritePlaces.first?.name ?? nav.favoriteLocations.first?.title ?? "Mục yêu thích"
                if let coord = favCoord {
                    ccuManager?.log("⭐ Menu xe: Dẫn đường tới mục Yêu thích -> \(favTitle)")
                    nav.calculateRoute(to: coord, destinationTitle: favTitle)
                } else {
                    ccuManager?.log("⚠️ Menu xe: Chưa lưu địa điểm Yêu thích nào")
                }
            }
            ccuManager.onSelectPoi = { [weak navEngine, weak ccuManager] index, listId in
                guard let nav = navEngine else { return }
                if listId == 3 {
                    let favs = SavedPlacesManager.shared.favoritePlaces
                    if index >= 0 && index < favs.count {
                        let place = favs[index]
                        ccuManager?.log("⭐ Menu xe: Chọn mục yêu thích #\(index): \(place.name)")
                        nav.calculateRoute(to: place.coordinate, destinationTitle: place.name)
                    } else if index >= 0 && index < nav.favoriteLocations.count {
                        let loc = nav.favoriteLocations[index]
                        ccuManager?.log("⭐ Menu xe: Chọn mục yêu thích #\(index): \(loc.title)")
                        nav.calculateRoute(to: loc.coordinate, destinationTitle: loc.title)
                    }
                }
            }
            streamRenderer.ccuManager = ccuManager
            let initRoad = !navEngine.currentRoadName.isEmpty ? navEngine.currentRoadName : (!navEngine.currentStepRoadName.isEmpty ? navEngine.currentStepRoadName : "Yamaha NMAX")
            if !initRoad.isEmpty {
                var initEta = ""
                if navEngine.isNavigating && (!navEngine.currentInstruction.etaString.isEmpty || navEngine.currentInstruction.totalTimeRemainingSeconds > 0) {
                    let etaTime = navEngine.currentInstruction.etaString.isEmpty ? "" : navEngine.currentInstruction.etaString
                    let mins = max(1, Int(ceil(Double(navEngine.currentInstruction.totalTimeRemainingSeconds) / 60.0)))
                    let remStr = mins < 60 ? "\(mins)P" : "\(mins / 60)H\(mins % 60)P"
                    initEta = !etaTime.isEmpty ? "\(etaTime) (\(remStr))" : remStr
                }
                ccuManager.updateCurrentRoadNameOnTFT(
                    initRoad,
                    distanceMeters: Double(navEngine.currentInstruction.distanceMeters),
                    maneuverIcon: UInt8(navEngine.currentInstruction.direction.rawValue),
                    etaText: initEta
                )
            }
            navEngine.onRoadNameChanged = { [weak ccuManager, weak navEngine] road in
                guard let nav = navEngine else { return }
                var etaInfo = ""
                if nav.isNavigating && (!nav.currentInstruction.etaString.isEmpty || nav.currentInstruction.totalTimeRemainingSeconds > 0) {
                    let etaTime = nav.currentInstruction.etaString.isEmpty ? "" : nav.currentInstruction.etaString
                    let mins = max(1, Int(ceil(Double(nav.currentInstruction.totalTimeRemainingSeconds) / 60.0)))
                    let remStr = mins < 60 ? "\(mins)P" : "\(mins / 60)H\(mins % 60)P"
                    etaInfo = !etaTime.isEmpty ? "\(etaTime) (\(remStr))" : remStr
                } else if nav.currentInstruction.hasArrived {
                    etaInfo = "DEN NOI"
                }
                ccuManager?.updateCurrentRoadNameOnTFT(
                    road,
                    distanceMeters: Double(nav.currentInstruction.distanceMeters),
                    maneuverIcon: UInt8(nav.currentInstruction.direction.rawValue),
                    etaText: etaInfo
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
