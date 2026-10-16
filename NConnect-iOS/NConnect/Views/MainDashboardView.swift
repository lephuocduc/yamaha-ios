import SwiftUI
import CoreLocation

public struct MainDashboardView: View {
    @ObservedObject var ccuManager: YamahaCCUManager
    @ObservedObject var navEngine: NavigationEngine
    @ObservedObject var streamRenderer: TFTStreamRenderer
    
    @State private var searchQuery = ""
    @State private var showSearchSheet = false
    @State private var showGasSheet = false
    
    public init(ccuManager: YamahaCCUManager, navEngine: NavigationEngine, streamRenderer: TFTStreamRenderer) {
        self.ccuManager = ccuManager
        self.navEngine = navEngine
        self.streamRenderer = streamRenderer
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
                    Text(ccuManager.isMFiConnected ? "Đã kết nối màn hình TFT" : ccuManager.state.rawValue)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                if ccuManager.isMFiConnected {
                    Text("Màn hình xe: \(ccuManager.mfiAccessoryName)")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else if let bike = ccuManager.connectedBike {
                    Text("Thiết bị BLE: \(bike.name)")
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
            // Tốc độ (Ưu tiên thông số xe CCU, nếu xe chưa chạy thì lấy tốc độ GPS thực tế của iPhone)
            VStack {
                let rawSpeed = ccuManager.telemetry.speedKmh > 0 ? ccuManager.telemetry.speedKmh : navEngine.currentSpeedKmh
                let currentSpeed = rawSpeed >= 2.5 ? rawSpeed : 0.0
                Text("\(Int(currentSpeed))")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("KM/H")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Vòng tua máy RPM (Dải vòng tua thực tế xe máy khi nổ máy: 800 - 13000 RPM)
            VStack {
                Text(ccuManager.telemetry.rpm >= 800 ? "\(ccuManager.telemetry.rpm)" : "--")
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
                Text(ccuManager.telemetry.fuelPercent > 0 ? "\(ccuManager.telemetry.fuelPercent)%" : "--%")
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
    
    // MARK: - Khung xem trước màn hình TFT (Bản đồ thực tế đang chiếu lên xe)
    private var tftPreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Bản đồ chiếu lên xe (TFT Mirror)", systemImage: "map.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(streamRenderer.targetWidth) × \(streamRenderer.targetHeight) px")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Button(action: {
                if ccuManager.state == .streaming {
                    ccuManager.state = .connected
                } else {
                    ccuManager.startStreaming()
                }
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .frame(height: 190)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ccuManager.state == .streaming ? Color.green : Color.cyan.opacity(0.4), lineWidth: 1.5))
                    
                    if let image = streamRenderer.lastFrameImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 190)
                            .cornerRadius(12)
                    } else {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Đang tạo bản đồ...")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Bản đồ vệ tinh/đường phố sẽ hiển thị trực tiếp tại đây")
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
                        .foregroundColor(.cyan)
                    TextField("Nhập tên đường, quán xá, tòa nhà...", text: $searchQuery)
                        .submitLabel(.search)
                        .onSubmit {
                            navEngine.searchPlaces(query: searchQuery)
                        }
                        .onChange(of: searchQuery) { val in
                            navEngine.searchPlaces(query: val)
                        }
                    if !searchQuery.isEmpty {
                        Button(action: {
                            searchQuery = ""
                            navEngine.searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color(white: 0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                if navEngine.searchResults.isEmpty && !searchQuery.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Đang tìm '\(searchQuery)' bằng Apple Maps...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                }
                
                List(navEngine.searchResults) { item in
                    Button(action: {
                        navEngine.calculateRoute(to: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude))
                        ccuManager.startStreaming()
                        showSearchSheet = false
                    }) {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundColor(.cyan)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline).foregroundColor(.primary)
                                Text(item.subtitle).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
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
            VStack {
                if navEngine.nearbyGasStations.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Đang quét trạm xăng gần bạn trong 5km...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                }
                
                List(navEngine.nearbyGasStations) { station in
                    Button(action: {
                        navEngine.calculateRoute(to: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude))
                        ccuManager.startStreaming()
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
