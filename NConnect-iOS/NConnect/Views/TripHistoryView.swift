import SwiftUI
import CoreLocation
import MapKit

public struct TripHistoryView: View {
    @ObservedObject private var tripManager = TripHistoryManager.shared
    @State private var selectedTripForMap: TripRecord? = nil
    @State private var showDeleteAllAlert: Bool = false
    @State private var tripToDelete: TripRecord? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.10)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Banner phiên đang ghi trực tiếp (nếu xe đang chạy)
                        if tripManager.isRecordingSession {
                            activeSessionCard
                        }
                        
                        // 2. Thẻ tổng quan thống kê toàn bộ lộ trình
                        if !tripManager.trips.isEmpty {
                            summaryStatsCard
                        }
                        
                        // 3. Danh sách các lộ trình đã lưu
                        if tripManager.trips.isEmpty && !tripManager.isRecordingSession {
                            emptyStateView
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("LỊCH SỬ CHUYẾN ĐI")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(Color(white: 0.6))
                                    Spacer()
                                    Text("\(tripManager.trips.count) lộ trình")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.cyan)
                                }
                                .padding(.horizontal, 4)
                                
                                ForEach(tripManager.trips) { trip in
                                    TripCardView(trip: trip) {
                                        selectedTripForMap = trip
                                    } onDelete: {
                                        tripToDelete = trip
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Lộ trình di chuyển")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !tripManager.trips.isEmpty {
                        Button(action: { showDeleteAllAlert = true }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red.opacity(0.85))
                        }
                    }
                }
            }
            .alert(isPresented: $showDeleteAllAlert) {
                Alert(
                    title: Text("Xoá toàn bộ lịch sử?"),
                    message: Text("Tất cả lộ trình đã ghi lại sẽ bị xóa vĩnh viễn khỏi thiết bị."),
                    primaryButton: .destructive(Text("Xoá tất cả")) {
                        tripManager.clearAllTrips()
                    },
                    secondaryButton: .cancel(Text("Huỷ"))
                )
            }
            .alert(item: $tripToDelete) { trip in
                Alert(
                    title: Text("Xoá lộ trình này?"),
                    message: Text("Lộ trình \(trip.formattedDistance) ngày \(trip.formattedDate) sẽ bị xóa."),
                    primaryButton: .destructive(Text("Xoá")) {
                        tripManager.deleteTrip(id: trip.id)
                    },
                    secondaryButton: .cancel(Text("Huỷ"))
                )
            }
            .sheet(item: $selectedTripForMap) { trip in
                TripDetailSheet(trip: trip)
            }
        }
    }
    
    // MARK: - Thẻ hiển thị phiên đang ghi nhận trực tiếp
    private var activeSessionCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.green.opacity(0.5), lineWidth: 3)
                            .scaleEffect(1.4)
                    )
                Text("ĐANG THEO DÕI LỘ TRÌNH XE CHẠY")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.green)
                Spacer()
                Text("Tự động")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                    .foregroundColor(.green)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quãng đường")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.7))
                    let dist = tripManager.currentSessionDistanceMeters
                    Text(dist < 1000 ? "\(Int(dist)) m" : String(format: "%.2f km", dist / 1000.0))
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.white)
                }
                
                Divider()
                    .frame(height: 36)
                    .background(Color(white: 0.2))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thời gian chạy")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.7))
                    let secs = Int(tripManager.currentSessionDurationSeconds)
                    let m = secs / 60
                    let s = secs % 60
                    Text(String(format: "%02d:%02d", m, s))
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.cyan)
                }
                Spacer()
            }
            
            // Điều kiện lưu: ít nhất 50m
            let progress = min(1.0, tripManager.currentSessionDistanceMeters / 50.0)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tripManager.currentSessionDistanceMeters >= 50.0 ? "✓ Đã đạt điều kiện lưu (> 50m)" : "Cần chạy ít nhất 50m để lưu lộ trình (\(Int(tripManager.currentSessionDistanceMeters))/50m)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(tripManager.currentSessionDistanceMeters >= 50.0 ? .green : .orange)
                    Spacer()
                }
                ProgressView(value: progress)
                    .accentColor(tripManager.currentSessionDistanceMeters >= 50.0 ? .green : .orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.08, green: 0.12, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                )
        )
    }
    
    // MARK: - Thẻ tổng quan số liệu toàn bộ chuyến đi
    private var summaryStatsCard: some View {
        let totalMeters = tripManager.trips.reduce(0.0) { $0 + $1.distanceMeters }
        let totalSecs = tripManager.trips.reduce(0.0) { $0 + $1.durationSeconds }
        let avgSpeed = totalSecs > 0 ? (totalMeters / 1000.0) / (totalSecs / 3600.0) : 0.0
        
        return HStack(spacing: 0) {
            StatItemView(
                title: "Tổng quãng đường",
                value: String(format: "%.1f", totalMeters / 1000.0),
                unit: "km",
                color: Color(red: 0.0, green: 1.0, blue: 0.45)
            )
            
            Divider()
                .frame(height: 40)
                .background(Color(white: 0.15))
            
            StatItemView(
                title: "Số chuyến đi",
                value: "\(tripManager.trips.count)",
                unit: "chuyến",
                color: .cyan
            )
            
            Divider()
                .frame(height: 40)
                .background(Color(white: 0.15))
            
            StatItemView(
                title: "Tốc độ TB",
                value: String(format: "%.1f", avgSpeed),
                unit: "km/h",
                color: Color(red: 1.0, green: 0.8, blue: 0.2)
            )
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.08, green: 0.10, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(white: 0.15), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Trạng thái trống (khi chưa có lộ trình nào)
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: 90, height: 90)
                Image(systemName: "map.circle")
                    .font(.system(size: 46))
                    .foregroundColor(.cyan)
            }
            
            Text("Chưa có lộ trình nào được lưu")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Text("Hệ thống sẽ tự động lưu lại thông tin chuyến đi mỗi khi bạn bật khóa và chạy xe từ 50 mét trở lên.\n\nNếu bạn chỉ mở khóa xe rồi tắt mà không chạy, thời gian đỗ xe sẽ được giữ nguyên.")
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)
            
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Thành phần chỉ số thống kê
private struct StatItemView: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.6))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Thẻ hiển thị 1 chuyến đi trong danh sách
private struct TripCardView: View {
    let trip: TripRecord
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Dòng 1: Ngày tháng & Quãng đường
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                        .foregroundColor(.cyan)
                    Text(trip.formattedDate)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("•")
                        .foregroundColor(Color(white: 0.4))
                    Text(trip.formattedTimeRange)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.7))
                }
                Spacer()
                Text(trip.formattedDistance)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(Color(red: 0.0, green: 1.0, blue: 0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.0, green: 1.0, blue: 0.45).opacity(0.12))
                    .cornerRadius(8)
            }
            
            Divider()
                .background(Color(white: 0.12))
            
            // Dòng 2: Điểm xuất phát -> Điểm kết thúc
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Xuất phát")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                        Text(trip.startAddress)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Kết thúc")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                        Text(trip.endAddress)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                }
            }
            
            Divider()
                .background(Color(white: 0.12))
            
            // Dòng 3: Thời gian chạy, Tốc độ trung bình, Thời gian đỗ xe
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 12))
                            .foregroundColor(.cyan)
                        Text(trip.formattedDuration)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.2))
                        Text("TB: \(trip.formattedAverageSpeed)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                // Mốc thời gian đỗ xe
                HStack(spacing: 6) {
                    Image(systemName: "parkingsign.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                    Text("Thời gian đỗ xe: \(trip.formattedParkingTime) (\(trip.relativeParkingDuration))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.75))
                    Spacer()
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.7))
                            .padding(4)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.09, green: 0.11, blue: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(white: 0.12), lineWidth: 1)
                )
        )
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Chi tiết lộ trình & Bản đồ xem lại
private struct TripDetailSheet: View {
    let trip: TripRecord
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.10)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Bản đồ lộ trình
                        TripMapView(trip: trip)
                            .frame(height: 240)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(white: 0.2), lineWidth: 1)
                            )
                        
                        // Chi tiết chỉ số
                        VStack(spacing: 14) {
                            DetailRow(title: "Quãng đường đã chạy", value: trip.formattedDistance, icon: "arrow.triangle.swap", color: Color(red: 0.0, green: 1.0, blue: 0.45))
                            DetailRow(title: "Thời gian di chuyển", value: trip.formattedDuration, icon: "stopwatch", color: .cyan)
                            DetailRow(title: "Tốc độ trung bình", value: trip.formattedAverageSpeed, icon: "speedometer", color: Color(red: 1.0, green: 0.8, blue: 0.2))
                            DetailRow(title: "Tốc độ tối đa", value: trip.formattedMaxSpeed, icon: "bolt.fill", color: .orange)
                            DetailRow(title: "Mốc đỗ xe tại đích", value: "\(trip.formattedParkingTime) (\(trip.relativeParkingDuration))", icon: "parkingsign.circle.fill", color: .blue)
                            DetailRow(title: "Phương tiện", value: trip.bikeName, icon: "bicycle", color: .purple)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 0.09, green: 0.11, blue: 0.15))
                        )
                        
                        // Địa chỉ
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CHI TIẾT ĐỊA ĐIỂM")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(white: 0.5))
                            
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Color.green).frame(width: 8, height: 8).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Điểm xuất phát:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Color(white: 0.6))
                                    Text(trip.startAddress)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Color.red).frame(width: 8, height: 8).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Điểm kết thúc:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Color(white: 0.6))
                                    Text(trip.endAddress)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 0.09, green: 0.11, blue: 0.15))
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Chi tiết lộ trình")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(white: 0.7))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Bản đồ lộ trình sử dụng MapKit
private struct TripMapView: UIViewRepresentable {
    let trip: TripRecord
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.overrideUserInterfaceStyle = .dark
        mapView.delegate = context.coordinator
        
