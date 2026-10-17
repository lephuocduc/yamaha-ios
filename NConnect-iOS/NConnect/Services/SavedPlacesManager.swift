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
    
    // MARK: - Tải dữ liệu từ UserDefaults
    private func loadFromDefaults() {
        if let homeData = UserDefaults.standard.data(forKey: homeKey),
           let place = try? JSONDecoder().decode(SavedPlace.self, from: homeData) {
            self.homePlace = place
        }
        
        if let workData = UserDefaults.standard.data(forKey: workKey),
           let place = try? JSONDecoder().decode(SavedPlace.self, from: workData) {
            self.workPlace = place
        }
        
        if let favData = UserDefaults.standard.data(forKey: favoritesKey),
           let places = try? JSONDecoder().decode([SavedPlace].self, from: favData) {
            self.favoritePlaces = places
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
        let hasHome = homePlace != nil
        let hasWork = workPlace != nil
        YamahaCCUManager.shared?.updateMenuCapabilities(hasHome: hasHome, hasWork: hasWork)
    }
    
    // MARK: - Thiết lập Nhà (Home)
    public func setHome(name: String, address: String = "", coordinate: CLLocationCoordinate2D) {
        let p = SavedPlace(name: name.isEmpty ? "Nhà" : name, address: address, coordinate: coordinate)
        self.homePlace = p
    }
    
    public func clearHome() {
        self.homePlace = nil
    }
    
    // MARK: - Thiết lập Nơi làm việc (Work)
    public func setWork(name: String, address: String = "", coordinate: CLLocationCoordinate2D) {
        let p = SavedPlace(name: name.isEmpty ? "Chỗ làm" : name, address: address, coordinate: coordinate)
        self.workPlace = p
    }
    
    public func clearWork() {
        self.workPlace = nil
    }
    
    // MARK: - Thêm / Xoá mục Yêu thích (Favorites)
    public func addFavorite(name: String, address: String = "", coordinate: CLLocationCoordinate2D) {
        let p = SavedPlace(name: name.isEmpty ? "Yêu thích" : name, address: address, coordinate: coordinate)
        self.favoritePlaces.append(p)
    }
    
    public func removeFavorite(id: UUID) {
        self.favoritePlaces.removeAll { $0.id == id }
    }
    
    // MARK: - Tìm cây xăng gần nhất sử dụng Apple MapKit (MKLocalSearch)
    public func findNearestGasStation(near center: CLLocationCoordinate2D, completion: @escaping (SavedPlace?) -> Void) {
        self.isSearchingGasStation = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Cây xăng"
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 6000, longitudinalMeters: 6000)
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                self?.isSearchingGasStation = false
                guard let mapItems = response?.mapItems, !mapItems.isEmpty else {
                    // Thử tìm lại bằng từ khoá tiếng Anh "Petrol station" nếu tiếng Việt không ra
                    self?.searchFallbackGasStation(near: center, completion: completion)
                    return
                }
                
                let sortedItems = mapItems.sorted { item1, item2 in
                    let loc1 = CLLocation(latitude: item1.placemark.coordinate.latitude, longitude: item1.placemark.coordinate.longitude)
                    let loc2 = CLLocation(latitude: item2.placemark.coordinate.latitude, longitude: item2.placemark.coordinate.longitude)
                    let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
                    return loc1.distance(from: centerLoc) < loc2.distance(from: centerLoc)
                }
                
                if let closest = sortedItems.first {
                    let title = closest.name ?? "Trạm xăng"
                    let addr = closest.placemark.title ?? ""
                    let station = SavedPlace(name: title, address: addr, coordinate: closest.placemark.coordinate)
                    completion(station)
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    private func searchFallbackGasStation(near center: CLLocationCoordinate2D, completion: @escaping (SavedPlace?) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Gas station"
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: 8000, longitudinalMeters: 8000)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                guard let mapItems = response?.mapItems, let closest = mapItems.first else {
                    completion(nil)
                    return
                }
                let title = closest.name ?? "Trạm xăng"
                let station = SavedPlace(name: title, address: closest.placemark.title ?? "", coordinate: closest.placemark.coordinate)
                completion(station)
            }
        }
    }
}
