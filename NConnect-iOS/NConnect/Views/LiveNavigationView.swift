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

// MARK: - Annotation ghim Điểm A, Điểm B, Điểm dừng trung gian (1, 2, 3...) & Điểm nhấn giữ trên bản đồ
public class RoutePointAnnotation: NSObject, MKAnnotation {
    public var coordinate: CLLocationCoordinate2D
    public var isPointA: Bool
    public var isDroppedPin: Bool
    public var stopIndex: Int?
    public var title: String?
    public var subtitle: String?
    
    public init(coordinate: CLLocationCoordinate2D, isPointA: Bool = false, isDroppedPin: Bool = false, stopIndex: Int? = nil, title: String, subtitle: String? = nil) {
        self.coordinate = coordinate
        self.isPointA = isPointA
        self.isDroppedPin = isDroppedPin
        self.stopIndex = stopIndex
        self.title = title
        self.subtitle = subtitle
    }
}

// MARK: - Loại địa điểm đặc biệt đã lưu (Nhà, Công ty, Y��u thích, Vị trí đỗ xe)
public enum SpecialPlaceType: String {
    case home = "Nhà"
    case work = "Công ty"
    case favorite = "Yêu thích"
    case parking = "Vị trí đỗ xe"
}

// MARK: - Annotation ghim các địa điểm đặc biệt trên bản đồ lớn
public class SpecialPlaceAnnotation: NSObject, MKAnnotation {
    public var coordinate: CLLocationCoordinate2D
    public var placeType: SpecialPlaceType
    public var title: String?
    public var subtitle: String?
    
    public init(coordinate: CLLocationCoordinate2D, placeType: SpecialPlaceType, title: String, subtitle: String? = nil) {
        self.coordinate = coordinate
        self.placeType = placeType
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
    @Environment(\.verticalSizeClass) var verticalSizeClass
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }
    
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
    @ObservedObject private var savedPlaces = SavedPlacesManager.shared
    @ObservedObject private var parkingManager = ParkingLocationManager.shared
    
    // Quản lý Điểm A (Xuất phát), Các điểm dừng trung gian và Điểm B (Điểm đến)
    @State private var pointA: RoutePointItem? = nil // nil = Vị trí GPS hiện tại của người dùng
    @State private var pointB: RoutePointItem? = nil
    @State private var intermediateStops: [RoutePointItem] = []
    
    // Quản lý Điểm ghim khi nhấn giữ trên bản đồ (Dropped Pin Long Press)
    @State private var droppedPinCoordinate: CLLocationCoordinate2D? = nil
    @State private var droppedPinTitle: String = ""
    @State private var droppedPinSubtitle: String = ""
    @State private var isLoadingAddress: Bool = false
    @State private var showDroppedPinCard: Bool = false
    
    private enum SearchTarget: Equatable {
        case pointA
        case pointB
        case newStop
        case editStop(Int)
    }
    @State private var searchTarget: SearchTarget = .pointB
    
    public init(navEngine: NavigationEngine, ccuManager: YamahaCCUManager, streamRenderer: TFTStreamRenderer) {
        self.navEngine = navEngine
        self.ccuManager = ccuManager
        self.streamRenderer = streamRenderer
    }
    
