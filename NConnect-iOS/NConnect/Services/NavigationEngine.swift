import Foundation
import CoreLocation
import MapKit
import Combine
import AVFoundation

// MARK: - Bộ xử lý định vị và dẫn đường NConnect sử dụng OpenStreetMap (OSM) & Valhalla Routing Engine
public final class NavigationEngine: NSObject, ObservableObject {
    public static var shared: NavigationEngine?
    
    @Published public var currentLocation: CLLocation?
    @Published public var currentSpeedKmh: Double = 0.0
    @Published public var currentInstruction: NavigationInstruction = NavigationInstruction()
    @Published public var isNavigating: Bool = false
    @Published public var searchResults: [SavedLocation] = []
    @Published public var nearbyGasStations: [SavedLocation] = []
    @Published public var activeRoute: OSMRoute?
    @Published public var alternativeRoutes: [OSMRoute] = []
    public private(set) var allCalculatedRoutes: [OSMRoute] = []
    @Published public var isSearching: Bool = false
    @Published public var isCalculatingRoute: Bool = false
    @Published public var destinationTitle: String = "Điểm đến"
    @Published public private(set) var currentIntermediateStops: [CLLocationCoordinate2D] = []
    @Published public var arrivalMessage: String? = nil
    @Published public var isVoiceGuidanceEnabled: Bool = false
    
    // Quản lý địa điểm đã lưu (Về nhà, Đi làm, Yêu thích)
    @Published public var homeLocation: SavedLocation?
    @Published public var workLocation: SavedLocation?
    @Published public var favoriteLocations: [SavedLocation] = []
    @Published public var currentRoadName: String = ""
    @Published public var currentHeading: Double = -1.0
    @Published public var isRerouting: Bool = false
    public var onRoadNameChanged: ((String) -> Void)?
    public var onNavigationStopped: (() -> Void)?
    
    // Quản lý giọng nói chỉ đường tiếng Việt
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenStepIndex: Int = -1
    private var hasSpoken300mAlert: Bool = false
    private var hasSpoken100mAlert: Bool = false
    
    // Lưu thông số để tự động tính lại lộ trình khi đi chệch hướng (Auto-Rerouting)
    private var currentDestinationCoordinate: CLLocationCoordinate2D?
    private var lastRerouteTime: Date = .distantPast
    private var offRouteConsecutiveTicks: Int = 0
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let networkSession: URLSession
    private var isGeocoding: Bool = false
    private var lastGeocodedLocation: CLLocation?
    private var lastGeocodeTime: Date = .distantPast
    private var routeSteps: [NavigationStep] = []
    private var currentStepIndex: Int = 0
    private var minDistanceToCurrentStep: CLLocationDistance = Double.greatestFiniteMagnitude
    private var searchWorkItem: DispatchWorkItem?
    
    // Tên con đường hiện tại xe đang lăn bánh thực tế (phục vụ hiển thị footer)
    public var currentStepRoadName: String {
        if currentStepIndex > 0 && currentStepIndex <= routeSteps.count {
            return routeSteps[currentStepIndex - 1].roadName
        } else if !routeSteps.isEmpty {
            return routeSteps[0].roadName
        }
        return ""
    }
    
    public override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.networkSession = URLSession(configuration: config)
        
        super.init()
        Self.shared = self
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .automotiveNavigation
        
        locationManager.showsBackgroundLocationIndicator = true
        
