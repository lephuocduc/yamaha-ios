import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Bộ xử lý định vị và dẫn đường cho NConnect (Tích hợp MapKit & Apple Maps)
public final class NavigationEngine: NSObject, ObservableObject {
    
    @Published public var currentLocation: CLLocation?
    @Published public var currentSpeedKmh: Double = 0.0
    @Published public var currentInstruction: NavigationInstruction = NavigationInstruction()
    @Published public var isNavigating: Bool = false
    @Published public var searchResults: [SavedLocation] = []
    @Published public var nearbyGasStations: [SavedLocation] = []
    @Published public var activeRoute: MKRoute?
    
    // Quản lý địa điểm đã lưu (Về nhà, Đi làm, Yêu thích)
    @Published public var homeLocation: SavedLocation?
    @Published public var workLocation: SavedLocation?
    @Published public var favoriteLocations: [SavedLocation] = []
    
    private let locationManager = CLLocationManager()
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
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .automotiveNavigation
        
        let status = locationManager.authorizationStatus
        if status == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        } else if status == .authorizedWhenInUse {
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
            locationManager.requestAlwaysAuthorization()
        } else {
            locationManager.requestAlwaysAuthorization()
        }
        
        loadSavedLocations()
    }
    
    // MARK: - Quản lý và lưu trữ địa điểm
    private func loadSavedLocations() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "nconnect_home_location"),
           let loc = try? decoder.decode(SavedLocation.self, from: data) {
            self.homeLocation = loc
        }
        if let data = UserDefaults.standard.data(forKey: "nconnect_work_location"),
           let loc = try? decoder.decode(SavedLocation.self, from: data) {
            self.workLocation = loc
        }
        if let data = UserDefaults.standard.data(forKey: "nconnect_favorite_locations"),
           let list = try? decoder.decode([SavedLocation].self, from: data) {
            self.favoriteLocations = list
        }
    }
    
    public func setHomeLocation(_ loc: SavedLocation) {
        var h = loc
        h.type = .home
        self.homeLocation = h
        if let data = try? JSONEncoder().encode(h) {
            UserDefaults.standard.set(data, forKey: "nconnect_home_location")
        }
    }
    
    public func setWorkLocation(_ loc: SavedLocation) {
        var w = loc
        w.type = .work
        self.workLocation = w
        if let data = try? JSONEncoder().encode(w) {
            UserDefaults.standard.set(data, forKey: "nconnect_work_location")
        }
    }
    
    public func addFavoriteLocation(_ loc: SavedLocation) {
        var f = loc
        f.type = .favorite
        if !favoriteLocations.contains(where: { $0.id == f.id || ($0.latitude == f.latitude && $0.longitude == f.longitude) }) {
            favoriteLocations.append(f)
            saveFavorites()
        }
    }
    
    public func removeFavoriteLocation(id: UUID) {
        favoriteLocations.removeAll(where: { $0.id == id })
        saveFavorites()
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoriteLocations) {
            UserDefaults.standard.set(data, forKey: "nconnect_favorite_locations")
        }
    }
    
    public func enableBackgroundUpdatesIfPossible() {
        let status = locationManager.authorizationStatus
        if (status == .authorizedAlways || status == .authorizedWhenInUse) {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
        }
        if status == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }
    
    // MARK: - Tìm kiếm địa điểm bằng Apple MapKit (Hỗ trợ tiếng Việt tuyệt đối, cực nhanh)
    public func searchPlaces(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let loc = currentLocation {
            request.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 30000, longitudinalMeters: 30000)
        }
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            if let error = error {
                print("[Nav] Lỗi tìm kiếm MapKit: \(error.localizedDescription)")
                return
            }
            guard let response = response else { return }
            
            let items: [SavedLocation] = response.mapItems.prefix(10).map { item in
                let sub = item.placemark.title ?? item.placemark.locality ?? "Việt Nam"
                return SavedLocation(
                    title: item.name ?? trimmed,
                    subtitle: sub,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    type: .favorite
                )
            }
            
            DispatchQueue.main.async {
                self.searchResults = items
            }
        }
    }
    
    // MARK: - Tìm trạm xăng lân cận bằng Apple MapKit
    public func fetchNearbyGasStations() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Trạm xăng"
        if let loc = currentLocation {
            request.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 10000, longitudinalMeters: 10000)
        }
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, _ in
            guard let self = self, let response = response else { return }
            
            let stations: [SavedLocation] = response.mapItems.prefix(10).map { item in
                var subText = item.placemark.title ?? "Trạm xăng gần bạn"
                if let loc = self.currentLocation {
                    let d = loc.distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude))
                    if d < 1000 {
                        subText = "Cách \(Int(d)) m"
                    } else {
                        subText = String(format: "Cách %.1f km", d / 1000.0)
                    }
                }
                return SavedLocation(
                    title: item.name ?? "Trạm xăng",
                    subtitle: subText,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    type: .gas
                )
            }
            
            DispatchQueue.main.async {
                self.nearbyGasStations = stations
            }
        }
    }
    
    // MARK: - Lập lộ trình bằng Apple MapKit Directions
    public func calculateRoute(to destination: CLLocationCoordinate2D) {
        guard let start = currentLocation?.coordinate else {
            print("[Nav] Chưa có vị trí GPS hiện tại để lập lộ trình")
            return
        }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self else { return }
            if let error = error {
                print("[Nav] Lỗi tính lộ trình: \(error.localizedDescription)")
                return
            }
            guard let route = response?.routes.first else {
                print("[Nav] Không tìm thấy lộ trình phù hợp")
                return
            }
            
            var steps: [NavigationStep] = []
            for step in route.steps {
                let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                
                let dir = self.mapInstructionTextToDirection(text)
                steps.append(NavigationStep(
                    instruction: text,
                    distanceMeters: Int(step.distance),
                    direction: dir,
                    coordinate: step.polyline.coordinate,
                    roadName: text
                ))
            }
            
            DispatchQueue.main.async {
                self.activeRoute = route
                self.routeSteps = steps
                self.currentStepIndex = 0
                self.enableBackgroundUpdatesIfPossible()
                self.isNavigating = true
                self.updateCurrentInstruction()
                print("[Nav] ✓ Lộ trình mới đã sẵn sàng: \(steps.count) bước dẫn đường")
            }
        }
    }
    
    public func stopNavigation() {
        isNavigating = false
        activeRoute = nil
        routeSteps.removeAll()
        currentStepIndex = 0
        currentInstruction = NavigationInstruction()
    }
    
    private func updateCurrentInstruction() {
        guard isNavigating, currentStepIndex < routeSteps.count else {
            if currentStepIndex >= routeSteps.count && !routeSteps.isEmpty {
                var inst = NavigationInstruction()
                inst.direction = .destination
                inst.distanceMeters = 0
                inst.nextRoadName = "Đã đến nơi"
                inst.isNavigating = true
                currentInstruction = inst
            }
            return
        }
        
        let step = routeSteps[currentStepIndex]
        var inst = NavigationInstruction()
        inst.direction = step.direction
        inst.distanceMeters = step.distanceMeters
        inst.nextRoadName = step.roadName
        inst.isNavigating = true
        
        currentInstruction = inst
    }
    
    private func mapInstructionTextToDirection(_ text: String) -> NavigationDirection {
        let lower = text.lowercased()
        if lower.contains("trái") || lower.contains("left") {
            if lower.contains("chếch") || lower.contains("slight") {
                return .slightLeft
            } else if lower.contains("gắt") || lower.contains("sharp") {
                return .sharpLeft
            }
            return .left
        } else if lower.contains("phải") || lower.contains("right") {
            if lower.contains("chếch") || lower.contains("slight") {
                return .slightRight
            } else if lower.contains("gắt") || lower.contains("sharp") {
                return .sharpRight
            }
            return .right
        } else if lower.contains("quay đầu") || lower.contains("u-turn") {
            return .uTurn
        } else if lower.contains("vòng xuyến") || lower.contains("bùng binh") || lower.contains("roundabout") {
            return .roundabout
        } else if lower.contains("đến") || lower.contains("đích") || lower.contains("arrive") || lower.contains("destination") {
            return .destination
        }
        return .straight
    }
}