    public var body: some View {
        ZStack {
            // 1. Bản đồ OpenStreetMap tương tác vẽ lộ trình, ghim A/B, ghim điểm nhấn giữ và các vị trí đặc biệt (Nhà, Công ty, Yêu thích)
            OSMMapView(
                navEngine: navEngine,
                trackingMode: $trackingMode,
                orientationMode: orientationMode,
                route: navEngine.activeRoute,
                coordA: pointA?.coordinate,
                coordB: pointB?.coordinate,
                intermediateStopCoords: intermediateStops.map { $0.coordinate },
                droppedPinCoord: droppedPinCoordinate,
                onLocationLongPressed: { coord in
                    handleMapLongPress(coordinate: coord)
                },
                onSelectSpecialPlace: { place in
                    handleSelectSpecialPlace(place)
                }
            )
            .ignoresSafeArea(edges: .top)
            
            VStack {
                
                // Thông báo khi xe đã đến nơi đích
                if let arrivalMsg = navEngine.arrivalMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.checkered.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ĐÃ ĐẾN NƠI!")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundColor(.green)
                            Text(arrivalMsg)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                navEngine.arrivalMessage = nil
                            }
                        }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.04, green: 0.16, blue: 0.08).opacity(0.96))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.green, lineWidth: 1.5)
                    )
                    .shadow(color: Color.green.opacity(0.4), radius: 8)
                    .padding(.horizontal)
                    .padding(.top, isLandscape ? 4 : 8)
                }
                
                // 2. Phía trên: HUD dẫn đường Turn-by-Turn HOẶC Hộp chọn lộ trình Điểm A & Điểm B (Google Maps style)
                if navEngine.isNavigating {
                    navigationHUD
                        .padding(.top, isLandscape ? 4 : 10)
                        .padding(.horizontal)
                } else {
                    routePlannerHeader
                        .padding(.top, isLandscape ? 4 : 10)
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
                
                // 3. Phía dưới: Thẻ chi tiết khi nhấn giữ (Dropped Pin) HOẶC Thẻ tóm tắt lộ trình HOẶC Các nút điều khiển
                if showDroppedPinCard && droppedPinCoordinate != nil {
                    droppedPinCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if navEngine.activeRoute != nil && !navEngine.isNavigating {
                    routePreviewCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    VStack(spacing: 8) {
                        if navEngine.isNavigating && !navEngine.alternativeRoutes.isEmpty {
                            alternativeRoutesNavigationPill
                        }
                        bottomControlsBar
                    }
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
    // MARK: - Hộp nhập lộ trình Điểm A & Điểm B kiểu Google Maps (Tự động thích ứng Dọc / Ngang)
    private var routePlannerHeader: some View {
        Group {
            if isLandscape {
                landscapeRoutePlannerHeader
            } else {
                portraitRoutePlannerHeader
            }
        }
    }
    
    // Giao diện hộp chọn lộ trình khi cầm ngang (Landscape) - Tinh gọn theo hàng ngang
    private var landscapeRoutePlannerHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // Ô Điểm A (Xuất phát)
                Button(action: {
                    searchTarget = .pointA
                    searchQuery = ""
                    showSearchSheet = true
                }) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Color.green).frame(width: 16, height: 16)
                            Text("A").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        }
                        Text(pointA?.title ?? "Vị trí của bạn")
                            .font(.system(size: 13, weight: .medium))
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
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.16))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity)
                
                // Nút Đảo Chiều lộ trình (Swap)
                Button(action: {
                    swapPoints()
                }) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.cyan)
                }
                
                // Ô Điểm B (Điểm đến)
                Button(action: {
                    searchTarget = .pointB
                    searchQuery = ""
                    showSearchSheet = true
                }) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Color.red).frame(width: 16, height: 16)
                            Text("B").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        }
                        Text(pointB?.title ?? "Nhập điểm đến (Điểm B)...")
                            .font(.system(size: 13, weight: pointB == nil ? .regular : .semibold))
                            .foregroundColor(pointB == nil ? .gray : .white)
                            .lineLimit(1)
                        Spacer()
                        if pointB != nil {
                            Button(action: {
                                clearRoute()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 12))
                            }
                        } else if navEngine.isCalculatingRoute {
                            ProgressView().scaleEffect(0.6)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.16))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity)
                
                // Nút Thêm điểm dừng
                Button(action: {
                    searchTarget = .newStop
                    searchQuery = ""
                    showSearchSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                }
            }
            
            // Thanh cuộn các điểm dừng trung gian (nếu có) khi ở chế độ ngang
            if !intermediateStops.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(intermediateStops.enumerated()), id: \.element.id) { index, stop in
                            HStack(spacing: 5) {
                                ZStack {
                                    Circle().fill(Color.orange).frame(width: 16, height: 16)
                                    Text("\(index + 1)").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                                }
                                Text(stop.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                
                                Button(action: {
                                    moveStopUp(at: index)
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(index > 0 ? .cyan : .gray.opacity(0.3))
                                }
                                .disabled(index == 0)
                                
                                Button(action: {
                                    moveStopDown(at: index)
                                }) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(index < intermediateStops.count - 1 ? .cyan : .gray.opacity(0.3))
                                }
                                .disabled(index == intermediateStops.count - 1)
                                
                                Button(action: {
                                    removeIntermediateStop(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.20))
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.96))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 2)
    }
    
    // Giao diện hộp chọn lộ trình khi cầm dọc (Portrait)
    private var portraitRoutePlannerHeader: some View {
        VStack(spacing: 8) {
            // Hàng 1: Ô Điểm A (Xuất phát)
            HStack(spacing: 8) {
                // Nhãn A (Xanh lá)
                ZStack {
                    Circle().fill(Color.green).frame(width: 24, height: 24)
                    Text("A")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Button(action: {
                    searchTarget = .pointA
                    searchQuery = ""
                    showSearchSheet = true
                }) {
                    HStack {
                        Text(pointA?.title ?? "Vị trí của bạn (Điểm A)")
                            .font(.system(size: 13, weight: .medium))
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(white: 0.16))
                    .cornerRadius(8)
                }
                
                // Nút Đảo Chiều toàn bộ lộ trình (Swap A <-> B và đảo ngược thứ tự các điểm dừng)
                Button(action: {
                    swapPoints()
                }) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.cyan)
                }
            }
            
            // Danh sách các điểm dừng trung gian (Đánh số 1, 2, 3...)
            if !intermediateStops.isEmpty {
                ForEach(Array(intermediateStops.enumerated()), id: \.element.id) { index, stop in
                    HStack(spacing: 8) {
                        // Nhãn số thứ tự (1, 2, 3...)
                        ZStack {
                            Circle().fill(Color.orange).frame(width: 24, height: 24)
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        // Tên điểm dừng (Bấm để đổi địa điểm)
                        Button(action: {
                            searchTarget = .editStop(index)
                            searchQuery = ""
                            showSearchSheet = true
                        }) {
                            HStack {
                                Text(stop.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(white: 0.16))
                            .cornerRadius(8)
                        }
                        
                        // Nút Di chuyển Lên (Up arrow)
                        Button(action: {
                            moveStopUp(at: index)
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(index > 0 ? .cyan : .gray.opacity(0.3))
                        }
                        .disabled(index == 0)
                        
                        // Nút Di chuyển Xuống (Down arrow)
                        Button(action: {
                            moveStopDown(at: index)
                        }) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(index < intermediateStops.count - 1 ? .cyan : .gray.opacity(0.3))
                        }
                        .disabled(index == intermediateStops.count - 1)
                        
                        // Nút Xóa điểm dừng
                        Button(action: {
                            removeIntermediateStop(at: index)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.red.opacity(0.85))
                        }
                    }
                }
            }
            
            // Hàng Ô Điểm B (Điểm đến)
            HStack(spacing: 8) {
                // Nhãn B (Đỏ)
                ZStack {
                    Circle().fill(Color.red).frame(width: 24, height: 24)
                    Text("B")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Button(action: {
                    searchTarget = .pointB
                    searchQuery = ""
                    showSearchSheet = true
                }) {
                    HStack {
                        Text(pointB?.title ?? "Nhập điểm đến (Điểm B)...")
                            .font(.system(size: 13, weight: pointB == nil ? .regular : .semibold))
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
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(white: 0.16))
                    .cornerRadius(8)
                }
                
                // Nút "+ Điểm dừng"
                Button(action: {
                    searchTarget = .newStop
                    searchQuery = ""
                    showSearchSheet = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(10)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.96))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.4), radius: 8, y: 4)
    }
    
    // MARK: - Thẻ chi tiết địa điểm khi nhấn giữ (Dropped Pin Location Card)
    private var droppedPinCard: some View {
        VStack(spacing: 12) {
            // Thanh cầm kéo nhỏ phía trên
            Capsule()
                .fill(Color.gray.opacity(0.45))
                .frame(width: 36, height: 4)
                .padding(.top, 2)
            
            HStack(alignment: .top, spacing: 12) {
                // Biểu tượng ghim đỏ
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.red)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    if isLoadingAddress {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text("Đang tra cứu địa chỉ...")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    } else {
                        Text(droppedPinTitle)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    
                    Text(droppedPinSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                    
                    // Khoảng cách ước tính từ vị trí hiện tại của xe
                    if let cur = navEngine.currentLocation, let pinCoord = droppedPinCoordinate {
                        let distMeters = cur.distance(from: CLLocation(latitude: pinCoord.latitude, longitude: pinCoord.longitude))
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.cyan)
                            Text("Cách vị trí hiện tại: \(formatDistance(meters: distMeters))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.cyan)
                        }
                        .padding(.top, 2)
                    }
                }
                
                Spacer()
                
                // Nút Đóng / Bỏ ghim
                Button(action: {
                    dismissDroppedPin()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.8))
                }
            }
            
            // Các nút hành động: Dẫn đường tới đây (Điểm B), Thêm điểm dừng, Đặt làm điểm A, Lưu yêu thích
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    // Nút DẪN ĐƯỜNG ĐẾN ĐÂY (Điểm đến B)
                    Button(action: {
                        navigateCurrentToDroppedPin()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "flag.checkered.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Điểm đến (B)")
                                .font(.system(size: 13, weight: .heavy))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(12)
                        .shadow(color: Color.red.opacity(0.3), radius: 4, y: 2)
                    }
                    
                    // Nút THÊM ĐIỂM DỪNG (Cam/Amber)
                    Button(action: {
                        addDroppedPinAsIntermediateStop()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("+ Thêm điểm dừng")
                                .font(.system(size: 13, weight: .heavy))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(12)
                        .shadow(color: Color.orange.opacity(0.35), radius: 4, y: 2)
                    }
                }
                
                HStack(spacing: 10) {
                    // Nút ĐẶT LÀM ĐIỂM XUẤT PHÁT (Điểm A)
                    Button(action: {
                        setDroppedPinAsPointA()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "location.north.circle.fill")
                                .font(.system(size: 13))
                            Text("Điểm xuất phát A")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(white: 0.22))
                        .cornerRadius(10)
                    }
                    
                    // Nút LƯU VÀO YÊU THÍCH (⭐)
                    Button(action: {
                        toggleFavoriteDroppedPin()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: isDroppedPinFavorite ? "star.fill" : "star")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(isDroppedPinFavorite ? .yellow : .white)
                            Text(isDroppedPinFavorite ? "Đã lưu" : "Lưu yêu thích")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isDroppedPinFavorite ? .yellow : .white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isDroppedPinFavorite ? Color.yellow.opacity(0.2) : Color(white: 0.22))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isDroppedPinFavorite ? Color.yellow.opacity(0.7) : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.97))
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.red.opacity(0.45), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 10, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
    
    // MARK: - Thẻ tóm tắt lộ trình phong cách Google Maps (hiển thị khi vẽ đường xong)
    private var routePreviewCard: some View {
        VStack(spacing: 12) {
            // Danh sách các tuyến đường lựa chọn (Google Maps Alternative Routes Carousel)
            if navEngine.allCalculatedRoutes.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.cyan)
                        Text("CÁC TUYẾN ĐƯỜNG GỢI Ý (CHẠM ĐỂ CHỌN)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.cyan)
                        Spacer()
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(navEngine.allCalculatedRoutes) { r in
                                let isSelected = (r.id == navEngine.activeRoute?.id)
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        navEngine.selectRoute(r)
                                    }
                                    let feedback = UIImpactFeedbackGenerator(style: .medium)
                                    feedback.impactOccurred()
                                }) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 6) {
                                            Text(r.formattedDuration)
                                                .font(.system(size: 18, weight: .heavy))
                                                .foregroundColor(isSelected ? (r.isFastest ? .green : .cyan) : .white)
                                            
                                            Text(r.timeDiffString)
                                                .font(.system(size: 10, weight: .heavy))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(r.isFastest ? Color.green.opacity(0.25) : Color.orange.opacity(0.25))
                                                .foregroundColor(r.isFastest ? .green : .orange)
                                                .cornerRadius(6)
                                        }
                                        
                                        HStack(spacing: 4) {
                                            Text(r.formattedDistance)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white.opacity(0.85))
                                            
                                            Text("•")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                            
                                            Text(r.routeName)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(isSelected ? .white : .gray)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? Color(red: 0.0, green: 0.22, blue: 0.35).opacity(0.85) : Color(white: 0.16))
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(isSelected ? Color.cyan : Color.gray.opacity(0.4), lineWidth: isSelected ? 2.0 : 1.0)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            } else {
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
                            Text(navEngine.activeRoute?.routeName.isEmpty == false ? navEngine.activeRoute!.routeName : "Tuyến đường tối ưu xe máy (Valhalla OSM)")
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
            }
            
            HStack(spacing: 12) {
                // Nút Đóng nếu có nhiều tuyến
                if navEngine.allCalculatedRoutes.count > 1 {
                    Button(action: {
                        clearRoute()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(14)
                            .background(Color(white: 0.2))
                            .cornerRadius(12)
                    }
                }
                
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
        .padding(14)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.96))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.5), radius: 10, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
    
    // MARK: - Thanh chuyển nhanh sang tuyến thay thế khi đang điều hướng
    private var alternativeRoutesNavigationPill: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(navEngine.alternativeRoutes) { alt in
                    Button(action: {
                        withAnimation {
                            navEngine.selectRoute(alt)
                            toastMessage = "Đã chọn: \(alt.routeName)"
                            showOrientationToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                showOrientationToast = false
                            }
                        }
                        let feedback = UIImpactFeedbackGenerator(style: .medium)
                        feedback.impactOccurred()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.cyan)
                            Text("Đổi: \(alt.routeName)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text("(\(alt.timeDiffString))")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(alt.isFastest ? .green : .orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.08, green: 0.14, blue: 0.22).opacity(0.92))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.cyan.opacity(0.6), lineWidth: 1.2)
                        )
                        .shadow(radius: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
        }
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
            if navEngine.isRerouting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                    .scaleEffect(1.1)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("ĐANG TÍNH LẠI LỘ TRÌNH...")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.yellow)
                    Text("Phát hiện bạn đã rẽ sang hướng khác")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            } else {
                Image(systemName: navEngine.currentInstruction.direction.iconName)
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(navEngine.currentInstruction.formattedDistance)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.green)
                        
                        Text("•")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray)
                        
                        Text(navEngine.currentInstruction.nextRoadName.isEmpty ? "Đang đi theo lộ trình" : navEngine.currentInstruction.nextRoadName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    
                    if !navEngine.currentInstruction.detailedInstruction.isEmpty {
                        Text(navEngine.currentInstruction.detailedInstruction)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Cụm thông tin ETA và nút dừng lộ trình
            VStack(alignment: .trailing, spacing: 4) {
                Button(action: {
                    clearRoute()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red.opacity(0.9))
                }
                
                if !navEngine.currentInstruction.etaString.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(navEngine.currentInstruction.etaString)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.white)
                        Text(navEngine.currentInstruction.remainingTimeFormatted)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.96))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(navEngine.isRerouting ? Color.yellow.opacity(0.8) : Color.cyan.opacity(0.3), lineWidth: 1.5)
        )
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
            .navigationTitle({
                switch searchTarget {
                case .pointA: return "Chọn Điểm A (Xuất phát)"
                case .pointB: return "Chọn Điểm B (Điểm đến)"
                case .newStop: return "Thêm Điểm Dừng Trung Gian"
                case .editStop(let idx): return "Đổi Điểm Dừng \(idx + 1)"
                }
            }())
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
        switch searchTarget {
        case .pointA:
            pointA = routeItem
        case .pointB:
            pointB = routeItem
        case .newStop:
            intermediateStops.append(routeItem)
        case .editStop(let idx):
            if idx >= 0 && idx < intermediateStops.count {
                intermediateStops[idx] = routeItem
            }
        }
        showSearchSheet = false
        triggerRouteCalculation()
    }
    
    private func triggerRouteCalculation() {
        guard let startCoord = effectivePointACoordinate, let dest = pointB else { return }
        let stopCoords = intermediateStops.map { $0.coordinate }
        navEngine.calculateRoute(from: startCoord, intermediateStops: stopCoords, to: dest.coordinate, destinationTitle: dest.title, autoStart: false)
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
        intermediateStops.reverse()
        triggerRouteCalculation()
    }
    
    private func moveStopUp(at index: Int) {
        guard index > 0 && index < intermediateStops.count else { return }
        withAnimation {
            intermediateStops.swapAt(index, index - 1)
            triggerRouteCalculation()
        }
    }
    
    private func moveStopDown(at index: Int) {
        guard index >= 0 && index < intermediateStops.count - 1 else { return }
        withAnimation {
            intermediateStops.swapAt(index, index + 1)
            triggerRouteCalculation()
        }
    }
    
    private func removeIntermediateStop(at index: Int) {
        guard index >= 0 && index < intermediateStops.count else { return }
        withAnimation {
            intermediateStops.remove(at: index)
            triggerRouteCalculation()
        }
    }
    
    private func addDroppedPinAsIntermediateStop() {
        guard let pinCoord = droppedPinCoordinate else { return }
        let title = droppedPinTitle.isEmpty ? "Điểm dừng \(intermediateStops.count + 1)" : droppedPinTitle
        let subtitle = droppedPinSubtitle
        
        let stopItem = RoutePointItem(
            title: title,
            subtitle: subtitle,
            coordinate: pinCoord,
            isCurrentLocation: false
        )
        withAnimation {
            intermediateStops.append(stopItem)
            dismissDroppedPin()
            triggerRouteCalculation()
        }
    }
    
    private func startNavigation() {
        let stopCoords = intermediateStops.map { $0.coordinate }
        if pointA != nil, let curLoc = navEngine.currentLocation, let dest = pointB {
            let destTitle = dest.title
            pointA = nil
            navEngine.calculateRoute(from: curLoc.coordinate, intermediateStops: stopCoords, to: dest.coordinate, destinationTitle: destTitle, autoStart: true)
        } else if let startCoord = effectivePointACoordinate, let dest = pointB {
            navEngine.calculateRoute(from: startCoord, intermediateStops: stopCoords, to: dest.coordinate, destinationTitle: dest.title, autoStart: true)
        } else {
            navEngine.startActiveNavigation()
        }
        ccuManager.startStreaming()
        trackingMode = .follow
        orientationMode = .headingTracking
        streamRenderer.isNorthUp = false
    }
    
    private func clearRoute() {
        pointA = nil
        pointB = nil
        intermediateStops.removeAll()
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
    
    // MARK: - Xử lý khi nhấn giữ chọn địa điểm trên bản đồ
    private func handleMapLongPress(coordinate: CLLocationCoordinate2D) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            droppedPinCoordinate = coordinate
            droppedPinTitle = "Đang tra cứu địa chỉ..."
            droppedPinSubtitle = String(format: "Tọa độ: %.5f, %.5f", coordinate.latitude, coordinate.longitude)
            isLoadingAddress = true
            showDroppedPinCard = true
        }
        
        navEngine.reverseGeocode(coordinate: coordinate) { title, subtitle in
            withAnimation {
                self.droppedPinTitle = title
                self.droppedPinSubtitle = subtitle
                self.isLoadingAddress = false
            }
        }
    }
    
    private func dismissDroppedPin() {
        withAnimation(.easeInOut(duration: 0.2)) {
            droppedPinCoordinate = nil
            showDroppedPinCard = false
        }
    }
    
    private var isDroppedPinFavorite: Bool {
        guard let coord = droppedPinCoordinate else { return false }
        return navEngine.favoriteLocations.contains { fav in
            abs(fav.latitude - coord.latitude) < 0.0001 && abs(fav.longitude - coord.longitude) < 0.0001
        }
    }
    
    private func toggleFavoriteDroppedPin() {
        guard let coord = droppedPinCoordinate else { return }
        let title = droppedPinTitle.isEmpty ? "Điểm đã ghim" : droppedPinTitle
        let subtitle = droppedPinSubtitle
        
        if let existing = navEngine.favoriteLocations.first(where: {
            abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001
        }) {
            navEngine.removeFavoriteLocation(id: existing.id)
        } else {
            let newFav = SavedLocation(
                title: title,
                subtitle: subtitle,
                latitude: coord.latitude,
                longitude: coord.longitude,
                type: .favorite
            )
            navEngine.addFavoriteLocation(newFav)
        }
    }
    
    private func navigateCurrentToDroppedPin() {
        guard let pinCoord = droppedPinCoordinate else { return }
        let title = droppedPinTitle.isEmpty ? "Điểm đã chọn" : droppedPinTitle
        let subtitle = droppedPinSubtitle
        
        withAnimation {
            pointB = RoutePointItem(
                title: title,
                subtitle: subtitle,
                coordinate: pinCoord,
                isCurrentLocation: false
            )
            dismissDroppedPin()
            triggerRouteCalculation()
        }
    }
    
    private func setDroppedPinAsPointA() {
        guard let pinCoord = droppedPinCoordinate else { return }
        let title = droppedPinTitle.isEmpty ? "Điểm đã chọn" : droppedPinTitle
        let subtitle = droppedPinSubtitle
        
        withAnimation {
            pointA = RoutePointItem(
                title: title,
                subtitle: subtitle,
                coordinate: pinCoord,
                isCurrentLocation: false
            )
            dismissDroppedPin()
            triggerRouteCalculation()
        }
    }
    
    // MARK: - Dẫn đường đến địa điểm đặc biệt (Nhà, Công ty, Yêu thích) khi nhấn nút trên bản đồ
    private func handleSelectSpecialPlace(_ place: SpecialPlaceAnnotation) {
        let destTitle = place.title ?? "Điểm đến"
        let subtitle = place.subtitle ?? ""
        withAnimation {
            pointB = RoutePointItem(
                title: destTitle,
                subtitle: subtitle,
                coordinate: place.coordinate,
                isCurrentLocation: false
            )
            dismissDroppedPin()
            triggerRouteCalculation()
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
        
        // Mặc định dùng ngói CartoDB Voyager bản quyền chính thức theo API Key của người dùng
        super.init(urlTemplate: template)
        self.canReplaceMapContent = true
        self.maximumZ = 19
        self.tileSize = CGSize(width: 256, height: 256)
        memoryCache.countLimit = 350
    }
    
    public override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let tmpl = OSMTileEngine.shared.tileUrlTemplate
        let urlStr = tmpl
            .replacingOccurrences(of: "{z}", with: "\(path.z)")
            .replacingOccurrences(of: "{x}", with: "\(path.x)")
            .replacingOccurrences(of: "{y}", with: "\(path.y)")
        return URL(string: urlStr) ?? super.url(forTilePath: path)
    }
    
    public override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = "\(path.z)_\(path.x)_\(path.y)" as NSString
        if let cached = memoryCache.object(forKey: key) {
            result(cached as Data, nil)
            return
        }
        
        // Kiểm tra bộ nhớ đệm ổ đĩa dùng chung với OSMTileEngine (chia sẻ cache offline giữa iPhone và xe máy)
        if let diskData = OSMTileEngine.shared.getCachedTileData(x: path.x, y: path.y, z: path.z) {
            memoryCache.setObject(diskData as NSData, forKey: key)
            result(diskData, nil)
            return
        }
        
        // Sử dụng pipeline nạp ngói phần cứng đa luồng tích hợp của Apple MapKit (siêu tốc qua Edge CDN)
        super.loadTile(at: path) { [weak self] data, error in
            guard let self = self else { return }
            if let data = data, data.count > 1000 {
                self.memoryCache.setObject(data as NSData, forKey: key)
                OSMTileEngine.shared.saveTileData(data, x: path.x, y: path.y, z: path.z)
                result(data, nil)
            } else {
                // Fallback: Thử máy chủ OpenStreetMap FOSSGIS
                let fbUrlStr = "https://tile.openstreetmap.de/\(path.z)/\(path.x)/\(path.y).png"
                if let fbUrl = URL(string: fbUrlStr) {
                    var req = URLRequest(url: fbUrl)
                    req.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
                    req.timeoutInterval = 4
                    self.session.dataTask(with: req) { [weak self] d2, r2, e2 in
                        if let d2 = d2, (r2 as? HTTPURLResponse)?.statusCode == 200, d2.count > 1000 {
                            self?.memoryCache.setObject(d2 as NSData, forKey: key)
                            OSMTileEngine.shared.saveTileData(d2, x: path.x, y: path.y, z: path.z)
                            result(d2, nil)
                        } else {
                            result(nil, error ?? e2)
                        }
                    }.resume()
                } else {
                    result(nil, error)
                }
            }
        }
    }
}

