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
            // 1. Bản đồ vệ tinh & đường phố tương tác (chỉ tràn cạnh trên để không che TabBar dưới)
            Map(coordinateRegion: $region, showsUserLocation: true, userTrackingMode: $trackingMode)
                .ignoresSafeArea(edges: .top)
            
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
                    // Nút điều khiển bản đồ & Zoom
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
                .padding(.horizontal)
                .padding(.bottom, 12)
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
    
    // MARK: - HUD Dẫn đường Turn-by-Turn (Dòng chữ to đậm, khoảng cách & tên đường trên 1 hàng)
    private var navigationHUD: some View {
        HStack(spacing: 12) {
            Image(systemName: navEngine.currentInstruction.direction.iconName)
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(.green)
            
            HStack(spacing: 8) {
                Text(navEngine.currentInstruction.formattedDistance)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.green)
                
                Text("•")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.gray)
                
                Text(navEngine.currentInstruction.nextRoadName.isEmpty ? "Đang đi theo lộ trình" : navEngine.currentInstruction.nextRoadName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                navEngine.stopNavigation()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red.opacity(0.9))
            }
        }
        .padding(14)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.95))
        .cornerRadius(16)
        .shadow(radius: 8)
    }
    
    // MARK: - Nút điều khiển bản đồ & Phóng to / Thu nhỏ
    private var mapControlButtons: some View {
        VStack(spacing: 10) {
            // Nút định vị vị trí hiện tại
            Button(action: {
                trackingMode = .follow
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
            
            // Phóng to (+)
            Button(action: {
                withAnimation {
                    region.span.latitudeDelta = max(0.001, region.span.latitudeDelta * 0.5)
                    region.span.longitudeDelta = max(0.001, region.span.longitudeDelta * 0.5)
                }
                streamRenderer.zoomIn()
            }) {
                Image(systemName: "plus")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.9))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            
            // Thu nhỏ (-)
            Button(action: {
                withAnimation {
                    region.span.latitudeDelta = min(0.05, region.span.latitudeDelta * 2.0)
                    region.span.longitudeDelta = min(0.05, region.span.longitudeDelta * 2.0)
                }
                streamRenderer.zoomOut()
            }) {
                Image(systemName: "minus")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.9))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            
            // Ẩn/Hiện mini preview TFT
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