// MARK: - CLLocationManagerDelegate
extension NavigationEngine: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
        
        // Cập nhật tốc độ GPS trực tiếp theo thời gian thực (km/h)
        if loc.speed >= 0 {
            currentSpeedKmh = loc.speed * 3.6
        } else {
            currentSpeedKmh = 0.0
        }
        
        // Khi xe di chuyển đến gần ngã rẽ, tự động chuyển sang bước tiếp theo
        if isNavigating && currentStepIndex < routeSteps.count {
            let target = routeSteps[currentStepIndex].coordinate
            let dist = loc.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
            
            // Cập nhật khoảng cách còn lại tới ngã rẽ
            if dist > 0 && dist < 5000 {
                currentInstruction.distanceMeters = Int(dist)
            }
            
            if dist < 25.0 { // Đã đi qua ngã rẽ
                currentStepIndex += 1
                updateCurrentInstruction()
            }
        }
    }
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            manager.pausesLocationUpdatesAutomatically = false
            manager.activityType = .automotiveNavigation
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.activityType = .automotiveNavigation
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        case .denied, .restricted:
            print("[Nav] Quyền vị trí GPS bị từ chối")
        default:
            break
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Nav] Lỗi cập nhật vị trí GPS: \(error.localizedDescription)")
    }
}