// MARK: - Lớp Polyline lộ trình tùy biến hỗ trợ Tuyến chính / Tuyến gợi ý thay thế
public class NavRoutePolyline: MKPolyline {
    public var routeId: UUID = UUID()
    public var isActiveRoute: Bool = false
    public var routeName: String = ""
    public var timeDiffString: String = ""
}

// MARK: - View Bản đồ OpenStreetMap tương tác (Vẽ lộ trình Google Maps, Ghim Điểm A/B, Điểm dừng trung gian & Điểm nhấn giữ)
public struct OSMMapView: UIViewRepresentable {
    @ObservedObject var navEngine: NavigationEngine
    @Binding var trackingMode: MapUserTrackingMode
    var orientationMode: MapOrientationMode
    var route: OSMRoute?
    var coordA: CLLocationCoordinate2D?
    var coordB: CLLocationCoordinate2D?
    var intermediateStopCoords: [CLLocationCoordinate2D] = []
    var droppedPinCoord: CLLocationCoordinate2D?
    var onLocationLongPressed: ((CLLocationCoordinate2D) -> Void)?
    var onSelectSpecialPlace: ((SpecialPlaceAnnotation) -> Void)?
    
    public init(
        navEngine: NavigationEngine,
        trackingMode: Binding<MapUserTrackingMode>,
        orientationMode: MapOrientationMode = .headingTracking,
        route: OSMRoute?,
        coordA: CLLocationCoordinate2D? = nil,
        coordB: CLLocationCoordinate2D? = nil,
        intermediateStopCoords: [CLLocationCoordinate2D] = [],
        droppedPinCoord: CLLocationCoordinate2D? = nil,
        onLocationLongPressed: ((CLLocationCoordinate2D) -> Void)? = nil,
        onSelectSpecialPlace: ((SpecialPlaceAnnotation) -> Void)? = nil
    ) {
        self.navEngine = navEngine
        self._trackingMode = trackingMode
        self.orientationMode = orientationMode
        self.route = route
        self.coordA = coordA
        self.coordB = coordB
        self.intermediateStopCoords = intermediateStopCoords
        self.droppedPinCoord = droppedPinCoord
        self.onLocationLongPressed = onLocationLongPressed
        self.onSelectSpecialPlace = onSelectSpecialPlace
    }
    
    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false // Tắt la bàn mặc định ở góc trên (bị hộp tìm kiếm che)
        mapView.showsScale = true
        
