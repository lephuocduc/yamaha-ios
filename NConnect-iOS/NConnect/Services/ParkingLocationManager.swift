import Foundation
import CoreLocation
import MapKit
import UIKit
import Combine

// MARK: - Mô hình lưu trữ vị trí đỗ xe (Find My Bike)
public struct ParkedBikeLocation: Codable, Identifiable, Equatable {
    public var id: UUID
    public var latitude: Double
    public var longitude: Double
    public var timestamp: Date
    public var address: String
    public var bikeName: String
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(id: UUID = UUID(), latitude: Double, longitude: Double, timestamp: Date = Date(), address: String = "", bikeName: String = "Yamaha NMAX") {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.address = address
        self.bikeName = bikeName
    }
    
    public init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, timestamp: Date = Date(), address: String = "", bikeName: String = "Yamaha NMAX") {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
        self.address = address
        self.bikeName = bikeName
    }
    
    // Chuỗi hiển thị thời gian đã đỗ xe
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm · dd/MM/yyyy"
        return formatter.string(from: timestamp)
    }
    
    // Thời gian trôi qua kể từ khi đỗ xe
    public var relativeTimeString: String {
        let elapsed = Date().timeIntervalSince(timestamp)
        if elapsed < 60 {
            return "Vừa mới đỗ xe"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "Đỗ cách đây \(minutes) phút"
        } else if elapsed < 86400 {
            let hours = Int(elapsed / 3600)
            let minutes = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "Đỗ cách đây \(hours) giờ \(minutes) phút"
            } else {
                return "Đỗ cách đây \(hours) giờ"
            }
        } else {
            let days = Int(elapsed / 86400)
            return "Đỗ cách đây \(days) ngày"
        }
    }
    
    // Khoảng cách theo mét từ vị trí hiện tại
    public func distanceMeters(from currentLocation: CLLocationCoordinate2D?) -> Double? {
        guard let current = currentLocation else { return nil }
        let bikeLoc = CLLocation(latitude: latitude, longitude: longitude)
        let currLoc = CLLocation(latitude: current.latitude, longitude: current.longitude)
        return bikeLoc.distance(from: currLoc)
    }
    
    // Chuỗi khoảng cách định dạng đẹp mắt (m hoặc km)
    public func formattedDistance(from currentLocation: CLLocationCoordinate2D?) -> String {
        guard let meters = distanceMeters(from: currentLocation) else { return "--" }
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000.0)
        }
    }
}

// MARK: - Quản lý tự động lưu và tìm kiếm vị trí đỗ xe Yamaha (Find My Bike)
public final class ParkingLocationManager: ObservableObject {
    public static let shared = ParkingLocationManager()
    
    private let storageKey = "mynmax_parking_location"
    private let geocoder = CLGeocoder()
    
    @Published public var lastParkedLocation: ParkedBikeLocation? {
        didSet {
            saveToDefaults()
        }
    }
    @Published public var isGeocoding: Bool = false
    
    public init() {
        loadFromDefaults()
    }
    
    // MARK: - Tải vị trí đỗ xe đã lưu từ bộ nhớ máy
    private func loadFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let parked = try? JSONDecoder().decode(ParkedBikeLocation.self, from: data) {
            self.lastParkedLocation = parked
        }
    }
    
    // MARK: - Ghi đè vào UserDefaults
    private func saveToDefaults() {
        if let parked = lastParkedLocation, let data = try? JSONEncoder().encode(parked) {
            UserDefaults.standard.set(data, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }
    
    // MARK: - Tự động ghi lại vị trí đỗ xe khi tắt khoá xe / ngắt kết nối
    public func recordParkingLocation(coordinate: CLLocationCoordinate2D, bikeName: String = "Yamaha NMAX") {
        // Tránh ghi đè nếu toạ độ không hợp lệ (0,0)
        guard coordinate.latitude != 0.0 && coordinate.longitude != 0.0 else { return }
        
        let initialAddress = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        var newLocation = ParkedBikeLocation(
            coordinate: coordinate,
            timestamp: Date(),
            address: initialAddress,
            bikeName: bikeName
        )
        
        DispatchQueue.main.async {
            self.lastParkedLocation = newLocation
            YamahaCCUManager.shared?.log("🛵 [Find My Bike] Tự động ghi nhận vị trí đỗ xe: \(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))")
        }
        
        // Tiến hành dịch toạ độ ra tên đường / địa chỉ thực tế (Reverse Geocoding)
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        self.isGeocoding = true
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                self?.isGeocoding = false
                guard let self = self else { return }
                
                if let pm = placemarks?.first {
                    var components: [String] = []
                    if let thoroughfare = pm.thoroughfare {
                        if let subThoroughfare = pm.subThoroughfare {
                            components.append("\(subThoroughfare) \(thoroughfare)")
                        } else {
                            components.append(thoroughfare)
                        }
                    } else if let name = pm.name, name != pm.locality {
                        components.append(name)
                    }
                    
                    if let subLocality = pm.subLocality {
                        components.append(subLocality)
                    }
                    if let locality = pm.locality {
                        components.append(locality)
                    }
                    
                    let resolvedAddress = components.isEmpty ? (pm.name ?? initialAddress) : components.joined(separator: ", ")
                    newLocation.address = resolvedAddress
                    self.lastParkedLocation = newLocation
                    YamahaCCUManager.shared?.log("📍 [Find My Bike] Đã xác định địa chỉ bãi đỗ: \(resolvedAddress)")
                }
            }
        }
    }
    
    // MARK: - Xoá vị trí đỗ xe
    public func clearParkingLocation() {
        DispatchQueue.main.async {
            self.lastParkedLocation = nil
            YamahaCCUManager.shared?.log("🗑 [Find My Bike] Đã xoá vị trí đỗ xe")
        }
    }
    
    // MARK: - Mở điều hướng đi bộ trong Apple Maps
    public func openAppleMapsWalking() {
        guard let parked = lastParkedLocation else { return }
        let urlString = "http://maps.apple.com/?daddr=\(parked.latitude),\(parked.longitude)&dirflg=w"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    // MARK: - Mở điều hướng đi bộ trong Google Maps
    public func openGoogleMapsWalking() {
        guard let parked = lastParkedLocation else { return }
        let gmapsScheme = "comgooglemaps://?daddr=\(parked.latitude),\(parked.longitude)&directionsmode=walking"
        let webUrl = "https://www.google.com/maps/dir/?api=1&destination=\(parked.latitude),\(parked.longitude)&travelmode=walking"
        
        if let schemeUrl = URL(string: gmapsScheme), UIApplication.shared.canOpenURL(schemeUrl) {
            UIApplication.shared.open(schemeUrl, options: [:], completionHandler: nil)
        } else if let url = URL(string: webUrl), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