        let status = locationManager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
            if status == .authorizedWhenInUse {
                locationManager.requestAlwaysAuthorization()
            }
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
        } else if let home = SavedPlacesManager.shared.homePlace {
            self.homeLocation = SavedLocation(title: home.name, subtitle: home.address, latitude: home.latitude, longitude: home.longitude, type: .home)
        }
        
        if let data = UserDefaults.standard.data(forKey: "nconnect_work_location"),
           let loc = try? decoder.decode(SavedLocation.self, from: data) {
            self.workLocation = loc
        } else if let work = SavedPlacesManager.shared.workPlace {
            self.workLocation = SavedLocation(title: work.name, subtitle: work.address, latitude: work.latitude, longitude: work.longitude, type: .work)
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
        SavedPlacesManager.shared.setHome(name: loc.title, address: loc.subtitle, coordinate: loc.coordinate)
    }
    
    public func setWorkLocation(_ loc: SavedLocation) {
        var w = loc
        w.type = .work
        self.workLocation = w
        if let data = try? JSONEncoder().encode(w) {
            UserDefaults.standard.set(data, forKey: "nconnect_work_location")
        }
        SavedPlacesManager.shared.setWork(name: loc.title, address: loc.subtitle, coordinate: loc.coordinate)
    }
    
    public func addFavoriteLocation(_ loc: SavedLocation) {
        var f = loc
        f.type = .favorite
        if !favoriteLocations.contains(where: { $0.id == f.id || ($0.latitude == f.latitude && $0.longitude == f.longitude) }) {
            favoriteLocations.append(f)
            saveFavorites()
            SavedPlacesManager.shared.addFavorite(name: loc.title, address: loc.subtitle, coordinate: loc.coordinate)
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
    
    // MARK: - Tìm kiếm địa chỉ & địa điểm siêu tốc bằng MapKit LocalSearch (Hỗ trợ 100% địa danh Việt Nam)
    public func searchPlaces(query: String) {
        searchWorkItem?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = [.address, .pointOfInterest]
            
            // Ưu tiên kết quả quanh tọa độ xe máy trong bán kính ~60km
            if let loc = self.currentLocation {
                let span = MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)
                request.region = MKCoordinateRegion(center: loc.coordinate, span: span)
            }
            
            let search = MKLocalSearch(request: request)
            search.start { [weak self] response, error in
                guard let self = self else { return }
                
                if let response = response, !response.mapItems.isEmpty {
                    let items: [SavedLocation] = response.mapItems.compactMap { item in
                        let title = item.name ?? trimmed
                        let placemark = item.placemark
                        
                        var addressComponents: [String] = []
                        if let num = placemark.subThoroughfare, !num.isEmpty { addressComponents.append(num) }
                        if let street = placemark.thoroughfare, !street.isEmpty { addressComponents.append(street) }
                        if let ward = placemark.subLocality, !ward.isEmpty { addressComponents.append(ward) }
                        if let district = placemark.locality, !district.isEmpty { addressComponents.append(district) }
                        if let city = placemark.administrativeArea, !city.isEmpty { addressComponents.append(city) }
                        
                        let subtitle = addressComponents.isEmpty ? (placemark.title ?? "Việt Nam") : addressComponents.joined(separator: ", ")
                        
                        return SavedLocation(
                            title: title,
                            subtitle: subtitle,
                            latitude: placemark.coordinate.latitude,
                            longitude: placemark.coordinate.longitude,
                            type: .favorite
                        )
                    }
                    
                    DispatchQueue.main.async {
                        self.isSearching = false
                        self.searchResults = items
                    }
                } else {
                    // Dự phòng: Thử tìm kiếm Nominatim / Photon nếu MapKit không có kết quả
                    self.fallbackPhotonSearch(query: trimmed)
                }
            }
        }
        
        self.searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    
    private func fallbackPhotonSearch(query: String) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            DispatchQueue.main.async { self.isSearching = false }
            return
        }
        var urlStr = "https://photon.komoot.io/api/?q=\(encoded)&limit=10&lang=default"
        if let loc = currentLocation {
            urlStr += "&lat=\(loc.coordinate.latitude)&lon=\(loc.coordinate.longitude)"
        }
        guard let url = URL(string: urlStr) else {
            DispatchQueue.main.async { self.isSearching = false }
            return
        }
        
        networkSession.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self else { return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = json["features"] as? [[String: Any]], !features.isEmpty else {
                DispatchQueue.main.async { self.isSearching = false }
                return
            }
            
            var items: [SavedLocation] = []
            for f in features {
                guard let geom = f["geometry"] as? [String: Any],
                      let coords = geom["coordinates"] as? [Double], coords.count >= 2 else { continue }
                let lon = coords[0]
                let lat = coords[1]
                let props = f["properties"] as? [String: Any] ?? [:]
                let name = props["name"] as? String ?? query
                let city = props["city"] as? String ?? props["county"] as? String ?? "Việt Nam"
                let street = props["street"] as? String ?? ""
                let subtitle = street.isEmpty ? city : "\(street), \(city)"
                
                items.append(SavedLocation(title: name, subtitle: subtitle, latitude: lat, longitude: lon, type: .favorite))
            }
            
            DispatchQueue.main.async {
                self.isSearching = false
                self.searchResults = items
            }
        }.resume()
    }
    
    // MARK: - Tra cứu tên địa điểm & địa chỉ từ tọa độ (Native CLGeocoder + Fallback OSM)
    public func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String, String) -> Void) {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            if let p = placemarks?.first {
                let title = p.name ?? p.thoroughfare ?? "Vị trí đã chọn"
                var parts: [String] = []
                if let num = p.subThoroughfare, !num.isEmpty { parts.append(num) }
                if let st = p.thoroughfare, !st.isEmpty { parts.append(st) }
                if let ward = p.subLocality, !ward.isEmpty { parts.append(ward) }
                if let dist = p.locality, !dist.isEmpty { parts.append(dist) }
                if let prov = p.administrativeArea, !prov.isEmpty { parts.append(prov) }
                let subtitle = parts.isEmpty ? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude) : parts.joined(separator: ", ")
                
                DispatchQueue.main.async {
                    completion(title, subtitle)
                }
            } else {
                // Dự phòng OSM Nominatim
                self?.fallbackOsmReverseGeocode(coordinate: coordinate, completion: completion)
            }
        }
    }
    
    private func fallbackOsmReverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String, String) -> Void) {
        let urlString = "https://nominatim.openstreetmap.org/reverse?format=json&lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&zoom=18&addressdetails=1&accept-language=vi"
        guard let url = URL(string: urlString) else {
            completion("Vị trí đã chọn", String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 4
        
        networkSession.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let displayName = json["display_name"] as? String {
                let name = json["name"] as? String
                let address = json["address"] as? [String: Any]
                let road = address?["road"] as? String
                let title = (name != nil && !name!.isEmpty) ? name! : (road ?? displayName.components(separatedBy: ",").first ?? "Vị trí đã chọn")
                DispatchQueue.main.async {
                    completion(title, displayName)
                }
            } else {
                DispatchQueue.main.async {
                    completion("Vị trí đã chọn", String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                }
            }
        }.resume()
    }
    
    // MARK: - Tìm trạm xăng lân cận bằng Apple MapKit LocalSearch (Hỗ trợ 100% cây xăng Việt Nam)
    public func fetchNearbyGasStations() {
        guard let loc = currentLocation else {
            locationManager.requestLocation()
            return
        }
        
        DispatchQueue.main.async {
            self.nearbyGasStations = []
        }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Cây xăng"
        if #available(iOS 13.0, *) {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        }
        request.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 12000, longitudinalMeters: 12000)
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            
            let items = response?.mapItems ?? []
            if items.isEmpty {
                let req2 = MKLocalSearch.Request()
                req2.naturalLanguageQuery = "Trạm xăng"
                req2.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 12000, longitudinalMeters: 12000)
                let search2 = MKLocalSearch(request: req2)
                search2.start { [weak self] resp2, _ in
                    guard let self = self else { return }
                    self.processGasStationMapItems(resp2?.mapItems ?? [], center: loc)
                }
            } else {
                self.processGasStationMapItems(items, center: loc)
            }
        }
    }
    
    private func processGasStationMapItems(_ mapItems: [MKMapItem], center: CLLocation) {
        let sorted = mapItems.sorted { item1, item2 in
            let d1 = center.distance(from: CLLocation(latitude: item1.placemark.coordinate.latitude, longitude: item1.placemark.coordinate.longitude))
            let d2 = center.distance(from: CLLocation(latitude: item2.placemark.coordinate.latitude, longitude: item2.placemark.coordinate.longitude))
            return d1 < d2
        }
        
        var stations: [SavedLocation] = []
        for item in sorted.prefix(25) {
            let name = item.name ?? "Trạm xăng"
            let coord = item.placemark.coordinate
            let dist = center.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            let distStr = dist < 1000 ? "Cách \(Int(dist)) m" : String(format: "Cách %.1f km", dist / 1000.0)
            let addr = item.placemark.title ?? item.placemark.thoroughfare ?? ""
            
            stations.append(SavedLocation(
                title: name,
                subtitle: "\(distStr) • \(addr)",
                latitude: coord.latitude,
                longitude: coord.longitude,
                type: .gas
            ))
        }
        
        DispatchQueue.main.async {
            self.nearbyGasStations = stations
        }
    }
    
    // MARK: - Lập lộ trình chỉ đường bằng Valhalla Routing Engine (Tối ưu xe máy, TRÁNH CAO TỐC & PHÍ, GỢI Ý TUYẾN THAY THẾ, HỖ TRỢ ĐIỂM DỪNG TRUNG GIAN)
    public func calculateRoute(
        from origin: CLLocationCoordinate2D? = nil,
        intermediateStops: [CLLocationCoordinate2D] = [],
        to destination: CLLocationCoordinate2D,
        destinationTitle: String = "Điểm đến",
        autoStart: Bool = true
    ) {
        self.currentDestinationCoordinate = destination
        self.destinationTitle = destinationTitle
        self.currentIntermediateStops = intermediateStops
        let start = origin ?? currentLocation?.coordinate
        guard let startCoord = start else {
            print("[Nav] Chưa có vị trí GPS hiện tại hoặc Điểm A để lập lộ trình")
            return
        }
        
        isCalculatingRoute = true
        self.alternativeRoutes = []
        self.allCalculatedRoutes = []
        
        requestValhallaRoutes(start: startCoord, intermediateStops: intermediateStops, destination: destination) { [weak self] routes in
            guard let self = self else { return }
            if !routes.isEmpty {
                DispatchQueue.main.async {
                    self.applyCalculatedRoutes(routes, autoStart: autoStart)
                }
            } else {
                print("[Nav] Valhalla không khả dụng, kích hoạt dự phòng OSRM...")
                self.fallbackOSRMRoutes(start: startCoord, intermediateStops: intermediateStops, destination: destination) { [weak self] fallbackRoutes in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.isCalculatingRoute = false
                        if !fallbackRoutes.isEmpty {
                            self.applyCalculatedRoutes(fallbackRoutes, autoStart: autoStart)
                        } else {
                            print("[Nav] Cả Valhalla và OSRM đều không tìm thấy lộ trình")
                        }
                    }
                }
            }
        }
    }
    
    public func calculateRoute(to destination: CLLocationCoordinate2D, destinationTitle: String = "Điểm đến") {
        calculateRoute(from: nil, intermediateStops: [], to: destination, destinationTitle: destinationTitle, autoStart: true)
    }
    
    public func startActiveNavigation() {
        guard activeRoute != nil else { return }
        self.isNavigating = true
        self.enableBackgroundUpdatesIfPossible()
        self.updateCurrentInstruction()
        if let loc = currentLocation {
            self.updateRemainingDistanceAndETA(currentLoc: loc)
            if !TripHistoryManager.shared.isRecordingSession {
                TripHistoryManager.shared.startTripSession(at: loc.coordinate, bikeName: "Yamaha NMAX")
            }
        }
    }
    
    // MARK: - Áp dụng danh sách các tuyến đường tính được (Tuyến tối ưu nhất làm activeRoute, các tuyến còn lại làm alternativeRoutes)
    private func applyCalculatedRoutes(_ routes: [OSMRoute], autoStart: Bool = true) {
        guard let primary = routes.first else { return }
        self.allCalculatedRoutes = routes
        self.alternativeRoutes = Array(routes.dropFirst())
        self.applyCalculatedRoute(primary, autoStart: autoStart)
    }
    
    // MARK: - Chuyển đổi tuyến đường đang dẫn (Chọn tuyến gợi ý thay thế tương tự Google Maps)
    public func selectRoute(_ route: OSMRoute) {
        guard activeRoute?.id != route.id else { return }
        
        let targetRoute: OSMRoute
        if let found = allCalculatedRoutes.first(where: { $0.id == route.id }) {
            targetRoute = found
        } else {
            targetRoute = route
        }
        
        self.activeRoute = targetRoute
        self.alternativeRoutes = allCalculatedRoutes.filter { $0.id != targetRoute.id }
        self.routeSteps = targetRoute.steps
        self.currentStepIndex = 0
        self.minDistanceToCurrentStep = Double.greatestFiniteMagnitude
        self.arrivalMessage = nil
        
        if let loc = currentLocation {
            self.updateRemainingDistanceAndETA(currentLoc: loc)
        } else {
            self.currentInstruction.totalDistanceRemainingMeters = Int(targetRoute.distanceMeters)
            self.currentInstruction.totalTimeRemainingSeconds = Int(targetRoute.durationSeconds)
            let eta = Date().addingTimeInterval(targetRoute.durationSeconds)
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            self.currentInstruction.etaString = df.string(from: eta)
            let mins = max(1, Int(targetRoute.durationSeconds) / 60)
            self.currentInstruction.remainingTimeFormatted = "\(mins) phút"
        }
        
        if isNavigating {
            self.updateCurrentInstruction()
        }
        
        print("[Nav] 🔀 Đã chuyển sang lộ trình: \(targetRoute.routeName) (\(targetRoute.formattedDuration), \(targetRoute.formattedDistance))")
    }
    
    private func applyCalculatedRoute(_ route: OSMRoute, autoStart: Bool = true) {
        self.isCalculatingRoute = false
        self.isRerouting = false
        self.offRouteConsecutiveTicks = 0
        self.activeRoute = route
        self.routeSteps = route.steps
        self.currentStepIndex = 0
        self.minDistanceToCurrentStep = Double.greatestFiniteMagnitude
        self.arrivalMessage = nil
        self.enableBackgroundUpdatesIfPossible()
        self.isNavigating = autoStart
        
        // Tính toán thông số ETA và khoảng cách còn lại ban đầu
        if let loc = currentLocation {
            self.updateRemainingDistanceAndETA(currentLoc: loc)
        } else {
            self.currentInstruction.totalDistanceRemainingMeters = Int(route.distanceMeters)
            self.currentInstruction.totalTimeRemainingSeconds = Int(route.durationSeconds)
            let eta = Date().addingTimeInterval(route.durationSeconds)
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            self.currentInstruction.etaString = df.string(from: eta)
            let mins = max(1, Int(route.durationSeconds) / 60)
            self.currentInstruction.remainingTimeFormatted = "\(mins) phút"
        }
        
        if autoStart {
            self.updateCurrentInstruction()
        }
        print("[Nav] ✓ Lộ trình Valhalla sẵn sàng: \(route.steps.count) bước, cự ly \(Int(route.distanceMeters))m, thời gian \(Int(route.durationSeconds))s, ETA: \(self.currentInstruction.etaString) (autoStart: \(autoStart), Tuyến khác: \(self.alternativeRoutes.count))")
    }
    
    // MARK: - Gọi API Valhalla Routing Engine với cấu hình xe máy (costing: motorcycle, TRÁNH CAO TỐC & PHÍ, TÌM TUYẾN PHỤ, ĐIỂM DỪNG TRUNG GIAN)
    private func requestValhallaRoutes(
        start: CLLocationCoordinate2D,
        intermediateStops: [CLLocationCoordinate2D] = [],
        destination: CLLocationCoordinate2D,
        completion: @escaping ([OSMRoute]) -> Void
    ) {
        let serverUrl = UserDefaults.standard.string(forKey: "valhallaServerUrl") ?? "https://valhalla1.openstreetmap.de"
        let trimmedServer = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedServer)/route") else {
            completion([])
            return
        }
        
        var locations: [[String: Any]] = [
            ["lat": start.latitude, "lon": start.longitude, "type": "break"]
        ]
        for stop in intermediateStops {
            locations.append(["lat": stop.latitude, "lon": stop.longitude, "type": "break"])
        }
        locations.append(["lat": destination.latitude, "lon": destination.longitude, "type": "break"])
        
        let payload: [String: Any] = [
            "locations": locations,
            "costing": "motorcycle",
            "costing_options": [
                "motorcycle": [
                    "use_highways": 0.0,  // Tuyệt đối không đi vào đường cao tốc cấm xe máy ở VN
                    "use_primary": 0.9,   // Ưu tiên đi các tuyến đường lớn, đại lộ chính rộng thoáng
                    "use_tolls": 0.0,     // Tránh trạm thu phí
                    "use_trails": 0.0,    // Tránh đường mòn, lối đi bộ
                    "alley_factor": 5.0,  // Phạt nặng việc rẽ vào ngõ ngách, đường hẻm nhỏ hẹp
                    "top_speed": 65       // Tốc độ di chuyển thực tế của xe máy
                ]
            ],
            "alternates": intermediateStops.isEmpty ? 2 : 0, // Gợi ý tối đa 2 tuyến đường thay thế (tương tự Google Maps)
            "directions_options": [
                "units": "kilometers",
                "language": "vi-VN"
            ]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        request.httpBody = httpBody
        
        networkSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let trip = json["trip"] as? [String: Any] else {
                completion([])
                return
            }
            
            var allTrips: [[String: Any]] = [trip]
            if let alternates = json["alternates"] as? [[String: Any]] {
                for alt in alternates {
                    if let altTrip = alt["trip"] as? [String: Any] {
                        allTrips.append(altTrip)
                    }
                }
            }
            
            var routes: [OSMRoute] = []
            for t in allTrips {
                if let r = self.parseValhallaTrip(t, startCoord: start) {
                    routes.append(r)
                }
            }
            
            guard !routes.isEmpty else {
                completion([])
                return
            }
            
            // Sắp xếp các tuyến theo thời gian di chuyển tăng dần (nhanh nhất lên đầu)
            routes.sort { $0.durationSeconds < $1.durationSeconds }
            let fastestDuration = routes.first?.durationSeconds ?? 0.0
            
            for i in 0..<routes.count {
                let diff = max(0.0, routes[i].durationSeconds - fastestDuration)
                routes[i].isFastest = (i == 0)
                routes[i].timeDifferenceSeconds = diff
            }
            
            // Xử lý chống trùng tên tuyến
            var seenNames: [String: Int] = [:]
            for i in 0..<routes.count {
                let base = routes[i].routeName
                if let count = seenNames[base] {
                    seenNames[base] = count + 1
                    routes[i].routeName = "\(base) (\(routes[i].formattedDistance))"
                } else {
                    seenNames[base] = 1
                }
            }
            
            completion(routes)
        }.resume()
    }
    
    private func parseValhallaTrip(_ trip: [String: Any], startCoord: CLLocationCoordinate2D) -> OSMRoute? {
        guard let legs = trip["legs"] as? [[String: Any]], !legs.isEmpty else {
            return nil
        }
        
        let summary = trip["summary"] as? [String: Any] ?? [:]
        let totalLengthKm = summary["length"] as? Double ?? 0.0
        let totalTimeSec = summary["time"] as? Double ?? 0.0
        
        var allCoordinates: [CLLocationCoordinate2D] = []
        var steps: [NavigationStep] = []
        var roadDistances: [String: Int] = [:]
        
        for leg in legs {
            let legOffset = allCoordinates.count
            let shape = leg["shape"] as? String ?? ""
            let legCoords = NavigationEngine.decodePolyline6(shape)
            
            if !allCoordinates.isEmpty && !legCoords.isEmpty {
                let last = allCoordinates.last!
                let first = legCoords.first!
                if abs(last.latitude - first.latitude) < 0.00001 && abs(last.longitude - first.longitude) < 0.00001 {
                    allCoordinates.append(contentsOf: legCoords.dropFirst())
                } else {
                    allCoordinates.append(contentsOf: legCoords)
                }
            } else {
                allCoordinates.append(contentsOf: legCoords)
            }
            
            if let maneuvers = leg["maneuvers"] as? [[String: Any]] {
                for m in maneuvers {
                    let type = m["type"] as? Int ?? 1
                    let rawInstruction = (m["instruction"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let lengthKm = m["length"] as? Double ?? 0.0
                    let distMeters = Int(lengthKm * 1000.0)
                    let beginIdx = (m["begin_shape_index"] as? Int ?? 0) + legOffset
                    
                    let streetNames = m["street_names"] as? [String] ?? []
                    var roadName = streetNames.first ?? ""
                    if roadName.isEmpty {
                        if let range = rawInstruction.range(of: "vào ") {
                            let extracted = String(rawInstruction[range.upperBound...])
                            roadName = extracted.components(separatedBy: "/").first?
                                .trimmingCharacters(in: CharacterSet(charactersIn: " .,")) ?? ""
                        }
                    }
                    let direction = self.mapValhallaToDirection(type: type)
                    if roadName.isEmpty {
                        roadName = (direction == .destination) ? "Điểm đến" : "Đoạn đường tiếp theo"
                    }
                    
                    // Thống kê quãng đường từng con đường chính để đặt tên lộ trình
                    let trimmedRoad = roadName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedRoad.isEmpty &&
                        trimmedRoad != "Điểm đến" &&
                        trimmedRoad != "Đoạn đường tiếp theo" &&
                        trimmedRoad != "Điểm xuất phát" &&
                        !trimmedRoad.lowercased().contains("hẻm") &&
                        !trimmedRoad.lowercased().contains("ngõ") {
                        roadDistances[trimmedRoad, default: 0] += distMeters
                    }
                    
                    let stepCoord = (beginIdx < allCoordinates.count) ? allCoordinates[beginIdx] : (allCoordinates.last ?? startCoord)
                    let finalInstruction = rawInstruction.isEmpty ? direction.descriptionVi : rawInstruction
                    
                    steps.append(NavigationStep(
                        instruction: finalInstruction,
                        distanceMeters: distMeters,
                        direction: direction,
                        coordinate: stepCoord,
                        roadName: roadName
                    ))
                }
            }
        }
        
        guard !allCoordinates.isEmpty else { return nil }
        
        // Đặt tên tuyến đường gợi ý dựa trên con đường chính dài nhất đã đi qua
        let topRoad = roadDistances.max(by: { $0.value < $1.value })?.key
        let routeName: String
        if let top = topRoad {
            let lower = top.lowercased()
            if lower.hasPrefix("đường ") || lower.hasPrefix("đ. ") || lower.hasPrefix("phố ") {
                routeName = "Qua \(top)"
            } else {
                routeName = "Qua Đ. \(top)"
            }
        } else {
            routeName = "Tuyến đường chính"
        }
        
        return OSMRoute(
            coordinates: allCoordinates,
            distanceMeters: totalLengthKm * 1000.0,
            durationSeconds: totalTimeSec,
            steps: steps,
            routeName: routeName
        )
    }
    
    // MARK: - Dự phòng OSRM khi Valhalla máy chủ quá tải hoặc không có mạng (Hỗ trợ alternatives & điểm dừng trung gian)
    private func fallbackOSRMRoutes(
        start: CLLocationCoordinate2D,
        intermediateStops: [CLLocationCoordinate2D] = [],
        destination: CLLocationCoordinate2D,
        completion: @escaping ([OSMRoute]) -> Void
    ) {
        let allCoords = [start] + intermediateStops + [destination]
        let coordsStr = allCoords.map { "\($0.longitude),\($0.latitude)" }.joined(separator: ";")
        let altParam = intermediateStops.isEmpty ? "&alternatives=true" : ""
        let urlStr = "https://router.project-osrm.org/route/v1/driving/\(coordsStr)?overview=full&geometries=geojson&steps=true\(altParam)"
        guard let url = URL(string: urlStr) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        
        networkSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? String, code == "Ok",
                  let rawRoutes = json["routes"] as? [[String: Any]], !rawRoutes.isEmpty else {
                completion([])
                return
            }
            
            var routes: [OSMRoute] = []
            for rDict in rawRoutes {
                var routeCoords: [CLLocationCoordinate2D] = []
                if let geometry = rDict["geometry"] as? [String: Any],
                   let coordinates = geometry["coordinates"] as? [[Double]] {
                    for pt in coordinates where pt.count >= 2 {
                        routeCoords.append(CLLocationCoordinate2D(latitude: pt[1], longitude: pt[0]))
                    }
                }
                guard !routeCoords.isEmpty else { continue }
                
                let totalDistance = rDict["distance"] as? Double ?? 0.0
                let totalDuration = rDict["duration"] as? Double ?? 0.0
                
                var steps: [NavigationStep] = []
                var roadDistances: [String: Int] = [:]
                
                if let legs = rDict["legs"] as? [[String: Any]] {
                    for leg in legs {
                        if let legSteps = leg["steps"] as? [[String: Any]] {
                            for st in legSteps {
                                let roadName = (st["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                let dist = Int(st["distance"] as? Double ?? 0.0)
                                let maneuver = st["maneuver"] as? [String: Any] ?? [:]
                                let type = maneuver["type"] as? String ?? ""
                                let modifier = maneuver["modifier"] as? String ?? ""
                                
                                var stepCoord = start
                                if let locArr = maneuver["location"] as? [Double], locArr.count >= 2 {
                                    stepCoord = CLLocationCoordinate2D(latitude: locArr[1], longitude: locArr[0])
                                }
                                
                                let dir = self.mapOSRMToDirection(type: type, modifier: modifier)
                                let text = self.buildOSRMInstructionText(type: type, modifier: modifier, roadName: roadName)
                                
                                if !roadName.isEmpty &&
                                    !roadName.lowercased().contains("hẻm") &&
                                    !roadName.lowercased().contains("ngõ") {
                                    roadDistances[roadName, default: 0] += dist
                                }
                                
                                steps.append(NavigationStep(
                                    instruction: text,
                                    distanceMeters: dist,
                                    direction: dir,
                                    coordinate: stepCoord,
                                    roadName: roadName.isEmpty ? "Đoạn đường tiếp theo" : roadName
                                ))
                            }
                        }
                    }
                }
                
                let topRoad = roadDistances.max(by: { $0.value < $1.value })?.key
                let routeName: String
                if let top = topRoad {
                    let lower = top.lowercased()
                    if lower.hasPrefix("đường ") || lower.hasPrefix("đ. ") || lower.hasPrefix("phố ") {
                        routeName = "Qua \(top)"
                    } else {
                        routeName = "Qua Đ. \(top)"
                    }
                } else {
                    routeName = "Tuyến OSRM"
                }
                
                routes.append(OSMRoute(
                    coordinates: routeCoords,
                    distanceMeters: totalDistance,
                    durationSeconds: totalDuration,
                    steps: steps,
                    routeName: routeName
                ))
            }
            
            guard !routes.isEmpty else {
                completion([])
                return
            }
            
            routes.sort { $0.durationSeconds < $1.durationSeconds }
            let fastestDuration = routes.first?.durationSeconds ?? 0.0
            
            for i in 0..<routes.count {
                let diff = max(0.0, routes[i].durationSeconds - fastestDuration)
                routes[i].isFastest = (i == 0)
                routes[i].timeDifferenceSeconds = diff
            }
            
            completion(routes)
        }.resume()
    }
    
    // MARK: - Giải mã chuỗi Polyline6 của Valhalla (Hệ số chính xác 1e6)
    public static func decodePolyline6(_ encoded: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        let count = bytes.count
        var lat: Int64 = 0
        var lon: Int64 = 0
        
        while index < count {
            var result: Int64 = 0
            var shift: Int64 = 0
            while true {
                guard index < count else { break }
                let b = Int64(bytes[index]) - 63
                index += 1
                if shift < 60 {
                    result |= (b & 0x1f) << shift
                    shift += 5
                }
                if b < 0x20 {
                    break
                }
            }
            let dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1))
            lat += dlat
            
            result = 0
            shift = 0
            while true {
                guard index < count else { break }
                let b = Int64(bytes[index]) - 63
                index += 1
                if shift < 60 {
                    result |= (b & 0x1f) << shift
                    shift += 5
                }
                if b < 0x20 {
                    break
                }
            }
            let dlon = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1))
            lon += dlon
            
            let latitude = Double(lat) / 1e6
            let longitude = Double(lon) / 1e6
            coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        
        return coordinates
    }
    
    // MARK: - Ánh xạ mã chỉ dẫn rẽ Valhalla sang biểu tượng Garmin StreetCross
    private func mapValhallaToDirection(type: Int) -> NavigationDirection {
        switch type {
        case 1, 2, 3: // kStart, kStartRight, kStartLeft
            return .straight
        case 4, 5, 6, 35, 36: // kDestination, kDestinationRight, kDestinationLeft, transit destinations
            return .destination
        case 7, 8, 17, 22, 25: // kBecomes, kContinue, kRampStraight, kStayStraight, kMerge
            return .straight
        case 9, 18, 20, 23, 37: // kSlightRight, kRampRight, kExitRight, kStayRight, kMergeRight
            return .slightRight
        case 10: // kRight
            return .right
        case 11: // kSharpRight
            return .sharpRight
        case 12, 13: // kUturnRight, kUturnLeft
            return .uTurn
        case 14: // kSharpLeft
            return .sharpLeft
        case 15: // kLeft
            return .left
        case 16, 19, 21, 24, 38: // kSlightLeft, kRampLeft, kExitLeft, kStayLeft, kMergeLeft
            return .slightLeft
        case 26, 27: // kRoundaboutEnter, kRoundaboutExit
            return .roundabout
        default:
            return .straight
        }
    }
    
    // MARK: - Xử lý khi xe đã đến đích (Đạt điểm đến & Tự động kết thúc chỉ đường)
    public func handleArrival() {
        guard isNavigating else { return }
        let destName = destinationTitle.isEmpty ? "Điểm đến" : destinationTitle
        print("[Nav] 🎯 ĐÃ ĐẾN NƠI: \(destName)! Dừng chỉ đường.")
        
        var inst = NavigationInstruction()
        inst.direction = .destination
        inst.distanceMeters = 0
        inst.nextRoadName = "Đã đến nơi"
        inst.destinationName = destName
        inst.hasArrived = true
        inst.isNavigating = false
        inst.currentRoadName = currentRoadName
        currentInstruction = inst
        
        arrivalMessage = "Đã đến nơi: \(destName)!"
        speak("Bạn đã đến nơi: \(destName). Đã kết thúc chỉ đường.")
        
        // Dừng điều hướng
        stopNavigation()
        
        // Giữ lại trạng thái thông báo đến đích trong 8 giây
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            if self?.arrivalMessage != nil {
                self?.arrivalMessage = nil
            }
        }
    }
    
    // MARK: - Giọng nói chỉ đường đã được tắt hoàn toàn theo yêu cầu người dùng
    public func speak(_ text: String) {
        // Tắt hoàn toàn giọng nói (không can thiệp AVAudioSession, không gây gián đoạn nhạc tai nghe hoặc đàm thoại)
        return
    }
    
    // MARK: - Cập nhật khoảng cách còn lại và thời gian dự kiến đến (ETA)
    public func updateRemainingDistanceAndETA(currentLoc: CLLocation) {
        guard let route = activeRoute else { return }
        
        var remainingMeters = 0
        if currentStepIndex < routeSteps.count {
            let curTarget = routeSteps[currentStepIndex].coordinate
            let distToStep = currentLoc.distance(from: CLLocation(latitude: curTarget.latitude, longitude: curTarget.longitude))
            remainingMeters += Int(distToStep)
            
            for i in (currentStepIndex + 1)..<routeSteps.count {
                remainingMeters += routeSteps[i].distanceMeters
            }
        }
        
        let totalDistance = max(1.0, route.distanceMeters)
        let progress = max(0.0, min(1.0, Double(remainingMeters) / totalDistance))
        let remainingSeconds = Int(route.durationSeconds * progress)
        
        currentInstruction.totalDistanceRemainingMeters = remainingMeters
        currentInstruction.totalTimeRemainingSeconds = remainingSeconds
        
        // Định dạng giờ đến (ETA HH:mm)
        let etaDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        currentInstruction.etaString = df.string(from: etaDate)
        
        // Định dạng thời gian di chuyển còn lại
        if remainingSeconds < 3600 {
            let mins = max(1, remainingSeconds / 60)
            currentInstruction.remainingTimeFormatted = "\(mins) phút"
        } else {
            let hours = remainingSeconds / 3600
            let mins = (remainingSeconds % 3600) / 60
            currentInstruction.remainingTimeFormatted = "\(hours)h \(mins)p"
        }
    }
    
    public func stopNavigation() {
        isNavigating = false
        isRerouting = false
        currentDestinationCoordinate = nil
        currentIntermediateStops.removeAll()
        offRouteConsecutiveTicks = 0
        activeRoute = nil
        alternativeRoutes.removeAll()
        allCalculatedRoutes.removeAll()
        routeSteps.removeAll()
        currentStepIndex = 0
        minDistanceToCurrentStep = Double.greatestFiniteMagnitude
        lastSpokenStepIndex = -1
        hasSpoken300mAlert = false
        hasSpoken100mAlert = false
        
        var inst = NavigationInstruction()
        inst.currentRoadName = currentRoadName
        inst.isNavigating = false
        currentInstruction = inst
        
        onNavigationStopped?()
        
        if let ccu = YamahaCCUManager.shared, !ccu.isMFiConnected && ccu.state != .connected {
            if TripHistoryManager.shared.isRecordingSession {
                TripHistoryManager.shared.endTripSession(at: currentLocation?.coordinate)
            }
        }
    }
    
    private func updateCurrentInstruction() {
        guard isNavigating, currentStepIndex < routeSteps.count else {
            if currentStepIndex >= routeSteps.count && !routeSteps.isEmpty {
                handleArrival()
            }
            return
        }
        
        let step = routeSteps[currentStepIndex]
        var inst = currentInstruction
        inst.direction = step.direction
        inst.distanceMeters = step.distanceMeters
        inst.nextRoadName = step.roadName
        inst.detailedInstruction = step.instruction
        inst.destinationName = destinationTitle
        inst.isNavigating = true
        inst.currentRoadName = currentRoadName
        
        currentInstruction = inst
        
        // Giọng nói khi chuyển sang bước rẽ mới
        if currentStepIndex != lastSpokenStepIndex {
            lastSpokenStepIndex = currentStepIndex
            hasSpoken300mAlert = false
            hasSpoken100mAlert = false
            
            let dist = step.distanceMeters
            let distStr = dist < 1000 ? "\(dist) mét" : String(format: "%.1f ki-lô-mét", Double(dist) / 1000.0)
            if step.direction == .straight {
                speak("Đi tiếp \(distStr) trên \(step.roadName)")
            } else {
                speak("\(step.direction.descriptionVi) vào \(step.roadName)")
            }
        }
    }
    
    // Ánh xạ phân loại rẽ của OSRM sang mã hướng biểu tượng Garmin StreetCross
    private func mapOSRMToDirection(type: String, modifier: String) -> NavigationDirection {
        let mod = modifier.lowercased()
        let t = type.lowercased()
        
        if t == "arrive" {
            return .destination
        } else if t.contains("roundabout") || t.contains("rotary") {
            return .roundabout
        }
        
        if mod.contains("uturn") {
            return .uTurn
        } else if mod.contains("sharp right") {
            return .sharpRight
        } else if mod.contains("sharp left") {
            return .sharpLeft
        } else if mod.contains("slight right") {
            return .slightRight
        } else if mod.contains("slight left") {
            return .slightLeft
        } else if mod.contains("right") {
            return .right
        } else if mod.contains("left") {
            return .left
        }
        return .straight
    }
    
    private func buildOSRMInstructionText(type: String, modifier: String, roadName: String) -> String {
        let name = roadName.isEmpty ? "" : " vào \(roadName)"
        let t = type.lowercased()
        let m = modifier.lowercased()
        
        if t == "arrive" {
            return "Đến điểm đích"
        } else if t.contains("roundabout") || t.contains("rotary") {
            return "Vào vòng xuyến\(name)"
        } else if m.contains("uturn") {
            return "Quay đầu xe"
        } else if m.contains("sharp right") {
            return "Rẽ gắt sang phải\(name)"
        } else if m.contains("sharp left") {
            return "Rẽ gắt sang trái\(name)"
        } else if m.contains("slight right") {
            return "Chếch sang phải\(name)"
        } else if m.contains("slight left") {
            return "Chếch sang trái\(name)"
        } else if m.contains("right") {
            return "Rẽ phải\(name)"
        } else if m.contains("left") {
            return "Rẽ trái\(name)"
        } else if t == "depart" {
            return "Bắt đầu đi\(name)"
        }
        return roadName.isEmpty ? "Đi thẳng" : "Đi thẳng trên \(roadName)"
    }
    
    // MARK: - Xác định tên con đường xe đang chạy thực tế bằng Apple CoreLocation Geocoder
    private func checkCurrentRoadName(at loc: CLLocation) {
        // 1. Khi đang dẫn đường, nếu currentRoadName còn rỗng thì khởi tạo từ bước đường hiện tại
        if isNavigating {
            let fallbackRoad = currentStepRoadName
            if self.currentRoadName.isEmpty && !fallbackRoad.isEmpty {
                self.currentRoadName = fallbackRoad
                self.currentInstruction.currentRoadName = fallbackRoad
                self.onRoadNameChanged?(fallbackRoad)
            }
        }
        
        // 2. Throttling cho Apple CLGeocoder: tối thiểu cách điểm cũ 20m và cách lần gọi trước 3.5 giây
        let now = Date()
        let dist = lastGeocodedLocation != nil ? loc.distance(from: lastGeocodedLocation!) : 999.0
        guard (dist > 20.0 || lastGeocodedLocation == nil) && now.timeIntervalSince(lastGeocodeTime) > 3.5 && !isGeocoding else { return }
        
        isGeocoding = true
        lastGeocodedLocation = loc
        lastGeocodeTime = now
        
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self = self else { return }
            self.isGeocoding = false
            
            guard let placemark = placemarks?.first, error == nil else { return }
            
            var street = placemark.thoroughfare ?? placemark.name ?? placemark.subLocality ?? ""
            street = street.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let thoroughfare = placemark.thoroughfare, !thoroughfare.isEmpty {
                street = thoroughfare
            }
            
            if !street.isEmpty && street != self.currentRoadName {
                DispatchQueue.main.async {
                    self.currentRoadName = street
                    self.currentInstruction.currentRoadName = street
                    self.onRoadNameChanged?(street)
                }
            }
        }
    }
}


