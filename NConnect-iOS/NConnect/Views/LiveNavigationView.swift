import SwiftUI
import MapKit

// MARK: - Mục điểm mốc lộ trình (Điểm A, Điểm B)
public struct RoutePointItem: Equatable, Identifiable {
    public var id = UUID()
    public var title: String
    public var subtitle: String
    public var coordinate: CLLocationCoordinate2D
    public var isCurrentLocation: Bool = false
    
    public static func == (lhs: RoutePointItem, rhs: RoutePointItem) -> Bool {
        lhs.title == rhs.title &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.isCurrentLocation == rhs.isCurrentLocation
    }
}

// MARK: - Annotation ghim Điểm A & Điểm B trên bản đồ
public class RoutePointAnnotation: NSObject, MKAnnotation {
    public var coordinate: CLLocationCoordinate2D
    public var isPointA: Bool
    public var title: String?
    public var subtitle: String?
    
    public init(coordinate: CLLocationCoordinate2D, isPointA: Bool, title: String, subtitle: String? = nil) {
        self.coordinate = coordinate
        self.isPointA = isPointA
        self.title = title
        self.subtitle = subtitle
    }
}

// MARK: - Chế độ định hướng bản đồ (North-Up vs Heading Tracking)
public enum MapOrientationMode: String, CaseIterable {
    case headingTracking = "Heading Tracking" // Theo hướng xe chạy (3D)
    case northUp = "North-Up"                 // Cố định phương Bắc (2D)
}

public struct LiveNavigationView: View {
    @ObservedObject var navEngine: NavigationEngine
    @ObservedObject var ccuManager: YamahaCCUManager
    @ObservedObject var streamRenderer: TFTStreamRenderer
    
    @State private var trackingMode: MapUserTrackingMode = .follow
    @State private var orientationMode: MapOrientationMode = .headingTracking
    @State private var showOrientationToast = false
    @State private var toastMessage = ""
    @State private var showSearchSheet = false
    @State private var searchQuery = ""
    @State private var showTFTMiniPreview = true
    
    // Quản lý Điểm A (Xuất phát) và Điểm B (Điểm đến)
    @State private var pointA: RoutePointItem? = nil // nil = Vị trí GPS hiện tại của người dùng
    @State private var pointB: RoutePointItem? = nil
    
    private enum SearchTarget {
        case pointA
        case pointB
    }
    @State private var searchTarget: SearchTarget = .pointB
    
    public init(navEngine: NavigationEngine, ccuManager: YamahaCCUManager, streamRenderer: TFTStreamRenderer) {
        self.navEngine = navEngine
        self.ccuManager = ccuManager
        self.streamRenderer = streamRenderer
    }
    
