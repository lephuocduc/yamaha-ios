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

// MARK: - Annotation ghim Điểm A, Điểm B & Điểm nhấn giữ trên bản đồ
public class RoutePointAnnotation: NSObject, MKAnnotation {
    public var coordinate: CLLocationCoordinate2D
    public var isPointA: Bool
    public var isDroppedPin: Bool
    public var title: String?
    public var subtitle: String?
    
    public init(coordinate: CLLocationCoordinate2D, isPointA: Bool = false, isDroppedPin: Bool = false, title: String, subtitle: String? = nil) {
        self.coordinate = coordinate
        self.isPointA = isPointA
        self.isDroppedPin = isDroppedPin
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
    @ObservedObject private var callManager = CallNotificationManager.shared
    
    // Quản lý Điểm A (Xuất phát) và Điểm B (Điểm đến)
    @State private var pointA: RoutePointItem? = nil // nil = Vị trí GPS hiện tại của người dùng
    @State private var pointB: RoutePointItem? = nil
    
    // Quản lý Điểm ghim khi nhấn giữ trên bản đồ (Dropped Pin Long Press)
    @State private var droppedPinCoordinate: CLLocationCoordinate2D? = nil
    @State private var droppedPinTitle: String = ""
    @State private var droppedPinSubtitle: String = ""
    @State private var isLoadingAddress: Bool = false
    @State private var showDroppedPinCard: Bool = false
    
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
            // 1. Bản đồ OpenStreetMap tương tác vẽ lộ trình, ghim A/B và ghim điểm nhấn giữ
            OSMMapView(
                navEngine: navEngine,
                trackingMode: $trackingMode,
                orientationMode: orientationMode,
                route: navEngine.activeRoute,
                coordA: pointA?.coordinate,
                coordB: pointB?.coordinate,
                droppedPinCoord: droppedPinCoordinate,
                onLocationLongPressed: { coord in
                    handleMapLongPress(coordinate: coord)
                }
            )
            .ignoresSafeArea(edges: .top)
            
            VStack {
                // Banner cuộc gọi đến trên màn hình dẫn đường
                if callManager.isCallRinging {
                    HStack(spacing: 12) {
                        Image(systemName: "phone.badge.waveform.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CUỘC GỌI ĐẾN")
                                .font(.subheadline)
                                .fontWeight(.heavy)
                                .foregroundColor(.white)
                            Text("Bấm (+) trên cùm xe để nghe, (-) để từ chối")
                                .font(.caption)
                                .foregroundColor(Color.yellow)
                        }
                        
                        Spacer()
                        
                        Button(action: { callManager.answerCall() }) {
                            Image(systemName: "phone.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                        
                        Button(action: { callManager.rejectCall() }) {
                            Image(systemName: "phone.down.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.82, green: 0.08, blue: 0.16))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.yellow, lineWidth: 2)
                    )
                    .padding(.horizontal)
                } else if callManager.isCallConnected {
                    HStack(spacing: 12) {
                        Image(systemName: "phone.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ĐANG ĐÀM THOẠI")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Bấm (-) trên cùm xe để kết thúc")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button(action: { callManager.rejectCall() }) {
                            Image(systemName: "phone.down.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.10, green: 0.15, blue: 0.22))
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
                
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
        HStack(spacing: 8) {
            // Ô Điểm A (Xuất phát)
            Button(action: {
                searchTarget = .pointA
                searchQuery = ""
                showSearchSheet = true
            }) {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
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
                .padding(.vertical, 7)
                .background(Color(white: 0.16))
                .cornerRadius(8)
            }
            .frame(maxWidth: .infinity)
            
            // Nút Đảo Chiều lộ trình (Swap)
            Button(action: {
                swapPoints()
            }) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.cyan)
            }
            
            // Ô Điểm B (Điểm đến)
            Button(action: {
                searchTarget = .pointB
                searchQuery = ""
                showSearchSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
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
                .padding(.vertical, 7)
                .background(Color(white: 0.16))
                .cornerRadius(8)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.96))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 2)
    }
    
    // Giao diện hộp chọn lộ trình khi cầm dọc (Portrait)
    private var portraitRoutePlannerHeader: some View {
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
            
            // Các nút hành động: Dẫn đường tới đây, Đặt làm điểm A, Lưu yêu thích
            VStack(spacing: 8) {
                // Nút DẪN ĐƯỜNG ĐẾN ĐÂY (Nổi bật, to, xanh lá)
                Button(action: {
                    navigateCurrentToDroppedPin()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("DẪN ĐƯỜNG ĐẾN ĐÂY")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .cornerRadius(12)
                    .shadow(color: Color.green.opacity(0.4), radius: 4, y: 2)
                }
                
                HStack(spacing: 10) {
                    // Nút ĐẶT LÀM ĐIỂM XUẤT PHÁT (Điểm A)
                    Button(action: {
                        setDroppedPinAsPointA()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "location.north.circle.fill")
                                .font(.system(size: 14))
                            Text("Điểm xuất phát A")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.22))
                        .cornerRadius(10)
                    }
                    
                    // Nút LƯU VÀO YÊU THÍCH (⭐)
                    Button(action: {
                        toggleFavoriteDroppedPin()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: isDroppedPinFavorite ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isDroppedPinFavorite ? .yellow : .white)
                            Text(isDroppedPinFavorite ? "Đã lưu" : "Lưu yêu thích")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isDroppedPinFavorite ? .yellow : .white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
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
        navEngine.calculateRoute(from: startCoord, to: dest.coordinate, destinationTitle: dest.title, autoStart: false)
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
        if pointA != nil, let curLoc = navEngine.currentLocation, let dest = pointB {
            let destTitle = dest.title
            pointA = nil
            navEngine.calculateRoute(from: curLoc.coordinate, to: dest.coordinate, destinationTitle: destTitle, autoStart: true)
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

// MARK: - View Bản đồ OpenStreetMap tương tác (Vẽ lộ trình Google Maps, Ghim Điểm A/B & Điểm nhấn giữ)
public struct OSMMapView: UIViewRepresentable {
    @ObservedObject var navEngine: NavigationEngine
    @Binding var trackingMode: MapUserTrackingMode
    var orientationMode: MapOrientationMode
    var route: OSMRoute?
    var coordA: CLLocationCoordinate2D?
    var coordB: CLLocationCoordinate2D?
    var droppedPinCoord: CLLocationCoordinate2D?
    var onLocationLongPressed: ((CLLocationCoordinate2D) -> Void)?
    
    public init(
        navEngine: NavigationEngine,
        trackingMode: Binding<MapUserTrackingMode>,
        orientationMode: MapOrientationMode = .headingTracking,
        route: OSMRoute?,
        coordA: CLLocationCoordinate2D? = nil,
        coordB: CLLocationCoordinate2D? = nil,
        droppedPinCoord: CLLocationCoordinate2D? = nil,
        onLocationLongPressed: ((CLLocationCoordinate2D) -> Void)? = nil
    ) {
        self.navEngine = navEngine
        self._trackingMode = trackingMode
        self.orientationMode = orientationMode
        self.route = route
        self.coordA = coordA
        self.coordB = coordB
        self.droppedPinCoord = droppedPinCoord
        self.onLocationLongPressed = onLocationLongPressed
    }
    
    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false // Tắt la bàn mặc định ở góc trên (bị hộp tìm kiếm che)
        mapView.showsScale = true
        
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
        
        context.coordinator.updateRoute(on: uiView, newRoute: route, coordA: coordA, coordB: coordB)
        context.coordinator.updateDroppedPin(on: uiView, coord: droppedPinCoord)
        
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
        var currentPolyline: MKPolyline?
        var routeAnnotations: [MKAnnotation] = []
        var droppedPinAnnotation: RoutePointAnnotation?
        var compassButton: MKCompassButton?
        var compassTopConstraint: NSLayoutConstraint?
        var compassTrailingConstraint: NSLayoutConstraint?
        var currentTileOverlay: CustomOSMTileOverlay?
        var currentTileTemplate: String = ""
        private var lastRouteKey: String = ""
        
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
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                // Đường polyline màu xanh neon siêu tương phản, nét dày 11.0pt dễ nhìn khi chạy xe máy ngoài trời
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
            guard let ptAnn = annotation as? RoutePointAnnotation else { return nil }
            let id = ptAnn.isDroppedPin ? "DroppedPinMarker" : "RoutePointMarker"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            
            view.annotation = ptAnn
            view.canShowCallout = true
            if ptAnn.isPointA {
                view.markerTintColor = UIColor.systemGreen
                view.glyphText = "A"
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
            
            // Chỉ tự động căn chỉnh toàn bộ lộ trình vừa khít màn hình khi đang xem trước lộ trình
            // Khi đang lái xe dẫn đường thực tế (isNavigating == true), camera giữ nguyên chế độ bám theo xe (Heading Tracking)
            if !self.parent.navEngine.isNavigating {
                let rect = polyline.boundingMapRect
                let padding = UIEdgeInsets(top: 160, left: 50, bottom: 220, right: 50)
                mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
            }
        }
    }
}
