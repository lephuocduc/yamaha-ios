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
            
            TripHistoryView()
                .tabItem {
                    Label("Lộ trình", systemImage: "clock.arrow.circlepath")
                }
                .tag(2)
            
            SettingsView(ccuManager: ccuManager)
                .tabItem {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                }
                .tag(3)
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
                guard let nav = navEngine, let ccu = ccuManager else { return }
                ccu.log("⛽ Menu xe: Đang tìm kiếm các cây xăng gần xe nhất...")
                let center = nav.currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)
                
                // 1. Nếu đã có sẵn danh sách cây xăng gần đây trong NavigationEngine, gửi ngay lập tức
                if !nav.nearbyGasStations.isEmpty {
                    let items = nav.nearbyGasStations.map { (name: $0.title, coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
                    ccu.sendPoiListToTFT(listId: 4, items: items, currentLoc: center)
                    if let first = items.first {
                        ccu.log("⛽ Menu xe: Tự động dẫn đường tới cây xăng gần nhất -> \(first.name)")
                        nav.calculateRoute(to: first.coordinate, destinationTitle: first.name)
                    }
                    return
                }
                
                // 2. Tìm kiếm mới qua SavedPlacesManager (MKPointOfInterestFilter [.gasStation])
                SavedPlacesManager.shared.findNearbyGasStationsList(near: center) { stations in
                    DispatchQueue.main.async {
                        if !stations.isEmpty {
                            let items = stations.map { (name: $0.name, coordinate: $0.coordinate) }
                            ccu.sendPoiListToTFT(listId: 4, items: items, currentLoc: center)
                            if let first = items.first {
                                ccu.log("⛽ Menu xe: Tự động dẫn đường tới cây xăng gần nhất -> \(first.name)")
                                nav.calculateRoute(to: first.coordinate, destinationTitle: first.name)
                            }
                        } else {
                            ccu.log("⚠️ Menu xe: Không tìm thấy cây xăng gần đây")
                            ccu.sendPoiListToTFT(listId: 4, items: [], currentLoc: center)
                            AppNotificationManager.shared.postNotification(
                                appName: "NConnect",
                                sender: "Tìm cây xăng",
                                message: "Không tìm thấy trạm xăng nào trong bán kính gần đây."
                            )
                        }
                    }
                }
            }
            ccuManager.onOpenFavorites = { [weak navEngine, weak ccuManager] in
                guard let nav = navEngine, let ccu = ccuManager else { return }
                let center = nav.currentLocation?.coordinate
                var favs: [(name: String, coordinate: CLLocationCoordinate2D)] = []
                for p in SavedPlacesManager.shared.favoritePlaces {
                    favs.append((name: p.name, coordinate: p.coordinate))
                }
                if favs.isEmpty {
                    for loc in nav.favoriteLocations {
                        favs.append((name: loc.title, coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)))
                    }
                }
                
                if !favs.isEmpty {
                    ccu.log("⭐ Menu xe: Gửi danh sách \(favs.count) mục Yêu thích lên đồng hồ xe...")
                    ccu.sendPoiListToTFT(listId: 3, items: favs, currentLoc: center)
                    if favs.count == 1, let first = favs.first {
                        ccu.log("⭐ Menu xe: Chỉ có 1 mục Yêu thích -> Tự động dẫn đường tới: \(first.name)")
                        nav.calculateRoute(to: first.coordinate, destinationTitle: first.name)
                    }
                } else {
                    ccu.log("⚠️ Menu xe: Chưa lưu địa điểm Yêu thích nào")
                    ccu.sendPoiListToTFT(listId: 3, items: [], currentLoc: center)
                    AppNotificationManager.shared.postNotification(
                        appName: "NConnect",
                        sender: "Mục Yêu thích",
                        message: "Vào Cài đặt để thêm các địa điểm Yêu thích."
                    )
                }
            }
            ccuManager.onSelectPoi = { [weak navEngine, weak ccuManager] index, listId in
                guard let nav = navEngine, let ccu = ccuManager else { return }
                if listId == 3 {
                    // Chọn mục từ danh sách Yêu thích
                    let favs = ccu.lastSentFavorites.isEmpty
                        ? SavedPlacesManager.shared.favoritePlaces.map { (name: $0.name, coordinate: $0.coordinate) }
                        : ccu.lastSentFavorites
                    if index >= 0 && index < favs.count {
                        let place = favs[index]
                        ccu.log("⭐ Menu xe: Đã chọn mục Yêu thích #\(index): \(place.name)")
                        nav.calculateRoute(to: place.coordinate, destinationTitle: place.name)
                    }
                } else if listId == 4 {
                    // Chọn mục từ danh sách Trạm xăng
                    let stations = ccu.lastSentGasStations
                    if index >= 0 && index < stations.count {
                        let station = stations[index]
                        ccu.log("⛽ Menu xe: Đã chọn cây xăng #\(index): \(station.name)")
                        nav.calculateRoute(to: station.coordinate, destinationTitle: station.name)
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