    public var body: some View {
        ZStack {
            // 1. Bản đồ OpenStreetMap tương tác vẽ lộ trình và ghim A/B
            OSMMapView(
                navEngine: navEngine,
                trackingMode: $trackingMode,
                orientationMode: orientationMode,
                route: navEngine.activeRoute,
                coordA: effectivePointACoordinate,
                coordB: pointB?.coordinate
            )
            .ignoresSafeArea(edges: .top)
            
            VStack {
                // 2. Phía trên: HUD dẫn đường Turn-by-Turn HOẶC Hộp chọn lộ trình Điểm A & Điểm B (Google Maps style)
                if navEngine.isNavigating {
                    navigationHUD
                        .padding(.top, 10)
                        .padding(.horizontal)
                } else {
                    routePlannerHeader
                        .padding(.top, 10)
                        .padding(.horizontal)
                }
                
                // Toast thông báo chuyển chế độ định hướng (North-Up / Heading Tracking)
                if showOrientationToast {
                    HStack(spacing: 8) {
                        Image(systemName: orientationMode == .headingTracking ? "location.north.line.fill" : "location.north.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(orientationMode == .headingTracking ? .cyan : .red)
                        Text(toastMessage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.88))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(orientationMode == .headingTracking ? Color.cyan.opacity(0.8) : Color.red.opacity(0.8), lineWidth: 1.2)
                    )
                    .shadow(radius: 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 4)
                }
                
                Spacer()
                
                // 3. Phía dưới: Thẻ tóm tắt lộ trình (khi đã vẽ đường xong) HOẶC Các nút điều khiển bản đồ
                if navEngine.activeRoute != nil && !navEngine.isNavigating {
                    routePreviewCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    bottomControlsBar
                }
                
                // 4. Nhãn bản quyền OpenStreetMap & Valhalla bắt buộc
                HStack {
                    Text("Bản đồ © OpenStreetMap contributors • Lộ trình Valhalla")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(6)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            searchSheet
        }
    }
    
    // Tọa độ thực tế của Điểm A (vị trí chọn sẵn hoặc GPS hiện tại)
    private var effectivePointACoordinate: CLLocationCoordinate2D? {
        pointA?.coordinate ?? navEngine.currentLocation?.coordinate
    }
    
    // MARK: - Hộp nhập lộ trình Điểm A & Điểm B kiểu Google Maps
    private var routePlannerHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Biểu tượng chuỗi hành trình Điểm A -> Điểm B
                VStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                    
                    VStack(spacing: 2) {
                        Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                        Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                        Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                    }
                    
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                }
                .padding(.leading, 4)
                
                // 2 Ô nhập Điểm A và Điểm B
                VStack(spacing: 8) {
                    // Ô Điểm A (Xuất phát)
                    Button(action: {
                        searchTarget = .pointA
                        searchQuery = ""
                        showSearchSheet = true
                    }) {
                        HStack {
                            Text(pointA?.title ?? "Vị trí của bạn")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(pointA == nil ? .cyan : .white)
                                .lineLimit(1)
                            Spacer()
                            if pointA != nil {
                                Button(action: {
                                    pointA = nil
                                    triggerRouteCalculation()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 14))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.16))
                        .cornerRadius(8)
                    }
                    
                    // Ô Điểm B (Điểm đến)
                    Button(action: {
                        searchTarget = .pointB
                        searchQuery = ""
                        showSearchSheet = true
                    }) {
                        HStack {
                            Text(pointB?.title ?? "Nhập điểm đến (Điểm B)...")
                                .font(.system(size: 14, weight: pointB == nil ? .regular : .semibold))
                                .foregroundColor(pointB == nil ? .gray : .white)
                                .lineLimit(1)
                            Spacer()
                            if pointB != nil {
                                Button(action: {
                                    clearRoute()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 14))
                                }
                            } else if navEngine.isCalculatingRoute {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(white: 0.16))
                        .cornerRadius(8)
                    }
                }
                
                // Nút Đảo Chiều lộ trình (Swap Điểm A <-> Điểm B)
                Button(action: {
                    swapPoints()
                }) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.cyan)
                        .padding(4)
                }
            }
            .padding(10)
            .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.96))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.4), radius: 8, y: 4)
        }
    }
    
    // MARK: - Thẻ tóm tắt lộ trình phong cách Google Maps (hiển thị khi vẽ đường xong)
    private var routePreviewCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(formatDuration(seconds: navEngine.activeRoute?.durationSeconds ?? 0))
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.green)
                        
                        Text("(\(formatDistance(meters: navEngine.activeRoute?.distanceMeters ?? 0)))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "bicycle")
                            .foregroundColor(.cyan)
                        Text("Tuyến đường tối ưu xe máy (Valhalla OSM)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Nút đóng / hủy lộ trình
                Button(action: {
                    clearRoute()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            
            HStack(spacing: 12) {
                // Nút Bắt đầu dẫn đường to nổi bật
                Button(action: {
                    startNavigation()
                }) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("BẮT ĐẦU DẪN ĐƯỜNG")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(12)
                    .shadow(radius: 4)
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.96))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.5), radius: 10, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
    
    // MARK: - Thanh điều khiển bản đồ & mini preview TFT phía dưới
    private var bottomControlsBar: some View {
        HStack(alignment: .bottom) {
            mapControlButtons
            Spacer()
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
        .padding(.bottom, 6)
    }
    
    // MARK: - HUD Dẫn đường Turn-by-Turn (Khi xe đang chạy)
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
                clearRoute()
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
    
    // MARK: - Nút điều khiển bản đồ & Zoom
    private var mapControlButtons: some View {
        VStack(spacing: 8) {
            // Nút Chuyển đổi Hướng bản đồ: North-Up ⇄ Heading Tracking
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    if orientationMode == .headingTracking {
                        orientationMode = .northUp
                        toastMessage = "Cố định phương Bắc (North-Up)"
                    } else {
                        orientationMode = .headingTracking
                        toastMessage = "Theo hướng xe chạy (Heading Tracking)"
                    }
                    streamRenderer.isNorthUp = (orientationMode == .northUp)
                    trackingMode = .follow
                    showOrientationToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showOrientationToast = false
                }
            }) {
                VStack(spacing: 2) {
                    if orientationMode == .headingTracking {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.cyan)
                        Text("THEO XE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.cyan)
                    } else {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(.red)
                        Text("BẮC")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 46, height: 46)
                .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.92))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(orientationMode == .headingTracking ? Color.cyan.opacity(0.8) : Color.red.opacity(0.8), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 4)
            }
            
            // Nút Định vị lại vị trí xe (Re-center)
            Button(action: {
                withAnimation {
                    trackingMode = .follow
                }
            }) {
                Image(systemName: trackingMode == .follow ? "location.fill" : "location")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(trackingMode == .follow ? .green : .gray)
                    .frame(width: 46, height: 46)
                    .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.92))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(trackingMode == .follow ? Color.green.opacity(0.8) : Color.gray.opacity(0.3), lineWidth: 1.2)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 4)
            }
            
            // Nút Phóng to (+)
            Button(action: { streamRenderer.zoomIn() }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.92))
                    .cornerRadius(12)
                    .shadow(radius: 4)
            }
            
            // Nút Thu nhỏ (-)
            Button(action: { streamRenderer.zoomOut() }) {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.92))
                    .cornerRadius(12)
                    .shadow(radius: 4)
            }
            
            // Nút Bật/Tắt xem trước màn hình TFT trên xe
            Button(action: { showTFTMiniPreview.toggle() }) {
                Image(systemName: showTFTMiniPreview ? "display" : "display.trianglebadge.exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(showTFTMiniPreview ? .green : .gray)
                    .frame(width: 46, height: 46)
                    .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.92))
                    .cornerRadius(12)
                    .shadow(radius: 4)
            }
        }
    }
    
    // MARK: - Sheet tìm kiếm OpenStreetMap
    private var searchSheet: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.cyan)
                    TextField(searchTarget == .pointA ? "Tìm điểm xuất phát A..." : "Tìm điểm đến B...", text: $searchQuery)
                        .submitLabel(.search)
                        .onSubmit {
                            navEngine.searchPlaces(query: searchQuery)
                        }
                        .onChange(of: searchQuery) { val in
                            navEngine.searchPlaces(query: val)
                        }
                    if navEngine.isSearching {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                .padding()
                .background(Color(white: 0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                List {
                    // Tùy chọn nhanh
                    Section(header: Text("Gợi ý nhanh")) {
                        if searchTarget == .pointA {
                            Button(action: {
                                pointA = nil
                                showSearchSheet = false
                                triggerRouteCalculation()
                            }) {
                                HStack {
                                    Image(systemName: "location.fill").foregroundColor(.green)
                                    VStack(alignment: .leading) {
                                        Text("Vị trí GPS hiện tại của bạn").font(.headline).foregroundColor(.primary)
                                        Text("Điểm xuất phát từ vị trí thực tế").font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        if let home = navEngine.homeLocation {
                            Button(action: {
                                applySelectedLocation(home)
                            }) {
                                HStack {
                                    Image(systemName: "house.fill").foregroundColor(.cyan)
                                    Text("Nhà riêng").font(.subheadline)
                                    Spacer()
                                    Text(home.title).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if let work = navEngine.workLocation {
                            Button(action: {
                                applySelectedLocation(work)
                            }) {
                                HStack {
                                    Image(systemName: "briefcase.fill").foregroundColor(.orange)
                                    Text("Cơ quan").font(.subheadline)
                                    Spacer()
                                    Text(work.title).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    // Kết quả tìm kiếm
                    Section(header: Text("Kết quả tìm kiếm OpenStreetMap")) {
                        ForEach(navEngine.searchResults) { item in
                            Button(action: {
                                applySelectedLocation(item)
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
                }
            }
            .navigationTitle(searchTarget == .pointA ? "Chọn Điểm A (Xuất phát)" : "Chọn Điểm B (Điểm đến)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showSearchSheet = false }
                }
            }
        }
    }
    
    // MARK: - Logic Điều hướng & Tính toán
    private func applySelectedLocation(_ item: SavedLocation) {
        let routeItem = RoutePointItem(
            title: item.title,
            subtitle: item.subtitle,
            coordinate: item.coordinate,
            isCurrentLocation: false
        )
        if searchTarget == .pointA {
            pointA = routeItem
        } else {
            pointB = routeItem
        }
        showSearchSheet = false
        triggerRouteCalculation()
    }
    
    private func triggerRouteCalculation() {
        guard let startCoord = effectivePointACoordinate, let dest = pointB else { return }
        navEngine.calculateRoute(from: startCoord, to: dest.coordinate, autoStart: false)
    }
    
    private func swapPoints() {
        let oldA = pointA
        let oldB = pointB
        
        // Nếu A là GPS hiện tại thì gán tọa độ GPS cho B, hoặc đảo ngược
        if oldA == nil, let loc = navEngine.currentLocation {
            pointB = RoutePointItem(
                title: "Vị trí GPS hiện tại",
                subtitle: "Tọa độ thực tế",
                coordinate: loc.coordinate,
                isCurrentLocation: true
            )
        } else {
            pointB = oldA
        }
        
        pointA = oldB
        triggerRouteCalculation()
    }
    
    private func startNavigation() {
        navEngine.startActiveNavigation()
        ccuManager.startStreaming()
        trackingMode = .follow
        orientationMode = .headingTracking
        streamRenderer.isNorthUp = false
    }
    
    private func clearRoute() {
        pointB = nil
        navEngine.stopNavigation()
    }
    
    private func formatDuration(seconds: Double) -> String {
        let mins = Int(seconds / 60.0)
        if mins < 60 {
            return "\(max(1, mins)) phút"
        } else {
            let hours = mins / 60
            let remainMins = mins % 60
            return "\(hours) giờ \(remainMins) ph"
        }
    }
    
    private func formatDistance(meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000.0)
        }
    }
}

// MARK: - Lớp nạp ngói bản đồ OpenStreetMap tốc độ cao có bộ đệm và tự động phục hồi
public class CustomOSMTileOverlay: MKTileOverlay {
    private let session: URLSession
    private let memoryCache = NSCache<NSString, NSData>()
    
    public init() {
        let template = OSMTileEngine.shared.tileUrlTemplate
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
        
        // Mặc định dùng ngói OpenStreetMap chuẩn của FOSSGIS (100% dữ liệu OSM, không cần API key)
        super.init(urlTemplate: template)
        self.canReplaceMapContent = true
        self.maximumZ = 19
        self.tileSize = CGSize(width: 256, height: 256)
        memoryCache.countLimit = 350
    }
    
    public override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = "\(path.z)_\(path.x)_\(path.y)" as NSString
        if let cached = memoryCache.object(forKey: key) {
            result(cached as Data, nil)
            return
        }
        
        let primaryUrlStr = "https://tile.openstreetmap.de/\(path.z)/\(path.x)/\(path.y).png"
        let fallbackUrlStr = "https://maps.wikimedia.org/osm-intl/\(path.z)/\(path.x)/\(path.y).png"
        
        guard let url = URL(string: primaryUrlStr) else {
            result(nil, nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6
        
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data, (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 {
                self.memoryCache.setObject(data as NSData, forKey: key)
                result(data, nil)
            } else if let fallbackUrl = URL(string: fallbackUrlStr) {
                var req2 = URLRequest(url: fallbackUrl)
                req2.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
                req2.timeoutInterval = 6
                self.session.dataTask(with: req2) { [weak self] d2, r2, e2 in
                    if let d2 = d2, (r2 as? HTTPURLResponse)?.statusCode == 200, d2.count > 1000 {
                        self?.memoryCache.setObject(d2 as NSData, forKey: key)
                        result(d2, nil)
                    } else {
                        result(nil, error ?? e2)
                    }
                }.resume()
            } else {
                result(nil, error)
            }
        }.resume()
    }
}

// MARK: - View Bản đồ OpenStreetMap tương tác (Vẽ lộ trình Google Maps & Ghim Điểm A/B)
public struct OSMMapView: UIViewRepresentable {
    @ObservedObject var navEngine: NavigationEngine
    @Binding var trackingMode: MapUserTrackingMode
    var orientationMode: MapOrientationMode
    var route: OSMRoute?
    var coordA: CLLocationCoordinate2D?
    var coordB: CLLocationCoordinate2D?
    
    public init(
        navEngine: NavigationEngine,
        trackingMode: Binding<MapUserTrackingMode>,
        orientationMode: MapOrientationMode = .headingTracking,
        route: OSMRoute?,
        coordA: CLLocationCoordinate2D? = nil,
        coordB: CLLocationCoordinate2D? = nil
    ) {
        self.navEngine = navEngine
        self._trackingMode = trackingMode
        self.orientationMode = orientationMode
        self.route = route
        self.coordA = coordA
        self.coordB = coordB
    }
    
    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        
        // Cấu hình ngói bản đồ OpenStreetMap ở level .aboveRoads
        let osmOverlay = CustomOSMTileOverlay()
        mapView.addOverlay(osmOverlay, level: .aboveRoads)
        
        if let loc = navEngine.currentLocation {
            let region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)
            mapView.setRegion(region, animated: false)
        }
        
        return mapView
    }
    
    public func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.updateRoute(on: uiView, newRoute: route, coordA: coordA, coordB: coordB)
        
        if trackingMode == .follow, let loc = navEngine.currentLocation {
            let speedKmh = max(0.0, loc.speed * 3.6)
            
            let camera: MKMapCamera
            switch orientationMode {
            case .headingTracking:
                // Theo hướng xe chạy (Heading Tracking):
                // Bản đồ xoay mượt mà theo góc di chuyển của xe (course) hoặc la bàn điện tử
                let effectiveHeading: CLLocationDirection = {
                    if loc.course >= 0 && speedKmh >= 3.0 {
                        return loc.course
                    } else if navEngine.currentHeading >= 0 {
                        return navEngine.currentHeading
                    } else {
                        return uiView.camera.heading
                    }
                }()
                
                // Góc nghiêng 3D thể thao khi xe lăn bánh (Pitch)
                let pitch: CGFloat = {
                    if navEngine.isNavigating {
                        return speedKmh > 15.0 ? 45.0 : 30.0
                    } else {
                        return speedKmh > 15.0 ? 35.0 : 0.0
                    }
                }()
                
                // Tầm nhìn mở rộng thích ứng tốc độ cao (Speed-Adaptive Distance)
                let viewDistance: CLLocationDistance = {
                    if speedKmh > 65.0 {
                        return 850.0
                    } else if speedKmh > 35.0 {
                        return 600.0
                    } else {
                        return 420.0
                    }
                }()
                
                camera = MKMapCamera(
                    lookingAtCenter: loc.coordinate,
                    fromDistance: viewDistance,
                    pitch: pitch,
                    heading: effectiveHeading
                )
                
            case .northUp:
                // Cố định phương Bắc (North-Up):
                // Bản đồ luôn hướng thẳng phương Bắc (heading = 0.0°), góc nhìn phẳng 2D từ trên xuống (pitch = 0.0°)
                let viewDistance: CLLocationDistance = {
                    if speedKmh > 65.0 {
                        return 950.0
                    } else if speedKmh > 35.0 {
                        return 700.0
                    } else {
                        return 500.0
                    }
                }()
                
                camera = MKMapCamera(
                    lookingAtCenter: loc.coordinate,
                    fromDistance: viewDistance,
                    pitch: 0.0,
                    heading: 0.0
                )
            }
            
            uiView.setCamera(camera, animated: true)
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: OSMMapView
        var currentPolyline: MKPolyline?
        var routeAnnotations: [MKAnnotation] = []
        private var lastRouteKey: String = ""
        
        init(_ parent: OSMMapView) {
            self.parent = parent
        }
        
        public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Khi người dùng chạm kéo bản đồ thủ công bằng ngón tay
            let isUserDrag = mapView.subviews.first?.gestureRecognizers?.contains(where: {
                $0.state == .began || $0.state == .changed
            }) ?? false
            if isUserDrag {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.trackingMode = .none
                }
            }
        }
        
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                // Màu xanh dương Google Maps sáng, đậm nét, viền bo tròn
                renderer.strokeColor = UIColor(red: 0.10, green: 0.52, blue: 1.0, alpha: 0.95)
                renderer.lineWidth = 7.0
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            guard let ptAnn = annotation as? RoutePointAnnotation else { return nil }
            let id = "RoutePointMarker"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            
            view.annotation = ptAnn
            view.canShowCallout = true
            if ptAnn.isPointA {
                view.markerTintColor = UIColor.systemGreen
                view.glyphText = "A"
            } else {
                view.markerTintColor = UIColor.systemRed
                view.glyphText = "B"
            }
            return view
        }
        
        public func updateRoute(
            on mapView: MKMapView,
            newRoute: OSMRoute?,
            coordA: CLLocationCoordinate2D?,
            coordB: CLLocationCoordinate2D?
        ) {
            let count = newRoute?.coordinates.count ?? 0
            let key = "\(count)_\(Int(newRoute?.distanceMeters ?? 0))_\(coordA?.latitude ?? 0)_\(coordB?.latitude ?? 0)"
            guard key != lastRouteKey else { return }
            lastRouteKey = key
            
            // Xóa polyline cũ và các marker cũ
            if let old = currentPolyline {
                mapView.removeOverlay(old)
                currentPolyline = nil
            }
            mapView.removeAnnotations(routeAnnotations)
            routeAnnotations.removeAll()
            
            guard let r = newRoute, !r.coordinates.isEmpty else { return }
            
            let polyline = MKPolyline(coordinates: r.coordinates, count: r.coordinates.count)
            currentPolyline = polyline
            
            // QUAN TRỌNG: Thêm polyline ở level .aboveLabels để đảm bảo luôn nằm TRÊN ngói OSM!
            mapView.addOverlay(polyline, level: .aboveLabels)
            
            // Ghim Điểm A (Xanh lá) & Điểm B (Đỏ)
            if let a = coordA {
                let annA = RoutePointAnnotation(coordinate: a, isPointA: true, title: "Điểm A (Xuất phát)")
                routeAnnotations.append(annA)
                mapView.addAnnotation(annA)
            }
            if let b = coordB {
                let annB = RoutePointAnnotation(coordinate: b, isPointA: false, title: "Điểm B (Điểm đến)")
                routeAnnotations.append(annB)
                mapView.addAnnotation(annB)
            }
            
            // Tự động căn chỉnh toàn bộ lộ trình vừa khít màn hình giống Google Maps
            let rect = polyline.boundingMapRect
            let padding = UIEdgeInsets(top: 160, left: 50, bottom: 220, right: 50)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
        }
    }
}