// MARK: - CLLocationManagerDelegate
extension NavigationEngine: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
        
        // Cập nhật vị trí vào bộ theo dõi lộ trình TripHistoryManager
        TripHistoryManager.shared.updateLocation(loc)
        
        // Cập nhật tên con đường xe đang chạy thực tế (ngay cả khi chạy tự do)
        checkCurrentRoadName(at: loc)
        
        // Cập nhật tốc độ GPS trực tiếp theo thời gian thực (km/h)
        if loc.speed >= 0 {
            currentSpeedKmh = loc.speed * 3.6
        } else {
            currentSpeedKmh = 0.0
        }
        
        // 1. KIỂM TRA ĐÃ ĐẾN NƠI (Đến điểm đích): Dừng chỉ đường & Phát thông báo
        if isNavigating, let dest = currentDestinationCoordinate {
            let distToDest = loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
            if distToDest < 32.0 || (currentStepIndex >= routeSteps.count && !routeSteps.isEmpty) {
                handleArrival()
                return
            }
        }
        
        // 2. Khi xe di chuyển đến gần ngã rẽ, tự động chuyển sang bước tiếp theo & cập nhật ETA
        if isNavigating && currentStepIndex < routeSteps.count {
            let step = routeSteps[currentStepIndex]
            let target = step.coordinate
            let dist = loc.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
            
            // Cập nhật khoảng cách còn lại tới ngã rẽ
            if dist > 0 && dist < 100_000 {
                currentInstruction.distanceMeters = Int(dist)
            }
            
            // Cập nhật khoảng cách tổng và thời gian dự kiến đến (ETA)
            updateRemainingDistanceAndETA(currentLoc: loc)
            
            // Cảnh báo giọng nói trước ngã rẽ ở 300 mét và 100 mét
            if dist <= 350.0 && dist > 150.0 && !hasSpoken300mAlert {
                hasSpoken300mAlert = true
                if step.direction == .straight {
                    speak("Tiếp tục đi thẳng trên \(step.roadName)")
                } else {
                    speak("Sau \(Int(dist)) mét nữa, chuẩn bị \(step.direction.descriptionVi.lowercased()) vào \(step.roadName)")
                }
            } else if dist <= 120.0 && dist > 35.0 && !hasSpoken100mAlert {
                hasSpoken100mAlert = true
                if step.direction == .straight {
                    speak("Đi thẳng trên \(step.roadName)")
                } else {
                    speak("Chuẩn bị \(step.direction.descriptionVi.lowercased()) vào \(step.roadName)")
                }
            }
            
            // Quản lý khoảng cách tiếp cận ngã rẽ (Turn Advancement State Machine)
            if dist < minDistanceToCurrentStep {
                minDistanceToCurrentStep = dist
            }
            
            let speedMps = max(0.0, loc.speed)
            var shouldAdvance = false
            
            if speedMps < 2.2 {
                // Khi xe dừng chờ đèn đỏ hoặc bò rất chậm (< 8 km/h):
                // TUYỆT ĐỐI KHÔNG nhảy cóc sang ngã rẽ tiếp theo trừ khi xe đã tiến sát mốc ngã rẽ (dưới 7m)
                if dist <= 7.0 {
                    shouldAdvance = true
                }
            } else {
                // Khi xe đang di chuyển thực sự (>= 8 km/h):
                // 1. Xe đã lọt vào ngã rẽ (dưới 12m)
                // 2. Xe đã vượt qua đỉnh cua và đang chạy xa dần trên con đường mới (dist tăng ít nhất 4m so với điểm gần nhất)
                if dist <= 12.0 {
                    shouldAdvance = true
                } else if minDistanceToCurrentStep < 25.0 && (dist - minDistanceToCurrentStep) >= 4.0 {
                    shouldAdvance = true
                } else if speedMps >= 11.0 && dist <= min(32.0, speedMps * 1.6) && (dist - minDistanceToCurrentStep) >= 2.0 {
                    shouldAdvance = true
                }
            }
            
            if shouldAdvance {
                currentStepIndex += 1
                minDistanceToCurrentStep = Double.greatestFiniteMagnitude
                updateCurrentInstruction()
            }
            
            // TỰ ĐỘNG PHÁT HIỆN ĐI CHỆCH LỘ TRÌNH & VẼ LẠI ĐƯỜNG ĐI (Auto-Rerouting):
            checkAndRerouteIfOffTrack(currentLoc: loc)
        }
    }
    
    // MARK: - Kiểm tra chệch đường & Tự động vẽ lại lộ trình (Auto-Rerouting)
    private func checkAndRerouteIfOffTrack(currentLoc: CLLocation) {
        guard let dest = currentDestinationCoordinate,
              !isCalculatingRoute,
              Date().timeIntervalSince(lastRerouteTime) > 4.5,
              let route = activeRoute,
              route.coordinates.count >= 2 else { return }
        
        // Tính khoảng cách tối thiểu từ vị trí xe tới toàn bộ polyline lộ trình
        let distToRoute = distanceToActiveRoute(from: currentLoc)
        let offRouteThreshold: CLLocationDistance = 45.0 // Ngưỡng chệch đường 45 mét
        
        if distToRoute > offRouteThreshold {
            offRouteConsecutiveTicks += 1
            // Cần 2 lần đo liên tiếp (> 2 giây) xác nhận xe đã thật sự rẽ sang đường khác
            // để tránh sai số GPS khi đi dưới bóng râm hoặc nhà cao tầng
            if offRouteConsecutiveTicks >= 2 {
                print("[Nav] ⚠️ Phát hiện xe đi chệch lộ trình (\(Int(distToRoute))m > \(Int(offRouteThreshold))m). Đang tự động vẽ lại đường đi mới...")
                lastRerouteTime = Date()
                offRouteConsecutiveTicks = 0
                isRerouting = true
                
                // Tự động yêu cầu Valhalla tính lại tuyến đường tối ưu từ vị trí xe hiện tại
                calculateRoute(from: currentLoc.coordinate, intermediateStops: currentIntermediateStops, to: dest, destinationTitle: destinationTitle, autoStart: true)
            }
        } else {
            offRouteConsecutiveTicks = 0
            if isRerouting {
                isRerouting = false
            }
        }
    }
    
    // MARK: - Tính khoảng cách vuông góc tối thiểu từ vị trí xe tới lộ trình (Point-to-Polyline)
    private func distanceToActiveRoute(from loc: CLLocation) -> CLLocationDistance {
        guard let coords = activeRoute?.coordinates, coords.count >= 2 else { return 0 }
        
        var minDistance: CLLocationDistance = .greatestFiniteMagnitude
        let p = loc.coordinate
        
        for i in 0..<(coords.count - 1) {
            let d = distanceToSegment(point: p, a: coords[i], b: coords[i + 1])
            if d < minDistance {
                minDistance = d
            }
        }
        return minDistance
    }
    
    private func distanceToSegment(point: CLLocationCoordinate2D, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> CLLocationDistance {
        let latMid = ((a.latitude + b.latitude) / 2.0) * .pi / 180.0
        let mPerDegLat: Double = 111132.92
        let mPerDegLon: Double = 111412.84 * cos(latMid)
        
        let px = point.longitude * mPerDegLon
        let py = point.latitude * mPerDegLat
        let ax = a.longitude * mPerDegLon
        let ay = a.latitude * mPerDegLat
        let bx = b.longitude * mPerDegLon
        let by = b.latitude * mPerDegLat
        
        let dx = bx - ax
        let dy = by - ay
        let lenSq = dx * dx + dy * dy
        
        if lenSq == 0 {
            return hypot(px - ax, py - ay)
        }
        
        var t = ((px - ax) * dx + (py - ay) * dy) / lenSq
        t = max(0.0, min(1.0, t))
        
        let projX = ax + t * dx
        let projY = ay + t * dy
        
        return hypot(px - projX, py - projY)
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            manager.showsBackgroundLocationIndicator = true
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.activityType = .automotiveNavigation
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            manager.showsBackgroundLocationIndicator = true
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
