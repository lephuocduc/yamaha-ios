import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Mô hình dữ liệu lưu trữ 1 chuyến đi (Lộ trình đã chạy)
public struct TripRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var startTime: Date
    public var endTime: Date
    public var startLatitude: Double
    public var startLongitude: Double
    public var startAddress: String
    public var endLatitude: Double
    public var endLongitude: Double
    public var endAddress: String
    public var distanceMeters: Double
    public var durationSeconds: TimeInterval
    public var averageSpeedKmh: Double
    public var maxSpeedKmh: Double
    public var parkingTimestamp: Date
    public var bikeName: String
    public var polylinePoints: [[Double]] // [[lat, lon], ...]
    
    public init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date,
        startLatitude: Double,
        startLongitude: Double,
        startAddress: String,
        endLatitude: Double,
        endLongitude: Double,
        endAddress: String,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        averageSpeedKmh: Double,
        maxSpeedKmh: Double,
        parkingTimestamp: Date,
        bikeName: String = "Yamaha NMAX",
        polylinePoints: [[Double]] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.startAddress = startAddress
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.endAddress = endAddress
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averageSpeedKmh = averageSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.parkingTimestamp = parkingTimestamp
        self.bikeName = bikeName
        self.polylinePoints = polylinePoints
    }
    
    public var startCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }
    
    public var endCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude)
    }
    
    // Định dạng ngày: "Thứ Bảy, 18/10/2026"
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "EEEE, dd/MM/yyyy"
        return formatter.string(from: startTime).capitalized
    }
    
    // Định dạng khung giờ: "08:15 - 08:45"
    public var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    // Định dạng cự ly: "4.25 km" hoặc "350 m"
    public var formattedDistance: String {
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters)) m"
        } else {
            return String(format: "%.2f km", distanceMeters / 1000.0)
        }
    }
    
    // Định dạng thời gian di chuyển: "35 phút" hoặc "1h 15p" hoặc "45 giây"
    public var formattedDuration: String {
        let seconds = Int(durationSeconds)
        if seconds < 60 {
            return "\(seconds) giây"
        } else if seconds < 3600 {
            let mins = seconds / 60
            let remSecs = seconds % 60
            return remSecs > 0 ? "\(mins)p \(remSecs)s" : "\(mins) phút"
        } else {
            let hours = seconds / 3600
            let mins = (seconds % 3600) / 60
            return mins > 0 ? "\(hours)h \(mins)p" : "\(hours) giờ"
        }
    }
    
    // Định dạng tốc độ trung bình
    public var formattedAverageSpeed: String {
        return String(format: "%.1f km/h", averageSpeedKmh)
    }
    
    // Định dạng tốc độ tối đa
    public var formattedMaxSpeed: String {
        return String(format: "%.1f km/h", maxSpeedKmh)
    }
    
    // Định dạng mốc thời gian bắt đầu đỗ xe
    public var formattedParkingTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm · dd/MM/yyyy"
        return formatter.string(from: parkingTimestamp)
    }
    
    // Thời gian trôi qua kể từ khi đỗ xe tại điểm kết thúc
    public var relativeParkingDuration: String {
        let elapsed = Date().timeIntervalSince(parkingTimestamp)
        if elapsed < 60 {
            return "Vừa đỗ xe"
        } else if elapsed < 3600 {
            return "Đã đỗ \(Int(elapsed / 60)) phút"
        } else if elapsed < 86400 {
            let h = Int(elapsed / 3600)
            let m = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
            return m > 0 ? "Đã đỗ \(h)h \(m)p" : "Đã đỗ \(h) giờ"
        } else {
            return "Đã đỗ \(Int(elapsed / 86400)) ngày"
        }
    }
}

// MARK: - Quản lý lưu trữ & theo dõi lộ trình di chuyển tự động (Trip History Manager)
public final class TripHistoryManager: ObservableObject {
    public static let shared = TripHistoryManager()
    
    private let storageKey = "mynmax_saved_trip_history"
    private let geocoder = CLGeocoder()
    
    @Published public var trips: [TripRecord] = []
    
    // Trạng thái phiên theo dõi trực tiếp
    @Published public var isRecordingSession: Bool = false
    @Published public var currentSessionDistanceMeters: Double = 0.0
    @Published public var currentSessionDurationSeconds: TimeInterval = 0.0
    