        let startAnn = MKPointAnnotation()
        startAnn.coordinate = trip.startCoordinate
        startAnn.title = "Xuất phát"
        mapView.addAnnotation(startAnn)
        
        let endAnn = MKPointAnnotation()
        endAnn.coordinate = trip.endCoordinate
        endAnn.title = "Đích đến"
        mapView.addAnnotation(endAnn)
        
        // Polyline nếu có điểm tọa độ
        if trip.polylinePoints.count >= 2 {
            var coords = trip.polylinePoints.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            mapView.addOverlay(polyline)
        } else {
            var coords = [trip.startCoordinate, trip.endCoordinate]
            let polyline = MKPolyline(coordinates: &coords, count: coords.count)
            mapView.addOverlay(polyline)
        }
        
        // Zoom vừa khung
        let centerLat = (trip.startLatitude + trip.endLatitude) / 2.0
        let centerLon = (trip.startLongitude + trip.endLongitude) / 2.0
        let spanLat = max(0.008, abs(trip.endLatitude - trip.startLatitude) * 1.6)
        let spanLon = max(0.008, abs(trip.endLongitude - trip.startLongitude) * 1.6)
        mapView.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon), span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)), animated: false)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 0.95)
                renderer.lineWidth = 4.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let id = "TripMarker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            if annotation.title == "Xuất phát" {
                view.markerTintColor = .systemGreen
                view.glyphText = "A"
            } else {
                view.markerTintColor = .systemRed
                view.glyphText = "B"
            }
            return view
        }
    }
}
