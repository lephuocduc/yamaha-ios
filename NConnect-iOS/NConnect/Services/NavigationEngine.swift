import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Bộ xử lý định vị và dẫn đường NConnect sử dụng OpenStreetMap (OSM) & Valhalla Routing Engine
public final class NavigationEngine: NSObject, ObservableObject {
    
    @Published public var currentLocation: CLLocation?
    @Published public var currentSpeedKmh: Double = 0.0
    @Published public var currentInstruction: NavigationInstruction = NavigationInstruction()
    @Published public var isNavigating: Bool = false
    @Published public var searchResults: [SavedLocation] = []
    @Published public var nearbyGasStations: [SavedLocation] = []
    @Published public var activeRoute: OSMRoute?
    @Published public var isSearching: Bool = false
    @Published public var isCalculatingRoute: Bool = false
    
    // Quản lý địa điểm đã lưu (Về nhà, Đi làm, Yêu thích)
    @Published public var homeLocation: SavedLocation?
    @Published public var workLocation: SavedLocation?
    @Published public var favoriteLocations: [SavedLocation] = []
    @Published public var currentRoadName: String = "MyNMAX"
    @Published public var currentHeading: Double = -1.0
    public var onRoadNameChanged: ((String) -> Void)?
    
    private let locationManager = CLLocationManager()
    private let networkSession: URLSession
    private var isGeocoding: Bool = false
    private var lastGeocodedLocation: CLLocation?
    private var lastGeocodeTime: Date = .distantPast
    private var routeSteps: [NavigationStep] = []
    private var currentStepIndex: Int = 0
    
    public override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.networkSession = URLSession(configuration: config)
        
        super.init()
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
    
    // MARK: - Tìm kiếm địa điểm bằng OpenStreetMap (Nominatim + Photon OSM Fallback)
    public func searchPlaces(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        
        // 1. Thử tìm kiếm bằng OpenStreetMap Nominatim
        var urlString = "https://nominatim.openstreetmap.org/search?q=\(encoded)&format=json&addressdetails=1&limit=12&accept-language=vi"
        if let loc = currentLocation {
            // Giới hạn vùng tìm kiếm ưu tiên quanh tọa độ xe máy (bán kính ~50km)
            let delta = 0.5
            let minLon = loc.coordinate.longitude - delta
            let maxLon = loc.coordinate.longitude + delta
            let minLat = loc.coordinate.latitude - delta
            let maxLat = loc.coordinate.latitude + delta
            urlString += "&viewbox=\(minLon),\(maxLat),\(maxLon),\(minLat)&bounded=0"
        }
        
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue("NConnect-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        
        networkSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let data = data,
               let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               !jsonArray.isEmpty {
                var items: [SavedLocation] = []
                for item in jsonArray {
                    guard let latStr = item["lat"] as? String, let lat = Double(latStr),
                          let lonStr = item["lon"] as? String, let lon = Double(lonStr) else { continue }
                    
                    let displayName = item["display_name"] as? String ?? trimmed
                    let name = item["name"] as? String
                    let title = (name != nil && !name!.isEmpty) ? name! : (displayName.components(separatedBy: ",").first ?? trimmed)
                    
                    items.append(SavedLocation(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        subtitle: displayName,
                        latitude: lat,
                        longitude: lon,
                        type: .favorite
                    ))
                }
                
                DispatchQueue.main.async {
                    self.isSearching = false
                    self.searchResults = items
                }
                return
            }
            
            // 2. Dự phòng bằng Photon OSM nếu Nominatim không trả lời
            self.fallbackPhotonSearch(query: trimmed)
        }.resume()
    }
    