    private var sessionStartTime: Date?
    private var sessionStartCoordinate: CLLocationCoordinate2D?
    private var sessionStartAddress: String = ""
    private var lastRecordedLocation: CLLocation?
    private var sessionPoints: [CLLocationCoordinate2D] = []
    private var sessionBikeName: String = "Yamaha NMAX"
    private var sessionMaxSpeedMps: Double = 0.0
    
    public init() {
        loadTrips()
    }
    
    // MARK: - Tải & Lưu danh sách từ UserDefaults
    private func loadTrips() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let list = try? JSONDecoder().decode([TripRecord].self, from: data) {
            self.trips = list.sorted { $0.startTime > $1.startTime }
        }
    }
    
    private func saveTrips() {
        if let data = try? JSONEncoder().encode(trips) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    // MARK: - Bắt đầu phiên theo dõi lộ trình (khi bật khoá xe hoặc bắt đầu dẫn đường)
    public func startTripSession(at coordinate: CLLocationCoordinate2D, bikeName: String = "Yamaha NMAX") {
        guard coordinate.latitude != 0.0 && coordinate.longitude != 0.0 else { return }
        
        // Nếu phiên đang ghi và vị trí không đổi, không reset
        if isRecordingSession { return }
        
        self.sessionStartTime = Date()
        self.sessionStartCoordinate = coordinate
        self.sessionBikeName = bikeName
        self.currentSessionDistanceMeters = 0.0
        self.currentSessionDurationSeconds = 0.0
        self.sessionMaxSpeedMps = 0.0
        self.sessionPoints = [coordinate]
        self.lastRecordedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        self.isRecordingSession = true
        
        self.sessionStartAddress = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        
        // Dịch tên đường / địa chỉ điểm xuất phát
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self = self, let pm = placemarks?.first else { return }
            var components: [String] = []
            if let subThoroughfare = pm.subThoroughfare, let thoroughfare = pm.thoroughfare {
                components.append("\(subThoroughfare) \(thoroughfare)")
            } else if let thoroughfare = pm.thoroughfare {
                components.append(thoroughfare)
            } else if let name = pm.name {
                components.append(name)
            }
            if let subLocality = pm.subLocality { components.append(subLocality) }
            if let locality = pm.locality { components.append(locality) }
            
            if !components.isEmpty {
                self.sessionStartAddress = components.joined(separator: ", ")
            }
        }
        
        YamahaCCUManager.shared?.log("🏁 [Lộ trình] Bắt đầu theo dõi lộ trình xe máy tại (\(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)))")
    }
    
    // MARK: - Cập nhật vị trí GPS theo thời gian thực
    public func updateLocation(_ location: CLLocation) {
        guard isRecordingSession, let last = lastRecordedLocation else { return }
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 60.0 else { return }
        
        let delta = location.distance(from: last)
        // Lọc nhiễu GPS đứng yên (cần di chuyển thực tế >= 2.0m)
        if delta >= 2.0 {
            currentSessionDistanceMeters += delta
            lastRecordedLocation = location
            
            // Lưu điểm polyline mỗi 15 mét để vẽ bản đồ
            if let lastPt = sessionPoints.last {
                let distFromLastPt = location.distance(from: CLLocation(latitude: lastPt.latitude, longitude: lastPt.longitude))
                if distFromLastPt >= 15.0 {
                    sessionPoints.append(location.coordinate)
                }
            }
        }
        
        if location.speed > 0 {
            if location.speed > sessionMaxSpeedMps {
                sessionMaxSpeedMps = location.speed
            }
        }
        
        if let start = sessionStartTime {
            currentSessionDurationSeconds = Date().timeIntervalSince(start)
        }
    }
    
    // MARK: - Kết thúc phiên lộ trình (khi tắt máy xe / ngắt kết nối / dừng dẫn đường)
    public func endTripSession(at endCoord: CLLocationCoordinate2D? = nil, completion: ((TripRecord?) -> Void)? = nil) {
        guard isRecordingSession else {
            completion?(nil)
            return
        }
        isRecordingSession = false
        
        let endTime = Date()
        let startTime = sessionStartTime ?? endTime
        let duration = max(1.0, endTime.timeIntervalSince(startTime))
        let totalDistance = currentSessionDistanceMeters
        
        let endCoordinate = endCoord ?? lastRecordedLocation?.coordinate ?? sessionStartCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let startCoordinate = sessionStartCoordinate ?? endCoordinate
        
        // KIỂM TRA ĐIỀU KIỆN TIÊN QUYẾT: CHỈ LƯU CÁC LỘ TRÌNH ĐÃ CHẠY ÍT NHẤT 50M
        if totalDistance < 50.0 {
            YamahaCCUManager.shared?.log("⚠️ [Lộ trình] Quãng đường \(Int(totalDistance))m < 50m -> Bỏ qua, không lưu lộ trình này.")
            resetSession()
            completion?(nil)
            return
        }
        
        // Tính tốc độ trung bình (km/h) = (km) / (giờ)
        let avgSpeedKmh = (totalDistance / 1000.0) / (duration / 3600.0)
        let maxSpeedKmh = sessionMaxSpeedMps * 3.6
        let parkingTime = endTime
        
        // Thêm điểm cuối vào polyline
        if let lastPt = sessionPoints.last {
            let distToEnd = CLLocation(latitude: endCoordinate.latitude, longitude: endCoordinate.longitude)
                .distance(from: CLLocation(latitude: lastPt.latitude, longitude: lastPt.longitude))
            if distToEnd > 5.0 {
                sessionPoints.append(endCoordinate)
            }
        }
        
        let poly = sessionPoints.map { [$0.latitude, $0.longitude] }
        let initialEndAddr = String(format: "%.5f, %.5f", endCoordinate.latitude, endCoordinate.longitude)
        let bike = self.sessionBikeName
        let startAddr = self.sessionStartAddress
        
        // Dịch tên địa chỉ điểm kết thúc
        let endLoc = CLLocation(latitude: endCoordinate.latitude, longitude: endCoordinate.longitude)
        geocoder.reverseGeocodeLocation(endLoc) { [weak self] placemarks, _ in
            guard let self = self else { return }
            var resolvedEndAddr = initialEndAddr
            if let pm = placemarks?.first {
                var components: [String] = []
                if let subThoroughfare = pm.subThoroughfare, let thoroughfare = pm.thoroughfare {
                    components.append("\(subThoroughfare) \(thoroughfare)")
                } else if let thoroughfare = pm.thoroughfare {
                    components.append(thoroughfare)
                } else if let name = pm.name {
                    components.append(name)
                }
                if let subLocality = pm.subLocality { components.append(subLocality) }
                if let locality = pm.locality { components.append(locality) }
                if !components.isEmpty {
                    resolvedEndAddr = components.joined(separator: ", ")
                }
            }
            
            let trip = TripRecord(
                id: UUID(),
                startTime: startTime,
                endTime: endTime,
                startLatitude: startCoordinate.latitude,
                startLongitude: startCoordinate.longitude,
                startAddress: startAddr.isEmpty ? "Vị trí xuất phát" : startAddr,
                endLatitude: endCoordinate.latitude,
                endLongitude: endCoordinate.longitude,
                endAddress: resolvedEndAddr,
                distanceMeters: totalDistance,
                durationSeconds: duration,
                averageSpeedKmh: avgSpeedKmh,
                maxSpeedKmh: maxSpeedKmh,
                parkingTimestamp: parkingTime,
                bikeName: bike,
                polylinePoints: poly
            )
            
            DispatchQueue.main.async {
                self.trips.insert(trip, at: 0)
                self.saveTrips()
                
                // Đồng thời ghi nhận vị trí đỗ xe MỚI với timestamp = thời điểm kết thúc lộ trình!
                ParkingLocationManager.shared.recordParkingLocation(
                    coordinate: endCoordinate,
                    bikeName: bike,
                    timestamp: parkingTime,
                    explicitAddress: resolvedEndAddr,
                    forceNewTimestamp: true
                )
                
                YamahaCCUManager.shared?.log("🏁 [Lộ trình] Đã lưu lộ trình: \(trip.formattedDistance), thời gian: \(trip.formattedDuration), tốc độ TB: \(trip.formattedAverageSpeed), đỗ xe lúc: \(trip.formattedParkingTime)")
                completion?(trip)
            }
        }
        
        resetSession()
    }
    
    private func resetSession() {
        sessionStartTime = nil
        sessionStartCoordinate = nil
        sessionStartAddress = ""
        lastRecordedLocation = nil
        sessionPoints.removeAll()
        currentSessionDistanceMeters = 0.0
        currentSessionDurationSeconds = 0.0
        sessionMaxSpeedMps = 0.0
    }
    
    public func deleteTrip(id: UUID) {
        trips.removeAll { $0.id == id }
        saveTrips()
    }
    
    public func clearAllTrips() {
        trips.removeAll()
        saveTrips()
    }
}
