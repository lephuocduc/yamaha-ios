import SwiftUI
import CoreLocation

public struct MainDashboardView: View {
    @ObservedObject var ccuManager: YamahaCCUManager
    @ObservedObject var navEngine: NavigationEngine
    
    @State private var searchQuery = ""
    @State private var showSearchSheet = false
    @State private var showGasSheet = false
    
    public init(ccuManager: YamahaCCUManager, navEngine: NavigationEngine) {
        self.ccuManager = ccuManager
        self.navEngine = navEngine
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.10)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Thẻ trạng thái kết nối xe
                        connectionStatusCard
                        
                        // 2. Thẻ thông số xe (Telemetry HUD)
                        telemetryCard
                        
                        // 3. Khung xem trước màn hình TFT (TFT Mirror Live Preview)
                        tftPreviewCard
                        
                        // 4. Các nút tác vụ nhanh (Quick Destinations)
                        quickActionsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("NConnect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if ccuManager.state == .disconnected || ccuManager.state == .error {
                            ccuManager.startScanning()
                        } else {
                            ccuManager.disconnect()
                        }
                    }) {
                        Image(systemName: ccuManager.state == .connected || ccuManager.state == .streaming ? "antenna.radiowaves.left.and.right" : "arrow.clockwise")
                            .foregroundColor(ccuManager.state == .connected || ccuManager.state == .streaming ? .green : .cyan)
                    }
                }
            }
            .sheet(isPresented: $showSearchSheet) {
                searchDestinationSheet
            }
            .sheet(isPresented: $showGasSheet) {
                gasStationsSheet
            }
        }
    }
    
    // MARK: - Thẻ trạng thái kết nối
    private var connectionStatusCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(ccuManager.state.rawValue)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                if let bike = ccuManager.connectedBike {
                    Text("Thiết bị: \(bike.name)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                } else {
                    Text("Bật chìa khóa xe để tự động kết nối...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Button(action: {
                if ccuManager.state == .disconnected || ccuManager.state == .error {
                    ccuManager.startScanning()
                } else if ccuManager.state == .connected || ccuManager.state == .authenticating {
                    ccuManager.startStreaming()
                } else if ccuManager.state == .streaming {
                    ccuManager.state = .connected
                }
            }) {
                Text(ccuManager.state == .streaming ? "Đang chiếu TFT" : (ccuManager.state == .connected ? "Chiếu lên xe" : (ccuManager.state == .authenticating ? "Bắt đầu chiếu" : "Kết nối")))
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(statusColor.opacity(0.2))
                    .foregroundColor(statusColor)
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(statusColor, lineWidth: 1))
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(16)
    }
    
    // MARK: - Thẻ thông số xe
    private var telemetryCard: some View {
        HStack(spacing: 16) {
            // Tốc độ
            VStack {
                Text("\(Int(ccuManager.telemetry.speedKmh))")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("KM/H")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Vòng tua máy RPM
            VStack {
                Text("\(ccuManager.telemetry.rpm)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.cyan)
                Text("VÒNG/PHÚT")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Xăng
            VStack {
                Text("\(ccuManager.telemetry.fuelPercent)%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                Text("NHIÊN LIỆU")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(16)
    }
    
    // MARK: - Khung xem trước màn hình TFT
    private var tftPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Màn hình TFT của xe", systemImage: "display")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("480 × 272 px")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Button(action: {
                ccuManager.startStreaming()
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .frame(height: 180)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ccuManager.state == .streaming ? Color.green : Color.cyan.opacity(0.4), lineWidth: 1.5))
                    
                    VStack(spacing: 8) {
                        if navEngine.isNavigating {
                            Image(systemName: navEngine.currentInstruction.direction.iconName)
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            Text(navEngine.currentInstruction.formattedDistance)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Text(navEngine.currentInstruction.nextRoadName)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        } else {
                            Image(systemName: ccuManager.state == .streaming ? "antenna.radiowaves.left.and.right" : "map")
                                .font(.system(size: 32))
                                .foregroundColor(ccuManager.state == .streaming ? .green : .cyan)
                            Text(ccuManager.state == .streaming ? "Đang truyền dữ liệu lên xe" : "Bấm để bắt đầu chiếu lên xe")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(ccuManager.state == .streaming ? "Đang phát tín hiệu TFT" : "Chọn điểm đến hoặc bấm vào đây để chiếu")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(16)
    }
    
    // MARK: - Nút tác vụ nhanh
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            // Nút tìm kiếm điểm đến
            Button(action: { showSearchSheet = true }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.cyan)
                    Text("Tìm kiếm địa điểm...")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding()
                .background(Color(white: 0.15))
                .cornerRadius(12)
            }
            
            HStack(spacing: 12) {
                // Đi làm
                quickButton(title: "Đi làm", icon: "briefcase.fill", color: .blue) {
                    // Tọa độ ví dụ hoặc mở bản đồ chọn
                    showSearchSheet = true
                }
                
                // Về nhà
                quickButton(title: "Về nhà", icon: "house.fill", color: .green) {
                    showSearchSheet = true
                }
                
                // Trạm xăng trong 5km
                quickButton(title: "Trạm xăng", icon: "fuelpump.fill", color: .orange) {
                    navEngine.fetchNearbyGasStations()
                    showGasSheet = true
                }
            }
        }
    }
    
    private func quickButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(white: 0.15))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Sheet tìm kiếm địa điểm
    private var searchDestinationSheet: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Nhập tên đường, quán xá, tòa nhà...", text: $searchQuery)
                        .onChange(of: searchQuery) { val in
                            navEngine.searchPlaces(query: val)
                        }
                }
                .padding()
                .background(Color(white: 0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                List(navEngine.searchResults) { item in
                    Button(action: {
                        navEngine.calculateRoute(to: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude))
                        showSearchSheet = false
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline).foregroundColor(.primary)
                            Text(item.subtitle).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Chọn điểm đến")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showSearchSheet = false }
                }
            }
        }
    }
    
    // MARK: - Sheet danh sách trạm xăng lân cận
    private var gasStationsSheet: some View {
        NavigationView {
            List(navEngine.nearbyGasStations) { station in
                Button(action: {
                    navEngine.calculateRoute(to: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude))
                    showGasSheet = false
                }) {
                    HStack {
                        Image(systemName: "fuelpump.fill").foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(station.title).font(.headline).foregroundColor(.primary)
                            Text(station.subtitle).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Trạm xăng trong 5km")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showGasSheet = false }
                }
            }
        }
    }
    
    private var statusColor: Color {
        switch ccuManager.state {
        case .connected, .streaming: return .green
        case .scanning, .connecting, .authenticating: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}
