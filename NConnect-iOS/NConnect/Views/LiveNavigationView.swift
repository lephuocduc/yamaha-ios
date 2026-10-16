import SwiftUI
import MapKit

public struct LiveNavigationView: View {
    @ObservedObject var navEngine: NavigationEngine
    @ObservedObject var ccuManager: YamahaCCUManager
    @ObservedObject var streamRenderer: TFTStreamRenderer
    
    @State private var trackingMode: MapUserTrackingMode = .follow
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009), // TP.HCM
        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
    )
    @State private var showSearchSheet = false
    @State private var searchQuery = ""
    @State private var showTFTMiniPreview = true
    
    public init(navEngine: NavigationEngine, ccuManager: YamahaCCUManager, streamRenderer: TFTStreamRenderer) {
        self.navEngine = navEngine
        self.ccuManager = ccuManager
        self.streamRenderer = streamRenderer
    }
    
    public var body: some View {
        ZStack {
            // 1. Bản đồ vệ tinh & đường phố tương tác toàn màn hình
            Map(coordinateRegion: $region, showsUserLocation: true, userTrackingMode: $trackingMode)
                .ignoresSafeArea()
            
            VStack {
                // 2. Thanh tìm kiếm nhanh hoặc HUD dẫn đường phía trên
                if navEngine.isNavigating {
                    navigationHUD
                        .padding(.top, 10)
                        .padding(.horizontal)
                } else {
                    topSearchBar
                        .padding(.top, 10)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // 3. Khung điều khiển & Xem trước khung hình TFT của xe
                HStack(alignment: .bottom) {
                    // Nút điều khiển bản đồ
                    mapControlButtons
                    
                    Spacer()
                    
                    // Khung thu nhỏ hiển thị chính xác những gì đang chiếu lên màn hình TFT của xe
                    if showTFTMiniPreview, let tftImage = streamRenderer.lastFrameImage {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack {
                                Circle().fill(ccuManager.state == .streaming ? Color.green : Color.yellow).frame(width: 6, height: 6)
                                Text(ccuManager.state == .streaming ? "TFT Đang chiếu" : "TFT Chờ")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            
                            Image(uiImage: tftImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 160, height: 90)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan, lineWidth: 1.5))
                                .shadow(radius: 6)
                        }
                    }
                }
                .padding()
                
                // 4. Thanh tác vụ dưới cùng
                bottomBar
                    .padding(.horizontal)
                    .padding(.bottom, 15)
            }
        }
        .onReceive(navEngine.$currentLocation) { loc in
            if let loc = loc {
                withAnimation {
                    region.center = loc.coordinate
                }
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            searchSheet
        }
    }
    
    // MARK: - Thanh tìm kiếm phía trên khi chưa dẫn đường
    private var topSearchBar: some View {
        Button(action: { showSearchSheet = true }) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.cyan)
                Text("Tìm địa điểm, quán ăn, cây xăng...")
                    .foregroundColor(.gray)
                Spacer()
                Image(systemName: "mic.fill")
                    .foregroundColor(.gray)
            }
            .padding(14)
            .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.95))
            .cornerRadius(14)
            .shadow(radius: 6)
        }
    }
    
    // MARK: - HUD Dẫn đường Turn-by-Turn
    private var navigationHUD: some View {
        HStack(spacing: 14) {
            Image(systemName: navEngine.currentInstruction.direction.iconName)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(navEngine.currentInstruction.formattedDistance)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text(navEngine.currentInstruction.nextRoadName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Tốc độ km/h
            VStack {
                let speed = ccuManager.telemetry.speedKmh > 0 ? ccuManager.telemetry.speedKmh : navEngine.currentSpeedKmh
                Text("\(Int(speed))")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("km/h")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
        }
        .padding(14)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.95))
        .cornerRadius(16)
        .shadow(radius: 8)
    }
    
    // MARK: - Nút điều khiển bản đồ
    private var mapControlButtons: some View {
        VStack(spacing: 10) {
            Button(action: {
                trackingMode = .followWithHeading
                if let loc = navEngine.currentLocation {
                    withAnimation {
                        region.center = loc.coordinate
                    }
                }
            }) {
                Image(systemName: "location.north.line.fill")
                    .font(.title3)
                    .foregroundColor(.cyan)
                    .padding(12)
                    .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.9))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            
            Button(action: {
                showTFTMiniPreview.toggle()
            }) {
                Image(systemName: showTFTMiniPreview ? "display" : "display.trianglebadge.exclamationmark")
                    .font(.title3)
                    .foregroundColor(showTFTMiniPreview ? .green : .gray)
                    .padding(12)
                    .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.9))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
        }
    }
    
    // MARK: - Thanh tác vụ dưới cùng
    private var bottomBar: some View {
        HStack {
            if navEngine.isNavigating {
                Button(action: {
                    navEngine.stopNavigation()
                }) {
                    Label("Dừng lộ trình", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(14)
                }
            } else {
                Button(action: {
                    ccuManager.startStreaming()
                }) {
                    Label(ccuManager.state == .streaming ? "Đang chiếu bản đồ lên TFT" : "Chiếu bản đồ lên TFT", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(ccuManager.state == .streaming ? Color.green.opacity(0.85) : Color.blue.opacity(0.85))
                        .cornerRadius(14)
                }
            }
        }
    }
    
    // MARK: - Sheet tìm kiếm
    private var searchSheet: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.cyan)
                    TextField("Nhập địa điểm...", text: $searchQuery)
                        .submitLabel(.search)
                        .onSubmit {
                            navEngine.searchPlaces(query: searchQuery)
                        }
                        .onChange(of: searchQuery) { val in
                            navEngine.searchPlaces(query: val)
                        }
                }
                .padding()
                .background(Color(white: 0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                List(navEngine.searchResults) { item in
                    Button(action: {
                        navEngine.calculateRoute(to: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude))
                        ccuManager.startStreaming()
                        showSearchSheet = false
                    }) {
                        HStack {
                            Image(systemName: "mappin.circle.fill").font(.title2).foregroundColor(.cyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline).foregroundColor(.primary)
                                Text(item.subtitle).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tìm điểm đến")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showSearchSheet = false }
                }
            }
        }
    }
}
