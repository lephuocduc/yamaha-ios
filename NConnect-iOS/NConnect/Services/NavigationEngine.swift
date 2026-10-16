import Foundation
import CoreLocation
import Combine

// MARK: - Bộ xử lý định vị và dẫn đường cho NConnect
public final class NavigationEngine: NSObject, ObservableObject {
    
    @Published public var currentLocation: CLLocation?
    @Published public var currentInstruction: NavigationInstruction = NavigationInstruction()
    @Published public var isNavigating: Bool = false
    @Published public var searchResults: [SavedLocation] = []
    @Published public var nearbyGasStations: [SavedLocation] = []
    
    private let locationManager = CLLocationManager()
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var routeSteps: [NavigationStep] = []
    private var currentStepIndex: Int = 0
    
    public struct NavigationStep {
        public let instruction: String
        public let distanceMeters: Int
        public let direction: NavigationDirection
        public let coordinate: CLLocationCoordinate2D
        public let roadName: String
    }
    
    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0 // Cập nhật mỗi 5 mét khi xe chạy
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // MARK: - Tìm kiếm địa điểm bằng Photon Geocoder (Hỗ trợ tiếng Việt rất tốt)
    public func searchPlaces(query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://photon.komoot.io/api/?q=\(encoded)&limit=5") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let features = json["features"] as? [[String: Any]] {
                    var results: [SavedLocation] = []
                    for f in features {
                        if let geometry = f["geometry"] as? [String: Any],
                           let coords = geometry["coordinates"] as? [Double], coords.count >= 2,
                           let properties = f["properties"] as? [String: Any] {
                            let name = properties["name"] as? String ?? query
                            let street = properties["street"] as? String ?? ""
                            let city = properties["city"] as? String ?? ""
                            let fullSub = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
                            
                            results.append(SavedLocation(
                                title: name,
                                subtitle: fullSub.isEmpty ? "Việt Nam" : fullSub,
                                latitude: coords[1],
                                longitude: coords[0],
                                type: .favorite
                            ))
                        }
                    }
                    DispatchQueue.main.async {
                        self?.searchResults = results
                    }
                }
            } catch {
                print("[Nav] Lỗi parse kết quả tìm kiếm: \(error)")
            }
        }.resume()
    }
    
    // MARK: - Lập lộ trình bằng Valhalla OpenStreetMap
    public func calculateRoute(to destination: CLLocationCoordinate2D) {
        guard let start = currentLocation?.coordinate else {
            print("[Nav] Chưa có vị trí GPS hiện tại")
            return
        }
        
        let requestJson: [String: Any] = [
            "locations": [
                ["lat": start.latitude, "lon": start.longitude],
                ["lat": destination.latitude, "lon": destination.longitude]
            ],
            "costing": "motorcycle", // Chế độ xe máy
            "directions_options": ["units": "kilometers", "language": "vi-VN"]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestJson),
              let jsonStr = String(data: jsonData, encoding: .utf8),
              let encoded = jsonStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://valhalla1.openstreetmap.de/route?json=\(encoded)") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let trip = json["trip"] as? [String: Any],
                   let legs = trip["legs"] as? [[String: Any]],
                   let firstLeg = legs.first,
                   let maneuvers = firstLeg["maneuvers"] as? [[String: Any]] {
                    
                    var steps: [NavigationStep] = []
                    for m in maneuvers {
                        let text = m["instruction"] as? String ?? ""
                        let lengthKm = m["length"] as? Double ?? 0.0
                        let distMeters = Int(lengthKm * 1000)
                        let streetNames = m["street_names"] as? [String]
                        let road = streetNames?.first ?? ""
                        let type = m["type"] as? Int ?? 1
                        
                        let dir = Self.mapValhallaTypeToDirection(type)
                        steps.append(NavigationStep(
                            instruction: text,
                            distanceMeters: distMeters,
                            direction: dir,
                            coordinate: destination,
                            roadName: road
                        ))
                    }
                    
                    DispatchQueue.main.async {
                        self?.routeSteps = steps
                        self?.currentStepIndex = 0
                        self?.isNavigating = true
                        self?.updateCurrentInstruction()
                    }
                }
            } catch {
                print("[Nav] Lỗi định tuyến: \(error)")
            }
        }.resume()
    }
    
    // MARK: - Tìm trạm xăng trong bán kính 5km
    public func fetchNearbyGasStations() {
        guard let loc = currentLocation?.coordinate else { return }
        let query = """
        [out:json];
        node["amenity"="fuel"](around:5000, \(loc.latitude), \(loc.longitude));
        out 10;
        """
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://overpass-api.de/api/interpreter?data=\(encoded)") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let elements = json["elements"] as? [[String: Any]] {
                var stations: [SavedLocation] = []
                for elem in elements {
                    let lat = elem["lat"] as? Double ?? 0.0
                    let lon = elem["lon"] as? Double ?? 0.0
                    let tags = elem["tags"] as? [String: Any]
                    let name = tags?["name"] as? String ?? tags?["brand"] as? String ?? "Trạm xăng Petrolimex"
                    
                    stations.append(SavedLocation(
                        title: name,
                        subtitle: "Cách khoảng 2-5 km",
                        latitude: lat,
                        longitude: lon,
                        type: .gas
                    ))
                }
                DispatchQueue.main.async {
                    self?.nearbyGasStations = stations
                }
            }
        }.resume()
    }
    
    private func updateCurrentInstruction() {
        guard isNavigating, currentStepIndex < routeSteps.count else { return }
        let step = routeSteps[currentStepIndex]
        
        var inst = NavigationInstruction()
        inst.direction = step.direction
        inst.distanceMeters = step.distanceMeters
        inst.nextRoadName = step.roadName.isEmpty ? step.instruction : step.roadName
        inst.isNavigating = true
        
        currentInstruction = inst
    }
    
    private static func mapValhallaTypeToDirection(_ type: Int) -> NavigationDirection {
        switch type {
        case 1, 2, 3: return .straight
        case 4, 5: return .slightRight
        case 6, 7: return .right
        case 8: return .sharpRight
        case 9: return .uTurn
        case 10: return .sharpLeft
        case 11, 12: return .left
        case 13, 14: return .slightLeft
        case 26: return .roundabout
        case 4, 15: return .destination
        default: return .straight
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension NavigationEngine: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
        
        // Khi xe di chuyển đến gần ngã rẽ, chuyển sang bước dẫn đường tiếp theo
        if isNavigating && currentStepIndex < routeSteps.count {
            let target = routeSteps[currentStepIndex].coordinate
            let dist = loc.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
            if dist < 20.0 { // Đã đi qua ngã rẽ trong 20m
                currentStepIndex += 1
                updateCurrentInstruction()
            }
        }
    }
}
