import SwiftUI
import CoreLocation

public struct MainDashboardView: View {
    @ObservedObject var ccuManager: YamahaCCUManager
    @ObservedObject var navEngine: NavigationEngine
    @ObservedObject var streamRenderer: TFTStreamRenderer
    
    @State private var searchQuery = ""
    @State private var showSearchSheet = false
    @State private var showGasSheet = false
    @State private var settingLocationType: SavedLocation.LocationType? = nil
    
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
                        // Thông báo khi xe đã đến nơi đích
                        if let arrivalMsg = navEngine.arrivalMessage {
                            HStack(spacing: 12) {
                                Image(systemName: "flag.checkered.circle.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ĐÃ ĐẾN NƠI!")
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundColor(.green)
                                    Text(arrivalMsg)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    withAnimation {
                                        navEngine.arrivalMessage = nil
                                    }
                                }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(12)
                            .background(Color(red: 0.04, green: 0.16, blue: 0.08).opacity(0.96))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.green, lineWidth: 1.5)
                            )
                            .shadow(color: Color.green.opacity(0.4), radius: 8)
                        }
                        
                        // 1. Thẻ trạng thái kết nối xe
                        connectionStatusCard
                        
                        // 2. Thẻ thông số xe (Telemetry HUD)
                        telemetryCard
                        
                        // 3. Khung xem trước màn hình TFT (TFT Mirror Live Preview)
                        tftPreviewCard
                        
                        // 4. Các nút tác vụ nhanh (Quick Destinations)
                        quickActionsSection
                        
                        // 5. Danh sách địa điểm yêu thích (Favorite Places)
                        favoriteLocationsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("MyNMAX")
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
                if ccuManager.state == .streaming {
                    ccuManager.state = .connected
                } else if ccuManager.isMFiConnected || ccuManager.state == .connected || ccuManager.state == .authenticating {
                    ccuManager.startStreaming()
                } else {
                    ccuManager.startScanning()
                }
            }) {
                Text(ccuManager.state == .streaming ? "Đang chiếu TFT" : ((ccuManager.isMFiConnected || ccuManager.state == .connected) ? "Chiếu lên xe" : (ccuManager.state == .authenticating ? "Bắt đầu chiếu" : "Kết nối")))
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
    
    // MARK: - Thẻ thông số xe (HUD)
    private var telemetryCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                // Tốc độ GPS thực tế thời gian thực
                VStack {
                    let currentSpeed = navEngine.currentSpeedKmh >= 2.5 ? navEngine.currentSpeedKmh : 0.0
                    Text("\(Int(currentSpeed))")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("KM/H (GPS)")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                
                Divider().background(Color.gray.opacity(0.3))
                
                // Vòng tua máy RPM
                VStack {
                    if ccuManager.telemetry.rpm >= 800 {
                        Text("\(ccuManager.telemetry.rpm)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan)
                        Text("VÒNG/PHÚT")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                    } else {
                        Text(ccuManager.isMFiConnected || ccuManager.state == .connected ? "Theo xe" : "--")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan.opacity(0.85))
                        Text("VÒNG TUA (LCD)")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider().background(Color.gray.opacity(0.3))
                
                // Xăng
                VStack {
                    if ccuManager.telemetry.fuelPercent > 0 && ccuManager.telemetry.fuelPercent < 100 {
                        Text("\(ccuManager.telemetry.fuelPercent)%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        Text("NHIÊN LIỆU")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                    } else {
                        Text(ccuManager.isMFiConnected || ccuManager.state == .connected ? "Theo xe" : "--")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.orange.opacity(0.85))
                        Text("MỨC XĂNG (LCD)")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            if ccuManager.isMFiConnected || ccuManager.state == .connected {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("Vòng tua máy và mức xăng hiển thị trực tiếp trên cụm đồng hồ LCD chính của xe.")
                }
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                if !ccuManager.currentRoadNameOnTFT.isEmpty {
                    Text("▲ \(ccuManager.currentRoadNameOnTFT)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                }
            }
            
            ZStack(alignment: .bottomTrailing) {
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
                
                // Nút Zoom In / Zoom Out trực tiếp trên bản đồ xem trước
                HStack(spacing: 8) {
                    Text(streamRenderer.zoomDescription)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(6)
                    
                    Spacer()
                    
                    Button(action: { streamRenderer.zoomIn() }) {
                        Image(systemName: "plus")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.cyan.opacity(0.6), lineWidth: 1))
                    }
                    
                    Button(action: { streamRenderer.zoomOut() }) {
                        Image(systemName: "minus")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.cyan.opacity(0.6), lineWidth: 1))
                    }
                }
                .padding(10)
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(16)
    }
    
    // MARK: - Nút tác vụ nhanh (Đi làm, Về nhà, Trạm xăng)
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            // Nút tìm kiếm điểm đến
            Button(action: {
                settingLocationType = nil
                showSearchSheet = true
            }) {
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
                quickDestinationButton(
                    title: "Đi làm",
                    subtitle: navEngine.workLocation?.title ?? "Chưa lưu",
                    icon: "briefcase.fill",
                    color: .blue
                ) {
                    if let work = navEngine.workLocation {
                        navEngine.calculateRoute(to: work.coordinate, destinationTitle: work.title)
                        ccuManager.startStreaming()
                    } else {
                        settingLocationType = .work
                        showSearchSheet = true
                    }
                } onEdit: {
                    settingLocationType = .work
                    showSearchSheet = true
                }
                
                // Về nhà
                quickDestinationButton(
                    title: "Về nhà",
                    subtitle: navEngine.homeLocation?.title ?? "Chưa lưu",
                    icon: "house.fill",
                    color: .green
                ) {
                    if let home = navEngine.homeLocation {
                        navEngine.calculateRoute(to: home.coordinate, destinationTitle: home.title)
                        ccuManager.startStreaming()
                    } else {
                        settingLocationType = .home
                        showSearchSheet = true
                    }
                } onEdit: {
                    settingLocationType = .home
                    showSearchSheet = true
                }
                
                // Trạm xăng trong 5km
                Button(action: {
                    navEngine.fetchNearbyGasStations()
                    showGasSheet = true
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: "fuelpump.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                        Text("Trạm xăng")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Text("Gần bạn")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.15))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private func quickDestinationButton(title: String, subtitle: String, icon: String, color: Color, onNavigate: @escaping () -> Void, onEdit: @escaping () -> Void) -> some View {
        Button(action: onNavigate) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(white: 0.15))
            .cornerRadius(12)
        }
        .contextMenu {
            Button("Thay đổi địa chỉ \(title)") {
                onEdit()
            }
        }
    }
    
    // MARK: - Mục Địa điểm Yêu thích
    private var favoriteLocationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Địa điểm yêu thích", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundColor(.yellow)
                Spacer()
                Button(action: {
                    settingLocationType = .favorite
                    showSearchSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Thêm")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(8)
                }
            }
            
            if navEngine.favoriteLocations.isEmpty {
                Text("Chưa có địa điểm yêu thích. Nhấn '+ Thêm' để lưu quán ăn, quán cà phê, nhà bạn bè...")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 6)
            } else {
                ForEach(navEngine.favoriteLocations) { fav in
                    HStack {
                        Button(action: {
                            navEngine.calculateRoute(to: fav.coordinate, destinationTitle: fav.title)
                            ccuManager.startStreaming()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "star.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fav.title)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Text(fav.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.cyan)
                            }
                        }
                        
                        Button(action: {
                            navEngine.removeFavoriteLocation(id: fav.id)
                        }) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.8))
                                .padding(8)
                        }
                    }
                    .padding(10)
                    .background(Color(white: 0.15))
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(16)
    }
    
    // MARK: - Sheet tìm kiếm địa điểm & lưu địa điểm
    private var searchDestinationSheet: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.cyan)
                    TextField("Nhập tên đường, địa chỉ, quán xá...", text: $searchQuery)
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
                        Text("Đang tìm '\(searchQuery)' trên OpenStreetMap...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                }
                
                List(navEngine.searchResults) { item in
                    HStack {
                        Button(action: {
                            if let target = settingLocationType {
                                switch target {
                                case .home:
                                    navEngine.setHomeLocation(item)
                                case .work:
                                    navEngine.setWorkLocation(item)
                                case .favorite:
                                    navEngine.addFavoriteLocation(item)
                                case .gas:
                                    break
                                }
                                settingLocationType = nil
                            } else {
                                navEngine.calculateRoute(to: item.coordinate, destinationTitle: item.title)
                                ccuManager.startStreaming()
                            }
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
                        
                        Spacer()
                        
                        Menu {
                            Button("🏠 Đặt làm Về nhà") {
                                navEngine.setHomeLocation(item)
                                showSearchSheet = false
                            }
                            Button("💼 Đặt làm Đi làm") {
                                navEngine.setWorkLocation(item)
                                showSearchSheet = false
                            }
                            Button("⭐ Lưu vào Yêu thích") {
                                navEngine.addFavoriteLocation(item)
                                showSearchSheet = false
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundColor(.cyan)
                                .padding(8)
                        }
                    }
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        settingLocationType = nil
                        showSearchSheet = false
                    }
                }
            }
        }
    }
    
    private var sheetTitle: String {
        switch settingLocationType {
        case .home: return "Đặt địa chỉ Về nhà"
        case .work: return "Đặt địa chỉ Đi làm"
        case .favorite: return "Thêm địa điểm Yêu thích"
        default: return "Tìm kiếm & Dẫn đường"
        }
    }
    
    // MARK: - Sheet danh sách trạm xăng lân cận
    private var gasStationsSheet: some View {
        NavigationView {
            VStack {
                if navEngine.nearbyGasStations.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Đang quét trạm xăng OpenStreetMap gần bạn...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                }
                
                List(navEngine.nearbyGasStations) { station in
                    Button(action: {
                        navEngine.calculateRoute(to: station.coordinate, destinationTitle: station.title)
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
        if ccuManager.isMFiConnected || ccuManager.state == .connected || ccuManager.state == .streaming {
            return .green
        }
        switch ccuManager.state {
        case .connected, .streaming: return .green
        case .scanning, .connecting, .authenticating: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}
