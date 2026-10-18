import Foundation
import CoreLocation
import MapKit

// MARK: - Mô hình lưu trữ địa điểm (Nhà, Công ty, Yêu thích, Trạm xăng)
public struct SavedPlace: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var address: String
    public var latitude: Double
    public var longitude: Double
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(id: UUID = UUID(), name: String, address: String = "", latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
    
    public init(id: UUID = UUID(), name: String, address: String = "", coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

// MARK: - Quản lý các địa điểm thường dùng kết nối với Menu cụm đồng hồ xe Yamaha
public final class SavedPlacesManager: ObservableObject {
    public static let shared = SavedPlacesManager()
    
    private let homeKey = "saved_home_place"
    private let workKey = "saved_work_place"
    private let favoritesKey = "saved_favorite_places"
    
    @Published public var homePlace: SavedPlace? {
        didSet {
            saveToDefaults(homePlace, key: homeKey)
            notifyMenuCapabilitiesChanged()
        }
    }
    
    @Published public var workPlace: SavedPlace? {
        didSet {
            saveToDefaults(workPlace, key: workKey)
            notifyMenuCapabilitiesChanged()
        }
    }
    
    @Published public var favoritePlaces: [SavedPlace] = [] {
        didSet {
            saveArrayToDefaults(favoritePlaces, key: favoritesKey)
        }
    }
    
    @Published public var isSearchingGasStation: Bool = false
    
    public init() {
        loadFromDefaults()
    }
    
    // MARK: - Tải dữ liệu từ UserDefaults (Tự động đồng bộ cả nconnect_* và saved_*)
    private func loadFromDefaults() {
        let decoder = JSONDecoder()
        
        // 1. Tải địa chỉ Nhà (Home)
        if let homeData = UserDefaults.standard.data(forKey: homeKey),
           let place = try? decoder.decode(SavedPlace.self, from: homeData) {
            self.homePlace = place
        } else if let legacyData = UserDefaults.standard.data(forKey: "nconnect_home_location"),
                  let loc = try? decoder.decode(SavedLocation.self, from: legacyData) {
            let place = SavedPlace(name: loc.title, address: loc.subtitle, latitude: loc.latitude, longitude: loc.longitude)
            self.homePlace = place
            saveToDefaults(place, key: homeKey)
        }
        
        // 2. Tải địa chỉ Nơi làm việc (Work)
        if let workData = UserDefaults.standard.data(forKey: workKey),
           let place = try? decoder.decode(SavedPlace.self, from: workData) {
            self.workPlace = place
        } else if let legacyData = UserDefaults.standard.data(forKey: "nconnect_work_location"),
                  let loc = try? decoder.decode(SavedLocation.self, from: legacyData) {
            let place = SavedPlace(name: loc.title, address: loc.subtitle, latitude: loc.latitude, longitude: loc.longitude)
            self.workPlace = place
            saveToDefaults(place, key: workKey)
        }
        
        // 3. Tải danh sách Yêu thích (Favorites)
        if let favData = UserDefaults.standard.data(forKey: favoritesKey),
           let places = try? decoder.decode([SavedPlace].self, from: favData), !places.isEmpty {
            self.favoritePlaces = places
        } else if let legacyData = UserDefaults.standard.data(forKey: "nconnect_favorite_locations"),
                  let list = try? decoder.decode([SavedLocation].self, from: legacyData), !list.isEmpty {
            let places = list.map {
                SavedPlace(name: $0.title, address: $0.subtitle, latitude: $0.latitude, longitude: $0.longitude)
            }
            self.favoritePlaces = places
            saveArrayToDefaults(places, key: favoritesKey)
        }
    }
    
    private func saveToDefaults(_ place: SavedPlace?, key: String) {
        if let place = place, let data = try? JSONEncoder().encode(place) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    private func saveArrayToDefaults(_ places: [SavedPlace], key: String) {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    // MARK: - Đồng bộ trạng thái Menu Home / Work lên màn hình xe qua Service 10 & 11
    public func notifyMenuCapabilitiesChanged() {
        let hasHome = homePlace != nil || UserDefaults.standard.data(forKey: "nconnect_home_location") != nil
        let hasWork = workPlace != nil || UserDefaults.standard.data(forKey: "nconnect_work_location") != nil
        YamahaCCUManager.shared?.updateMenuCapabilities(hasHome: hasHome, hasWork: hasWork)
    }
    
    // MARK: - Thiết lập Nhà (Home)
    public func setHome(name: String, address: String = "", coordinate: CLLocationCoordinate2D) {
        let p = SavedPlace(name: name.isEmpty ? "Nhà" : name, address: address, coordinate: coordinate)
        self.homePlace = p
        let loc = SavedLocation(title: p.name, subtitle: p.address, latitude: p.latitude, longitude: p.longitude, type: .home)
        if let data = try? JSONEncoder().encode(loc) {
            UserDefaults.standard.set(data, forKey: "nconnect_home_location")
        }
    }
    
    public func clearHome() {
        self.homePlace = nil
        UserDefaults.standard.removeObject(forKey: "nconnect_home_location")
    }
    
    // MARK: - Thiết lập Nơi làm việc (Work)
    public func setWork(name: String, address: String = "", coordinate: CLLocationCoordinate2D) {
        let p = SavedPlace(name: name.isEmpty ? "Chỗ làm" : name, address: address, coordinate: coordinate)
        self.workPlace = p
        let loc = SavedLocation(title: p.name, subtitle: p.address, latitude: p.latitude, longitude: p.longitude, type: .work)
        if let data = try? JSONEncoder().encode(loc) {
            UserDefaults.standard.set(data, forKey: "nconnect_work_location")
        }
    }
    
    public func clearWork() {
        self.workPlace = nil
        UserDefaults.standard.removeObject(forKey: "nconnect_work_location")
    }
    
    // MARK: - Thêm / Xoá mục Yêu thích (Favorites)
    public func addFavorite(name: String, address: String = "", coordinate: CLLocationCoordinate2D) {
        let p = SavedPlace(name: name.isEmpty ? "Yêu thích" : name, address: address, coordinate: coordinate)
        self.favoritePlaces.append(p)
    }
    
    public func removeFavorite(id: UUID) {
        self.favoritePlaces.removeAll { $0.id == id }
    }
    
    // MARK: - Tìm danh sách cây xăng gần nhất sử dụng Apple MapKit (MKLocalSearch)
    public func findNearbyGasStationsList(near center: CLLocationCoordinate2D, completion: @escaping ([SavedPlace]) -> Void) {
        self.isSearchingGasStation = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Trạm xăng"
        if #available(iOS 13.0, *) {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        }
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 10000, longitudinalMeters: 10000)
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            let items = response?.mapItems ?? []
            if !items.isEmpty {
                DispatchQueue.main.async {
                    self?.isSearchingGasStation = false
                    let places = self?.processMapItemsToPlaces(items, center: center) ?? []
                    completion(places)
                }
                return
            }
            
            // Thử lại với "Cây xăng"
            let req2 = MKLocalSearch.Request()
            req2.naturalLanguageQuery = "Cây xăng"
            if #available(iOS 13.0, *) {
                req2.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
            }
            req2.region = MKCoordinateRegion(center: center, latitudinalMeters: 10000, longitudinalMeters: 10000)
            let search2 = MKLocalSearch(request: req2)
            search2.start { resp2, _ in
                let items2 = resp2?.mapItems ?? []
                if !items2.isEmpty {
                    DispatchQueue.main.async {
                        self?.isSearchingGasStation = false
                        let places = self?.processMapItemsToPlaces(items2, center: center) ?? []
                        completion(places)
                    }
                    return
                }
                
                // Fallback với "Gas station"
                let req3 = MKLocalSearch.Request()
                req3.naturalLanguageQuery = "Gas station"
                if #available(iOS 13.0, *) {
                    req3.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
                }
                req3.region = MKCoordinateRegion(center: center, latitudinalMeters: 10000, longitudinalMeters: 10000)
                let search3 = MKLocalSearch(request: req3)
                search3.start { resp3, _ in
                    DispatchQueue.main.async {
                        self?.isSearchingGasStation = false
                        let items3 = resp3?.mapItems ?? []
                        let places = self?.processMapItemsToPlaces(items3, center: center) ?? []
                        completion(places)
                    }
                }
            }
        }
    }
    
    private func processMapItemsToPlaces(_ mapItems: [MKMapItem], center: CLLocationCoordinate2D) -> [SavedPlace] {
        let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let sorted = mapItems.sorted { item1, item2 in
            let d1 = centerLoc.distance(from: CLLocation(latitude: item1.placemark.coordinate.latitude, longitude: item1.placemark.coordinate.longitude))
            let d2 = centerLoc.distance(from: CLLocation(latitude: item2.placemark.coordinate.latitude, longitude: item2.placemark.coordinate.longitude))
            return d1 < d2
        }
        
        var places: [SavedPlace] = []
        for item in sorted.prefix(20) {
            let title = item.name ?? "Trạm xăng"
            let addr = item.placemark.title ?? item.placemark.thoroughfare ?? ""
            places.append(SavedPlace(name: title, address: addr, coordinate: item.placemark.coordinate))
        }
        return places
    }
    
    // MARK: - Tìm cây xăng gần nhất
    public func findNearestGasStation(near center: CLLocationCoordinate2D, completion: @escaping (SavedPlace?) -> Void) {
        findNearbyGasStationsList(near: center) { list in
            completion(list.first)
        }
    }
}