        // Thêm nhận diện cử chỉ chạm vào tuyến đường thay thế trên bản đồ (Tap to select Alternative Route)
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)
        
        // Thêm nhận diện cử chỉ nhấn giữ bản đồ để chọn địa điểm (Long Press to Drop Pin)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        mapView.addGestureRecognizer(longPress)
        
        // Cấu hình ngói bản đồ OpenStreetMap ở level .aboveRoads
        let osmOverlay = CustomOSMTileOverlay()
        context.coordinator.currentTileOverlay = osmOverlay
        context.coordinator.currentTileTemplate = OSMTileEngine.shared.tileUrlTemplate
        mapView.addOverlay(osmOverlay, level: .aboveRoads)
        
        // Thêm nút La bàn MKCompassButton riêng biệt, định vị nằm ngay DƯỚI thanh tìm kiếm / HUD
        let compass = MKCompassButton(mapView: mapView)
        compass.compassVisibility = .visible // Luôn hiển thị kim la bàn chỉ Bắc cho người lái xe
        compass.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(compass)
        context.coordinator.compassButton = compass
        
        let topConstraint = compass.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 145)
        let trailingConstraint = compass.trailingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        NSLayoutConstraint.activate([topConstraint, trailingConstraint])
        context.coordinator.compassTopConstraint = topConstraint
        context.coordinator.compassTrailingConstraint = trailingConstraint
        
        if let loc = navEngine.currentLocation {
            let region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)
            mapView.setRegion(region, animated: false)
        }
        
        return mapView
    }
    
    public func updateUIView(_ uiView: MKMapView, context: Context) {
        // Tự động tải lại ngói bản đồ khi người dùng thay đổi giao diện bản đồ trong Cài đặt
        if context.coordinator.currentTileTemplate != OSMTileEngine.shared.tileUrlTemplate {
            context.coordinator.currentTileTemplate = OSMTileEngine.shared.tileUrlTemplate
            if let old = context.coordinator.currentTileOverlay {
                uiView.removeOverlay(old)
            }
            let newOverlay = CustomOSMTileOverlay()
            context.coordinator.currentTileOverlay = newOverlay
            uiView.addOverlay(newOverlay, level: .aboveRoads)
        }
        
        context.coordinator.updateRoute(on: uiView, newRoute: route, coordA: coordA, stopCoords: intermediateStopCoords, coordB: coordB)
        context.coordinator.updateDroppedPin(on: uiView, coord: droppedPinCoord)
        context.coordinator.updateSpecialPlaces(on: uiView)
        
        let isNavigating = navEngine.isNavigating
        let isLandscape = uiView.traitCollection.verticalSizeClass == .compact
        
        // Tự động điều chỉnh khoảng cách trên của La bàn để không bao giờ bị thanh nhập địa điểm che
        let targetTopOffset: CGFloat = isLandscape ? (isNavigating ? 60 : 68) : (isNavigating ? 85 : 145)
        if context.coordinator.compassTopConstraint?.constant != targetTopOffset {
            context.coordinator.compassTopConstraint?.constant = targetTopOffset
            UIView.animate(withDuration: 0.25) {
                uiView.layoutIfNeeded()
            }
        }
        
        if trackingMode == .follow, let loc = navEngine.currentLocation {
            let speedKmh = max(0.0, loc.speed * 3.6)
            
            // Giữ nguyên mức zoom hiện tại của người dùng, không bao giờ tự ý zoom vào khi bấm đổi hướng
            let currentDistance: CLLocationDistance = {
                let d = uiView.camera.centerCoordinateDistance
                if d > 120.0 {
                    return d
                }
                return speedKmh > 65.0 ? 800.0 : 500.0
            }()
            
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
                
                camera = MKMapCamera(
                    lookingAtCenter: loc.coordinate,
                    fromDistance: currentDistance,
                    pitch: pitch,
                    heading: effectiveHeading
                )
                
            case .northUp:
                // Cố định phương Bắc (North-Up):
                // Bản đồ luôn hướng thẳng phương Bắc (heading = 0.0°), góc nhìn phẳng 2D từ trên xuống (pitch = 0.0°)
                // GIỮ NGUYÊN MỨC ZOOM HIỆN TẠI (currentDistance), CHỈ XOAY HƯỚNG BẢN ĐỒ
                camera = MKMapCamera(
                    lookingAtCenter: loc.coordinate,
                    fromDistance: currentDistance,
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
        var activePolyline: NavRoutePolyline?
        var alternativePolylines: [NavRoutePolyline] = []
        var routeAnnotations: [MKAnnotation] = []
        var droppedPinAnnotation: RoutePointAnnotation?
        var compassButton: MKCompassButton?
        var compassTopConstraint: NSLayoutConstraint?
        var compassTrailingConstraint: NSLayoutConstraint?
        var currentTileOverlay: CustomOSMTileOverlay?
        var currentTileTemplate: String = ""
        private var lastRouteKey: String = ""
        var specialPlaceAnnotations: [SpecialPlaceAnnotation] = []
        private var lastSpecialPlacesKey: String = ""
        
        init(_ parent: OSMMapView) {
            self.parent = parent
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            
            DispatchQueue.main.async { [weak self] in
                self?.parent.onLocationLongPressed?(coord)
            }
        }
        
        // MARK: - Nhận diện chạm vào tuyến đường thay thế trên bản đồ (Google Maps style Tap Route to Select)
        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            guard let mapView = gesture.view as? MKMapView else { return }
            let tapPoint = gesture.location(in: mapView)
            
            let alternatives = parent.navEngine.alternativeRoutes
            guard !alternatives.isEmpty else { return }
            
            var closestRoute: OSMRoute? = nil
            var minDistance: CGFloat = 36.0 // Ngưỡng nhận diện chạm 36 points (~1cm màn hình iPhone)
            
            for alt in alternatives {
                let d = distanceToRoute(tapPoint: tapPoint, coordinates: alt.coordinates, in: mapView)
                if d < minDistance {
                    minDistance = d
                    closestRoute = alt
                }
            }
            
            if let selected = closestRoute {
                let feedback = UIImpactFeedbackGenerator(style: .medium)
                feedback.impactOccurred()
                
                DispatchQueue.main.async { [weak self] in
                    self?.parent.navEngine.selectRoute(selected)
                }
            }
        }
        
        private func distanceToRoute(tapPoint: CGPoint, coordinates: [CLLocationCoordinate2D], in mapView: MKMapView) -> CGFloat {
            guard coordinates.count >= 2 else { return .infinity }
            var minDistance: CGFloat = .infinity
            var prevPoint: CGPoint? = nil
            
            // Lấy mẫu nếu tuyến có quá nhiều điểm (tối ưu hóa hiệu năng)
            let step = max(1, coordinates.count / 400)
            for i in stride(from: 0, to: coordinates.count, by: step) {
                let pt = mapView.convert(coordinates[i], toPointTo: mapView)
                if let p1 = prevPoint {
                    let d = pointToSegmentDistance(p: tapPoint, a: p1, b: pt)
                    if d < minDistance {
                        minDistance = d
                    }
                }
                prevPoint = pt
            }
            return minDistance
        }
        
        private func pointToSegmentDistance(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lenSq = dx * dx + dy * dy
            if lenSq == 0 {
                return hypot(p.x - a.x, p.y - a.y)
            }
            let t = max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
            let projX = a.x + t * dx
            let projY = a.y + t * dy
            return hypot(p.x - projX, p.y - projY)
        }
        
        public func updateDroppedPin(on mapView: MKMapView, coord: CLLocationCoordinate2D?) {
            if let existing = droppedPinAnnotation {
                if existing.coordinate.latitude == coord?.latitude && existing.coordinate.longitude == coord?.longitude {
                    return
                }
                mapView.removeAnnotation(existing)
                droppedPinAnnotation = nil
            }
            
            guard let c = coord else { return }
            let pin = RoutePointAnnotation(coordinate: c, isPointA: false, isDroppedPin: true, title: "Địa điểm đã chọn", subtitle: "Nhấn giữ điểm khác để thay đổi")
            droppedPinAnnotation = pin
            mapView.addAnnotation(pin)
            mapView.selectAnnotation(pin, animated: true)
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
            if let navPoly = overlay as? NavRoutePolyline {
                let renderer = MKPolylineRenderer(polyline: navPoly)
                if navPoly.isActiveRoute {
                    // Tuyến chính đang dẫn đường: Màu xanh Yamaha Neon Cyan siêu sáng 11.0pt
                    renderer.strokeColor = UIColor(red: 0.0, green: 0.70, blue: 1.0, alpha: 0.98)
                    renderer.lineWidth = 11.0
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                } else {
                    // Tuyến gợi ý thay thế (Google Maps style): Màu xám khói slate gray tương phản 7.5pt
                    renderer.strokeColor = UIColor(red: 0.50, green: 0.60, blue: 0.70, alpha: 0.88)
                    renderer.lineWidth = 7.5
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                }
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.0, green: 0.70, blue: 1.0, alpha: 0.98)
                renderer.lineWidth = 11.0
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
            
            // 1. Điểm đặc biệt đã lưu (Nhà, Công ty, Yêu thích)
            if let special = annotation as? SpecialPlaceAnnotation {
                let id = "SpecialMarker_\(special.placeType.rawValue)"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                
                view.annotation = special
                view.canShowCallout = true
                view.animatesWhenAdded = true
                
                let iconView = UIImageView(frame: CGRect(x: 0, y: 0, width: 26, height: 26))
                iconView.contentMode = .scaleAspectFit
                
                switch special.placeType {
                case .home:
                    view.markerTintColor = UIColor.systemOrange
                    view.glyphImage = UIImage(systemName: "house.fill")
                    view.displayPriority = .required
                    iconView.image = UIImage(systemName: "house.fill")
                    iconView.tintColor = .systemOrange
                case .work:
                    view.markerTintColor = UIColor(red: 0.10, green: 0.50, blue: 1.0, alpha: 1.0)
                    view.glyphImage = UIImage(systemName: "briefcase.fill")
                    view.displayPriority = .required
                    iconView.image = UIImage(systemName: "briefcase.fill")
                    iconView.tintColor = UIColor(red: 0.10, green: 0.50, blue: 1.0, alpha: 1.0)
                case .favorite:
                    view.markerTintColor = UIColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
                    view.glyphImage = UIImage(systemName: "star.fill")
                    view.displayPriority = .defaultHigh
                    iconView.image = UIImage(systemName: "star.fill")
                    iconView.tintColor = UIColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0)
                case .parking:
                    view.markerTintColor = UIColor(red: 0.58, green: 0.20, blue: 0.92, alpha: 1.0) // Deep Purple
                    view.glyphImage = UIImage(systemName: "parkingsign.circle.fill")
                    view.displayPriority = .required
                    iconView.image = UIImage(systemName: "parkingsign.circle.fill")
                    iconView.tintColor = UIColor(red: 0.58, green: 0.20, blue: 0.92, alpha: 1.0)
                }
                
                view.leftCalloutAccessoryView = iconView
                
                let navButton = UIButton(type: .custom)
                navButton.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
                let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
                navButton.setImage(UIImage(systemName: "arrow.triangle.turn.up.right.circle.fill", withConfiguration: config), for: .normal)
                navButton.tintColor = UIColor.systemGreen
                view.rightCalloutAccessoryView = navButton
                
                return view
            }
            
            // 2. Điểm A, Điểm B, Điểm dừng trung gian (1, 2, 3...), Dropped Pin
            guard let ptAnn = annotation as? RoutePointAnnotation else { return nil }
            let id: String
            if ptAnn.isDroppedPin {
                id = "DroppedPinMarker"
            } else if let stopIdx = ptAnn.stopIndex {
                id = "StopMarker_\(stopIdx)"
            } else if ptAnn.isPointA {
                id = "PointAMarker"
            } else {
                id = "PointBMarker"
            }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            
            view.annotation = ptAnn
            view.canShowCallout = true
            if ptAnn.isPointA {
                view.markerTintColor = UIColor.systemGreen
                view.glyphText = "A"
            } else if let stopIdx = ptAnn.stopIndex {
                view.markerTintColor = UIColor.systemOrange
                view.glyphText = "\(stopIdx)"
            } else if ptAnn.isDroppedPin {
                view.markerTintColor = UIColor.systemRed
                view.glyphImage = UIImage(systemName: "mappin.circle.fill")
                view.animatesWhenAdded = true
            } else {
                view.markerTintColor = UIColor.systemRed
                view.glyphText = "B"
            }
            return view
        }
        
        // Bấm nút chỉ đường trên Callout của địa điểm đặc biệt để lập tức dẫn đường
        public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let special = view.annotation as? SpecialPlaceAnnotation {
                parent.onSelectSpecialPlace?(special)
            }
        }
        
        // MARK: - Cập nhật và hiển thị các địa điểm đặc biệt đã lưu (Nhà, Công ty, Yêu thích, Vị trí đỗ xe) lên bản đồ lớn
        public func updateSpecialPlaces(on mapView: MKMapView) {
            var placesToDisplay: [(coord: CLLocationCoordinate2D, type: SpecialPlaceType, title: String, subtitle: String)] = []
            
            // 1. Nhà (Home)
            if let home = SavedPlacesManager.shared.homePlace {
                placesToDisplay.append((home.coordinate, .home, home.name, home.address.isEmpty ? "Nhà riêng • Chạm nút chỉ đường" : "\(home.address) • Chạm nút chỉ đường"))
            } else if let homeLoc = parent.navEngine.homeLocation {
                placesToDisplay.append((homeLoc.coordinate, .home, homeLoc.title, homeLoc.subtitle.isEmpty ? "Nhà riêng • Chạm nút chỉ đường" : "\(homeLoc.subtitle) • Chạm nút chỉ đường"))
            }
            
            // 2. Cơ quan / Nơi làm việc (Work)
            if let work = SavedPlacesManager.shared.workPlace {
                placesToDisplay.append((work.coordinate, .work, work.name, work.address.isEmpty ? "Nơi làm việc • Chạm nút chỉ đường" : "\(work.address) • Chạm nút chỉ đường"))
            } else if let workLoc = parent.navEngine.workLocation {
                placesToDisplay.append((workLoc.coordinate, .work, workLoc.title, workLoc.subtitle.isEmpty ? "Nơi làm việc • Chạm nút chỉ đường" : "\(workLoc.subtitle) • Chạm nút chỉ đường"))
            }
            
            // 3. Mục yêu thích (Favorites)
            var seenCoords: [CLLocationCoordinate2D] = []
            for fav in SavedPlacesManager.shared.favoritePlaces {
                let c = fav.coordinate
                if !seenCoords.contains(where: { abs($0.latitude - c.latitude) < 0.0001 && abs($0.longitude - c.longitude) < 0.0001 }) {
                    seenCoords.append(c)
                    placesToDisplay.append((c, .favorite, fav.name, fav.address.isEmpty ? "Yêu thích • Chạm nút chỉ đường" : "\(fav.address) • Chạm nút chỉ đường"))
                }
            }
            for fav in parent.navEngine.favoriteLocations {
                let c = fav.coordinate
                if !seenCoords.contains(where: { abs($0.latitude - c.latitude) < 0.0001 && abs($0.longitude - c.longitude) < 0.0001 }) {
                    seenCoords.append(c)
                    placesToDisplay.append((c, .favorite, fav.title, fav.subtitle.isEmpty ? "Yêu thích • Chạm nút chỉ đường" : "\(fav.subtitle) • Chạm nút chỉ đường"))
                }
            }
            
            // 4. Vị trí đỗ xe máy gần nhất (Find My Bike)
            if let parked = ParkingLocationManager.shared.lastParkedLocation {
                let sub = parked.address.isEmpty
                    ? "Đỗ lúc \(parked.relativeTimeString) (\(parked.formattedDistance())) • Chạm nút tìm xe"
                    : "\(parked.address) • Đỗ lúc \(parked.relativeTimeString) (\(parked.formattedDistance())) • Chạm nút tìm xe"
                placesToDisplay.append((parked.coordinate, .parking, "Vị trí xe (\(parked.bikeName))", sub))
            }
            
            let key = placesToDisplay.map { "\($0.type.rawValue)_\($0.coord.latitude)_\($0.coord.longitude)_\($0.title)" }.joined(separator: "|")
            guard key != lastSpecialPlacesKey else { return }
            lastSpecialPlacesKey = key
            
            mapView.removeAnnotations(specialPlaceAnnotations)
            specialPlaceAnnotations.removeAll()
            
            for p in placesToDisplay {
                let ann = SpecialPlaceAnnotation(coordinate: p.coord, placeType: p.type, title: p.title, subtitle: p.subtitle)
                specialPlaceAnnotations.append(ann)
                mapView.addAnnotation(ann)
            }
        }
        
        public func updateRoute(
            on mapView: MKMapView,
            newRoute: OSMRoute?,
            coordA: CLLocationCoordinate2D?,
            stopCoords: [CLLocationCoordinate2D] = [],
            coordB: CLLocationCoordinate2D?
        ) {
            let routeId = newRoute?.id.uuidString ?? ""
            let altCount = parent.navEngine.alternativeRoutes.count
            let stopsKey = stopCoords.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";")
            let key = "\(routeId)_\(altCount)_\(coordA?.latitude ?? 0)_\(stopsKey)_\(coordB?.latitude ?? 0)"
            guard key != lastRouteKey else { return }
            lastRouteKey = key
            
            // Xóa toàn bộ polyline cũ
            if let oldActive = activePolyline {
                mapView.removeOverlay(oldActive)
                activePolyline = nil
            }
            for alt in alternativePolylines {
                mapView.removeOverlay(alt)
            }
            alternativePolylines.removeAll()
            
            mapView.removeAnnotations(routeAnnotations)
            routeAnnotations.removeAll()
            
            // 1. Thêm các tuyến đường thay thế (Alternative Routes) TRƯỚC để chúng nằm dưới
            let alternatives = parent.navEngine.alternativeRoutes
            for alt in alternatives where !alt.coordinates.isEmpty {
                let poly = NavRoutePolyline(coordinates: alt.coordinates, count: alt.coordinates.count)
                poly.routeId = alt.id
                poly.isActiveRoute = false
                poly.routeName = alt.routeName
                poly.timeDiffString = alt.timeDiffString
                alternativePolylines.append(poly)
                mapView.addOverlay(poly, level: .aboveLabels)
            }
            
            // 2. Thêm tuyến chính đang chọn (Active Route) SAU để nằm trên cùng
            if let r = newRoute, !r.coordinates.isEmpty {
                let poly = NavRoutePolyline(coordinates: r.coordinates, count: r.coordinates.count)
                poly.routeId = r.id
                poly.isActiveRoute = true
                poly.routeName = r.routeName
                poly.timeDiffString = r.timeDiffString
                activePolyline = poly
                mapView.addOverlay(poly, level: .aboveLabels)
            }
            
            // Ghim Điểm A (Xanh lá - A)
            if let a = coordA {
                let annA = RoutePointAnnotation(coordinate: a, isPointA: true, title: "Điểm A (Xuất phát)")
                routeAnnotations.append(annA)
                mapView.addAnnotation(annA)
            }
            
            // Ghim các điểm dừng trung gian (Cam - 1, 2, 3...)
            for (idx, sc) in stopCoords.enumerated() {
                let annStop = RoutePointAnnotation(coordinate: sc, stopIndex: idx + 1, title: "\(idx + 1). Điểm dừng \(idx + 1)")
                routeAnnotations.append(annStop)
                mapView.addAnnotation(annStop)
            }
            
            // Ghim Điểm B (Đỏ - B)
            if let b = coordB {
                let annB = RoutePointAnnotation(coordinate: b, isPointA: false, title: "Điểm B (Điểm đến)")
                routeAnnotations.append(annB)
                mapView.addAnnotation(annB)
            }
            
            // Căn chỉnh bao quát lộ trình nếu đang ở màn hình xem trước lộ trình
            if !self.parent.navEngine.isNavigating, let poly = activePolyline {
                var unionRect = poly.boundingMapRect
                for altPoly in alternativePolylines {
                    unionRect = unionRect.union(altPoly.boundingMapRect)
                }
                let padding = UIEdgeInsets(top: 160, left: 50, bottom: 250, right: 50)
                mapView.setVisibleMapRect(unionRect, edgePadding: padding, animated: true)
            }
        }
    }
}