    private func fallbackPhotonSearch(query: String) {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        var urlStr = "https://photon.komoot.io/api/?q=\(encoded)&limit=10&lang=default"
        if let loc = currentLocation {
            urlStr += "&lat=\(loc.coordinate.latitude)&lon=\(loc.coordinate.longitude)"
        }
        guard let url = URL(string: urlStr) else { return }
        
        networkSession.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = json["features"] as? [[String: Any]] else {
                DispatchQueue.main.async { self?.isSearching = false }
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
    
    // MARK: - Tra cứu tên địa điểm & địa chỉ từ tọa độ (Reverse Geocoding OpenStreetMap)
    public func reverseGeocode(coordinate: CLLocationCoordinate2D, completion: @escaping (String, String) -> Void) {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        let urlString = "https://nominatim.openstreetmap.org/reverse?format=json&lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&zoom=18&addressdetails=1&accept-language=vi"
        guard let url = URL(string: urlString) else {
            geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
                DispatchQueue.main.async {
                    if let p = placemarks?.first {
                        let title = p.name ?? p.thoroughfare ?? "Vị trí đã chọn"
                        let subtitle = [p.subThoroughfare, p.thoroughfare, p.subLocality, p.locality, p.administrativeArea]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                        completion(title, subtitle.isEmpty ? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude) : subtitle)
                    } else {
                        completion("Vị trí đã chọn", String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    }
                }
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("NConnect-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6
        
        networkSession.dataTask(with: request) { data, response, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let displayName = json["display_name"] as? String {
                
                let name = json["name"] as? String
                let address = json["address"] as? [String: Any]
                let road = address?["road"] as? String
                let suburb = address?["suburb"] as? String ?? address?["quarter"] as? String
                let city = address?["city"] as? String ?? address?["county"] as? String
                
                let title: String = {
                    if let n = name, !n.isEmpty { return n }
                    if let r = road, !r.isEmpty { return r }
                    return displayName.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "Vị trí đã chọn"
                }()
                
                let subtitle: String = {
                    var parts: [String] = []
                    if let s = suburb, !s.isEmpty { parts.append(s) }
                    if let c = city, !c.isEmpty { parts.append(c) }
                    if !parts.isEmpty { return parts.joined(separator: ", ") }
                    return displayName
                }()
                
                DispatchQueue.main.async {
                    completion(title, subtitle)
                }
            } else {
                geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
                    DispatchQueue.main.async {
                        if let p = placemarks?.first {
                            let title = p.name ?? p.thoroughfare ?? "Vị trí đã chọn"
                            let subtitle = [p.subThoroughfare, p.thoroughfare, p.subLocality, p.locality, p.administrativeArea]
                                .compactMap { $0 }
                                .joined(separator: ", ")
                            completion(title, subtitle.isEmpty ? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude) : subtitle)
                        } else {
                            completion("Vị trí đã chọn", String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        }
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Tìm trạm xăng lân cận bằng OpenStreetMap (OSM Fuel Search)
    public func fetchNearbyGasStations() {
        guard let loc = currentLocation else { return }
        
        let delta = 0.08 // bán kính khoảng 8km
        let minLon = loc.coordinate.longitude - delta
        let maxLon = loc.coordinate.longitude + delta
        let minLat = loc.coordinate.latitude - delta
        let maxLat = loc.coordinate.latitude + delta
        
        guard let url = URL(string: "https://nominatim.openstreetmap.org/search?format=json&q=x%C4%83ng&viewbox=\(minLon),\(maxLat),\(maxLon),\(minLat)&bounded=1&limit=15&accept-language=vi") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("NConnect-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        
        networkSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let data = data, let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var stations: [SavedLocation] = []
                for item in jsonArray {
                    guard let latStr = item["lat"] as? String, let lat = Double(latStr),
                          let lonStr = item["lon"] as? String, let lon = Double(lonStr) else { continue }
                    
                    let name = item["name"] as? String ?? "Cây xăng Petrolimex"
                    let displayName = item["display_name"] as? String ?? "Trạm xăng OpenStreetMap"
                    let dist = loc.distance(from: CLLocation(latitude: lat, longitude: lon))
                    let distStr = dist < 1000 ? "Cách \(Int(dist)) m" : String(format: "Cách %.1f km", dist / 1000.0)
                    
                    stations.append(SavedLocation(
                        title: name,
                        subtitle: "\(distStr) • \(displayName.components(separatedBy: ",").first ?? "")",
                        latitude: lat,
                        longitude: lon,
                        type: .gas
                    ))
                }
                
                DispatchQueue.main.async {
                    self.nearbyGasStations = stations
                }
            }
        }.resume()
    }
    
    // MARK: - Lập lộ trình chỉ đường bằng Valhalla Routing Engine (Tối ưu xe máy)
    public func calculateRoute(from origin: CLLocationCoordinate2D? = nil, to destination: CLLocationCoordinate2D, autoStart: Bool = true) {
        let start = origin ?? currentLocation?.coordinate
        guard let startCoord = start else {
            print("[Nav] Chưa có vị trí GPS hiện tại hoặc Điểm A để lập lộ trình")
            return
        }
        
        isCalculatingRoute = true
        requestValhallaRoute(start: startCoord, destination: destination) { [weak self] route in
            guard let self = self else { return }
            if let route = route {
                DispatchQueue.main.async {
                    self.applyCalculatedRoute(route, autoStart: autoStart)
                }
            } else {
                print("[Nav] Valhalla không khả dụng, kích hoạt dự phòng OSRM...")
                self.fallbackOSRMRoute(start: startCoord, destination: destination) { [weak self] fallbackRoute in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.isCalculatingRoute = false
                        if let fb = fallbackRoute {
                            self.applyCalculatedRoute(fb, autoStart: autoStart)
                        } else {
                            print("[Nav] Cả Valhalla và OSRM đều không tìm thấy lộ trình")
                        }
                    }
                }
            }
        }
    }
    
    public func calculateRoute(to destination: CLLocationCoordinate2D) {
        calculateRoute(from: nil, to: destination, autoStart: true)
    }
    
    public func startActiveNavigation() {
        guard activeRoute != nil else { return }
        self.isNavigating = true
        self.enableBackgroundUpdatesIfPossible()
        self.updateCurrentInstruction()
    }
    
    private func applyCalculatedRoute(_ route: OSMRoute, autoStart: Bool = true) {
        self.isCalculatingRoute = false
        self.activeRoute = route
        self.routeSteps = route.steps
        self.currentStepIndex = 0
        self.enableBackgroundUpdatesIfPossible()
        self.isNavigating = autoStart
        if autoStart {
            self.updateCurrentInstruction()
        }
        print("[Nav] ✓ Lộ trình Valhalla sẵn sàng: \(route.steps.count) bước, cự ly \(Int(route.distanceMeters))m, thời gian \(Int(route.durationSeconds))s (autoStart: \(autoStart))")
    }
    
    // MARK: - Gọi API Valhalla Routing Engine với cấu hình xe máy (costing: motorcycle)
    private func requestValhallaRoute(start: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, completion: @escaping (OSMRoute?) -> Void) {
        let serverUrl = UserDefaults.standard.string(forKey: "valhallaServerUrl") ?? "https://valhalla1.openstreetmap.de"
        let trimmedServer = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedServer)/route") else {
            completion(nil)
            return
        }
        
        let payload: [String: Any] = [
            "locations": [
                ["lat": start.latitude, "lon": start.longitude, "type": "break"],
                ["lat": destination.latitude, "lon": destination.longitude, "type": "break"]
            ],
            "costing": "motorcycle",
            "costing_options": [
                "motorcycle": [
                    "use_highways": 0.5,
                    "use_trails": 0.0
                ]
            ],
            "directions_options": [
                "units": "kilometers",
                "language": "vi-VN"
            ]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        request.httpBody = httpBody
        
        networkSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                completion(nil)
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let trip = json["trip"] as? [String: Any],
                  let legs = trip["legs"] as? [[String: Any]],
                  let firstLeg = legs.first else {
                completion(nil)
                return
            }
            
            let summary = trip["summary"] as? [String: Any] ?? [:]
            let totalLengthKm = summary["length"] as? Double ?? 0.0
            let totalTimeSec = summary["time"] as? Double ?? 0.0
            
            let shape = firstLeg["shape"] as? String ?? ""
            let coordinates = NavigationEngine.decodePolyline6(shape)
            guard !coordinates.isEmpty else {
                completion(nil)
                return
            }
            
            var steps: [NavigationStep] = []
            if let maneuvers = firstLeg["maneuvers"] as? [[String: Any]] {
                for m in maneuvers {
                    let type = m["type"] as? Int ?? 1
                    let rawInstruction = (m["instruction"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let lengthKm = m["length"] as? Double ?? 0.0
                    let distMeters = Int(lengthKm * 1000.0)
                    let beginIdx = m["begin_shape_index"] as? Int ?? 0
                    
                    let streetNames = m["street_names"] as? [String] ?? []
                    var roadName = streetNames.first ?? ""
                    if roadName.isEmpty {
                        if let range = rawInstruction.range(of: "vào ") {
                            let extracted = String(rawInstruction[range.upperBound...])
                            roadName = extracted.components(separatedBy: "/").first?
                                .trimmingCharacters(in: CharacterSet(charactersIn: " .,")) ?? ""
                        }
                    }
                    if roadName.isEmpty {
                        roadName = "Đoạn đường tiếp theo"
                    }
                    
                    let stepCoord = (beginIdx < coordinates.count) ? coordinates[beginIdx] : (coordinates.first ?? start)
                    let direction = self.mapValhallaToDirection(type: type)
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
            
            let route = OSMRoute(
                coordinates: coordinates,
                distanceMeters: totalLengthKm * 1000.0,
                durationSeconds: totalTimeSec,
                steps: steps
            )
            completion(route)
        }.resume()
    }
    
    // MARK: - Dự phòng OSRM khi Valhalla máy chủ quá tải hoặc không có mạng
    private func fallbackOSRMRoute(start: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, completion: @escaping (OSMRoute?) -> Void) {
        let urlStr = "https://router.project-osrm.org/route/v1/driving/\(start.longitude),\(start.latitude);\(destination.longitude),\(destination.latitude)?overview=full&geometries=geojson&steps=true"
        guard let url = URL(string: urlStr) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        
        networkSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = json["code"] as? String, code == "Ok",
                  let routes = json["routes"] as? [[String: Any]],
                  let firstRoute = routes.first else {
                completion(nil)
                return
            }
            
            var routeCoords: [CLLocationCoordinate2D] = []
            if let geometry = firstRoute["geometry"] as? [String: Any],
               let coordinates = geometry["coordinates"] as? [[Double]] {
                for pt in coordinates where pt.count >= 2 {
                    routeCoords.append(CLLocationCoordinate2D(latitude: pt[1], longitude: pt[0]))
                }
            }
            
            let totalDistance = firstRoute["distance"] as? Double ?? 0.0
            let totalDuration = firstRoute["duration"] as? Double ?? 0.0
            
            var steps: [NavigationStep] = []
            if let legs = firstRoute["legs"] as? [[String: Any]], let firstLeg = legs.first,
               let legSteps = firstLeg["steps"] as? [[String: Any]] {
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
                    
                    steps.append(NavigationStep(
                        instruction: text,
                        distanceMeters: dist,
                        direction: dir,
                        coordinate: stepCoord,
                        roadName: roadName.isEmpty ? "Đoạn đường tiếp theo" : roadName
                    ))
                }
            }
            
            let osmRoute = OSMRoute(
                coordinates: routeCoords,
                distanceMeters: totalDistance,
                durationSeconds: totalDuration,
                steps: steps
            )
            completion(osmRoute)
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
                result |= (b & 0x1f) << shift
                shift += 5
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
                result |= (b & 0x1f) << shift
                shift += 5
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
    
    // MARK: - Xác định tên con đường xe đang chạy thực tế bằng OpenStreetMap Reverse Geocoding
    private func checkCurrentRoadName(at loc: CLLocation) {
        if isNavigating && currentStepIndex < routeSteps.count {
            let step = routeSteps[currentStepIndex]
            let road = step.roadName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !road.isEmpty && road != currentRoadName {
                self.currentRoadName = road
                self.currentInstruction.currentRoadName = road
                self.onRoadNameChanged?(road)
            }
            return
        }
        
        let now = Date()
        let dist = lastGeocodedLocation != nil ? loc.distance(from: lastGeocodedLocation!) : 999.0
        guard (dist > 30.0 || lastGeocodedLocation == nil) && now.timeIntervalSince(lastGeocodeTime) > 6.0 && !isGeocoding else { return }
        
        isGeocoding = true
        lastGeocodedLocation = loc
        lastGeocodeTime = now
        
        let urlStr = "https://nominatim.openstreetmap.org/reverse?lat=\(loc.coordinate.latitude)&lon=\(loc.coordinate.longitude)&format=json&addressdetails=1&accept-language=vi"
        guard let url = URL(string: urlStr) else {
            self.isGeocoding = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("NConnect-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        
        networkSession.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self else { return }
            self.isGeocoding = false
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let address = json["address"] as? [String: Any] else { return }
            
            let road = address["road"] as? String
                ?? address["pedestrian"] as? String
                ?? address["suburb"] as? String
                ?? address["neighbourhood"] as? String
                ?? address["city_district"] as? String
                ?? ""
            
            let trimmed = road.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != self.currentRoadName {
                DispatchQueue.main.async {
                    self.currentRoadName = trimmed
                    self.currentInstruction.currentRoadName = trimmed
                    self.onRoadNameChanged?(trimmed)
                }
            }
        }.resume()
    }
}


// MARK: - CLLocationManagerDelegate
extension NavigationEngine: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        currentLocation = loc
        
        // Cập nhật tên con đường xe đang chạy thực tế (ngay cả khi chạy tự do)
        checkCurrentRoadName(at: loc)
        
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
            
            // Ngưỡng chuyển bước thích ứng theo tốc độ (High-Speed Adaptive Turn Threshold):
            // Ở tốc độ cao (60 - 100+ km/h), xe di chuyển 17 - 28 mét/giây.
            // Ngưỡng được mở rộng theo vận tốc để GPS 1Hz không bao giờ bị nhảy cóc qua ngã rẽ.
            let speedMps = max(0.0, loc.speed)
            let dynamicThreshold = max(28.0, speedMps * 2.2) // 40km/h: ~28m, 60km/h: ~37m, 90km/h: ~55m
            
            var shouldAdvance = dist < dynamicThreshold
            
            // Nếu xe đã vượt qua ngã rẽ hiện tại và đang tiến gần hơn tới ngã rẽ tiếp theo (i+1)
            if !shouldAdvance && (currentStepIndex + 1) < routeSteps.count {
                let nextTarget = routeSteps[currentStepIndex + 1].coordinate
                let nextDist = loc.distance(from: CLLocation(latitude: nextTarget.latitude, longitude: nextTarget.longitude))
                if nextDist < dist && dist < 90.0 {
                    shouldAdvance = true
                }
            }
            
            if shouldAdvance {
                currentStepIndex += 1
                updateCurrentInstruction()
            }
        }
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
