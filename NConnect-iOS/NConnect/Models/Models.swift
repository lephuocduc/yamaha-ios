import Foundation
import CoreLocation

// MARK: - Trạng thái kết nối xe
public enum BikeConnectionState: String, CaseIterable {
    case disconnected = "Chưa kết nối"
    case scanning = "Đang tìm xe..."
    case connecting = "Đang kết nối..."
    case authenticating = "Đang xác thực (Handshake)..."
    case connected = "Đã kết nối với xe"
    case streaming = "Đang truyền bản đồ lên màn hình TFT"
    case error = "Lỗi kết nối"
}

// MARK: - Thông tin xe Yamaha (CCU)
public struct BikeDevice: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let address: String
    public var rssi: Int
    public var isPaired: Bool
    
    public init(id: UUID = UUID(), name: String, address: String = "", rssi: Int = 0, isPaired: Bool = false) {
        self.id = id
        self.name = name
        self.address = address
        self.rssi = rssi
        self.isPaired = isPaired
    }
}

// MARK: - Thông số tức thời từ xe máy
public struct BikeTelemetry {
    public var speedKmh: Double = 0.0
    public var rpm: Int = 0
    public var fuelPercent: Int = 100
    public var engineTemperature: Double = 0.0
    public var batteryVoltage: Double = 12.8
    public var hasError: Bool = false
    public var errorCode: String = ""
    
    public init() {}
}

// MARK: - Thông số màn hình TFT nhận diện từ xe
public struct TFTDisplaySpec {
    public var width: Int = 480
    public var height: Int = 234
    public var softwarePart: String = "006-B4160"
    public var isReadyForStreaming: Bool = false
    
    public init(width: Int = 480, height: Int = 234, softwarePart: String = "006-B4160", isReady: Bool = false) {
        self.width = width
        self.height = height
        self.softwarePart = softwarePart
        self.isReadyForStreaming = isReady
    }
}

// MARK: - Điểm đến nhanh
public struct SavedLocation: Identifiable, Codable {
    public var id = UUID()
    public var title: String
    public var subtitle: String
    public var latitude: Double
    public var longitude: Double
    public var type: LocationType
    
    public enum LocationType: String, Codable {
        case home = "Nhà"
        case work = "Cơ quan"
        case gas = "Trạm xăng"
        case favorite = "Yêu thích"
    }
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(title: String, subtitle: String, latitude: Double, longitude: Double, type: LocationType) {
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.type = type
    }
}

// MARK: - Hướng rẽ dẫn đường (Maneuver)
public enum NavigationDirection: Int {
    case straight = 1
    case slightRight = 2
    case right = 3
    case sharpRight = 4
    case uTurn = 5
    case sharpLeft = 6
    case left = 7
    case slightLeft = 8
    case roundabout = 9
    case destination = 10
    
    public var iconName: String {
        switch self {
        case .straight: return "arrow.up"
        case .slightRight: return "arrow.up.right"
        case .right: return "arrow.right"
        case .sharpRight: return "arrow.turn.up.right"
        case .uTurn: return "arrow.uturn.backward"
        case .sharpLeft: return "arrow.turn.up.left"
        case .left: return "arrow.left"
        case .slightLeft: return "arrow.up.left"
        case .roundabout: return "arrow.triangle.2.circlepath"
        case .destination: return "mappin.and.ellipse"
        }
    }
    
    public var descriptionVi: String {
        switch self {
        case .straight: return "Đi thẳng"
        case .slightRight: return "Chếch sang phải"
        case .right: return "Rẽ phải"
        case .sharpRight: return "Rẽ gắt sang phải"
        case .uTurn: return "Quay đầu xe"
        case .sharpLeft: return "Rẽ gắt sang trái"
        case .left: return "Rẽ trái"
        case .slightLeft: return "Chếch sang trái"
        case .roundabout: return "Vào vòng xuyến"
        case .destination: return "Đến điểm đích"
        }
    }
}

// MARK: - Chỉ dẫn điều hướng Turn-by-Turn
public struct NavigationInstruction {
    public var direction: NavigationDirection = .straight
    public var distanceMeters: Int = 0
    public var currentRoadName: String = ""
    public var nextRoadName: String = ""
    public var totalDistanceRemainingMeters: Int = 0
    public var totalTimeRemainingSeconds: Int = 0
    public var isNavigating: Bool = false
    
    public var formattedDistance: String {
        if distanceMeters < 1000 {
            return "\(distanceMeters) m"
        } else {
            return String(format: "%.1f km", Double(distanceMeters) / 1000.0)
        }
    }
    
    public init() {}
}

// MARK: - Bước điều hướng Turn-by-Turn (Valhalla / OSM Step)
public struct NavigationStep: Identifiable {
    public let id = UUID()
    public let instruction: String
    public let distanceMeters: Int
    public let direction: NavigationDirection
    public let coordinate: CLLocationCoordinate2D
    public let roadName: String
    
    public init(instruction: String, distanceMeters: Int, direction: NavigationDirection, coordinate: CLLocationCoordinate2D, roadName: String) {
        self.instruction = instruction
        self.distanceMeters = distanceMeters
        self.direction = direction
        self.coordinate = coordinate
        self.roadName = roadName
    }
}

// MARK: - Tuyến đường lộ trình OpenStreetMap (OSM Route)
public struct OSMRoute {
    public let coordinates: [CLLocationCoordinate2D]
    public let distanceMeters: Double
    public let durationSeconds: Double
    public let steps: [NavigationStep]
    
    public init(coordinates: [CLLocationCoordinate2D], distanceMeters: Double, durationSeconds: Double, steps: [NavigationStep]) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.steps = steps
    }
}

