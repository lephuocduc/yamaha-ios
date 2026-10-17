import SwiftUI
import MapKit

public struct LiveNavigationView: View {
    @ObservedObject var navEngine: NavigationEngine
    @ObservedObject var ccuManager: YamahaCCUManager
    @ObservedObject var streamRenderer: TFTStreamRenderer
    
    @State private var trackingMode: MapUserTrackingMode = .follow
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
            // 1. Bản đồ OpenStreetMap tương tác (hoàn toàn mã nguồn mở, không dùng Apple/Google)
            OSMMapView(navEngine: navEngine, trackingMode: $trackingMode, route: navEngine.activeRoute)
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
                .padding(.bottom, 6)
                
                // 4. Nhãn bản quyền OpenStreetMap bắt buộc
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
    
    // MARK: - Thanh tìm kiếm phía trên khi chưa dẫn đường
    private var topSearchBar: some View {
        Button(action: { showSearchSheet = true }) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.cyan)
                Text("Tìm trên OpenStreetMap (quán ăn, trạm xăng...)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                if navEngine.isCalculatingRoute {
                    ProgressView()
                        .scaleEffect(0.8)
                }
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
    
    // MARK: - Sheet tìm kiếm OpenStreetMap
    private var searchSheet: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.cyan)
                    TextField("Tìm địa điểm OpenStreetMap...", text: $searchQuery)
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
            .navigationTitle("Tìm điểm đến OSM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showSearchSheet = false }
                }
            }
        }
    }
}

// MARK: - Lớp nạp ngói bản đồ OpenStreetMap tốc độ cao có bộ đệm và tự động phục hồi
public class CustomOSMTileOverlay: MKTileOverlay {
    public static var currentTileTemplate: String = "https://tile.openstreetmap.de/{z}/{x}/{y}.png"
    private let session: URLSession
    private let memoryCache = NSCache<NSString, NSData>()
    
    public init(urlTemplate: String? = nil) {
        let template = urlTemplate ?? CustomOSMTileOverlay.currentTileTemplate
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
        
        let url = self.url(forTilePath: path)
        var request = URLRequest(url: url)
        request.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6
        
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data, (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 {
                self.memoryCache.setObject(data as NSData, forKey: key)
                result(data, nil)
            } else {
                // Fallback 1: Thử máy chủ Wikimedia OpenStreetMap nếu OSM DE bận
                let fallback1 = "https://maps.wikimedia.org/osm-intl/\(path.z)/\(path.x)/\(path.y).png"
                if let fallbackUrl1 = URL(string: fallback1) {
                    var req1 = URLRequest(url: fallbackUrl1)
                    req1.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
                    self.session.dataTask(with: req1) { d1, r1, _ in
                        if let d1 = d1, (r1 as? HTTPURLResponse)?.statusCode == 200, d1.count > 1000 {
                            self.memoryCache.setObject(d1 as NSData, forKey: key)
                            result(d1, nil)
                        } else {
                            // Fallback 2: Thử CyclOSM (nguồn mở cho xe hai bánh)
                            let fallback2 = "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/\(path.z)/\(path.x)/\(path.y).png"
                            if let fallbackUrl2 = URL(string: fallback2) {
                                var req2 = URLRequest(url: fallbackUrl2)
                                req2.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
                                self.session.dataTask(with: req2) { d2, r2, e2 in
                                    if let d2 = d2, (r2 as? HTTPURLResponse)?.statusCode == 200, d2.count > 1000 {
                                        self.memoryCache.setObject(d2 as NSData, forKey: key)
                                        result(d2, nil)
                                    } else {
                                        result(nil, error)
                                    }
                                }.resume()
                            } else {
                                result(nil, error)
                            }
                        }
                    }.resume()
                } else {
                    result(nil, error)
                }
            }
        }.resume()
    }
}

// MARK: - View Bản đồ OpenStreetMap tương tác (Thay thế hoàn toàn Apple Maps bằng OpenStreetMap)
public struct OSMMapView: UIViewRepresentable {
    @ObservedObject var navEngine: NavigationEngine
    @Binding var trackingMode: MapUserTrackingMode
    var route: OSMRoute?
    
    public init(navEngine: NavigationEngine, trackingMode: Binding<MapUserTrackingMode>, route: OSMRoute?) {
        self.navEngine = navEngine
        self._trackingMode = trackingMode
        self.route = route
    }
    
    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = false
        
        // Cấu hình ngói bản đồ OpenStreetMap tốc độ cao thay thế hoàn toàn bản đồ mặc định của Apple
        let osmOverlay = CustomOSMTileOverlay()
        mapView.addOverlay(osmOverlay, level: .aboveLabels)
        
        if let loc = navEngine.currentLocation {
            let region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)
            mapView.setRegion(region, animated: false)
        }
        
        return mapView
    }
    
    public func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.updateRoute(on: uiView, newRoute: route)
        
        if trackingMode == .follow, let loc = navEngine.currentLocation {
            let center = uiView.centerCoordinate
            let dLat = abs(center.latitude - loc.coordinate.latitude)
            let dLon = abs(center.longitude - loc.coordinate.longitude)
            if dLat > 0.0001 || dLon > 0.0001 {
                uiView.setCenter(loc.coordinate, animated: true)
            }
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: OSMMapView
        var currentPolyline: MKPolyline?
        private var lastRouteKey: String = ""
        
        init(_ parent: OSMMapView) {
            self.parent = parent
        }
        
        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 0.95)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        public func updateRoute(on mapView: MKMapView, newRoute: OSMRoute?) {
            let count = newRoute?.coordinates.count ?? 0
            let key = "\(count)_\(Int(newRoute?.distanceMeters ?? 0))"
            guard key != lastRouteKey else { return }
            lastRouteKey = key
            
            if let old = currentPolyline {
                mapView.removeOverlay(old)
                currentPolyline = nil
            }
            if let r = newRoute, !r.coordinates.isEmpty {
                let polyline = MKPolyline(coordinates: r.coordinates, count: r.coordinates.count)
                currentPolyline = polyline
                mapView.addOverlay(polyline, level: .aboveRoads)
            }
        }
    }
}


