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
    @ObservedObject private var callManager = CallNotificationManager.shared
    @ObservedObject private var notificationManager = AppNotificationManager.shared
    @ObservedObject private var parkingManager = ParkingLocationManager.shared
    
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
                        
                        // 0. Banner cuộc gọi đến (nếu có)
                        callNotificationBanner
                        
                        // 1. Thẻ trạng thái kết nối xe
                        connectionStatusCard
                        
                        // 2. Thẻ thông số xe (Telemetry HUD)
                        telemetryCard
                        
                        // 3. Vị trí đỗ xe tự động (Find My Bike)
                        parkingLocationCard
                        
                        // 4. Khung xem trước màn hình TFT (TFT Mirror Live Preview)
                        tftPreviewCard
                        
                        // 5. Các nút tác vụ nhanh (Quick Destinations)
                        quickActionsSection
                        
                        // 6. Danh sách địa điểm yêu thích (Favorite Places)
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
    
    // MARK: - Banner cảnh báo cuộc gọi đến
    private var callNotificationBanner: some View {
        Group {
            if callManager.isCallRinging {
                HStack(spacing: 12) {
                    Image(systemName: "phone.badge.waveform.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CUỘC GỌI ĐẾN")
                            .font(.caption2.bold())
                            .foregroundColor(Color(red: 0.9, green: 1.0, blue: 0.85))
                        Text(callManager.callerName.isEmpty ? "Cuộc gọi đến" : callManager.callerName)
                            .font(.headline)
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: { callManager.answerCall() }) {
                        Image(systemName: "phone.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    
                    Button(action: { callManager.rejectCall() }) {
                        Image(systemName: "phone.down.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Color(red: 0.08, green: 0.65, blue: 0.24))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                )
            } else if callManager.isCallConnected {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ĐANG ĐÀM THOẠI")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                        Text(callManager.callerName.isEmpty ? "Đang kết nối" : callManager.callerName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: { callManager.rejectCall() }) {
                        Image(systemName: "phone.down.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }
                .padding()
                .background(Color(red: 0.05, green: 0.35, blue: 0.15))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.green.opacity(0.5), lineWidth: 1.5)
                )
            } else if let notif = notificationManager.activeNotification {
                HStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(notif.appName.uppercased()) · \(notif.sender)")
                            .font(.caption2.bold())
                            .foregroundColor(.cyan)
                        Text(notif.message)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button(action: { notificationManager.dismissNotification() }) {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.7))
                            .padding(6)
                    }
                }
                .padding()
                .background(Color(red: 0.10, green: 0.16, blue: 0.26))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.cyan.opacity(0.6), lineWidth: 1.5)
                )
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
    
    // MARK: - Thẻ thông số xe (Telemetry HUD: RPM, Xăng, Ắc quy, Pin iPhone)
    private var telemetryCard: some View {
        VStack(spacing: 12) {
            // Hàng 1: Tốc độ, RPM, Xăng
            HStack(spacing: 12) {
                // Tốc độ GPS
                VStack(spacing: 4) {
                    let currentSpeed = navEngine.currentSpeedKmh >= 2.5 ? navEngine.currentSpeedKmh : 0.0
                    Text("\(Int(currentSpeed))")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("KM/H (GPS)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                
                Divider().background(Color.gray.opacity(0.3))
                
                // Vòng tua máy RPM
                VStack(spacing: 4) {
                    if ccuManager.telemetry.rpm >= 800 {
                        Text("\(ccuManager.telemetry.rpm)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(ccuManager.telemetry.rpm > 7000 ? .orange : .cyan)
                        Text("VÒNG/PHÚT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    } else {
                        Text(ccuManager.isMFiConnected || ccuManager.state == .connected ? "0 RPM" : "--")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.cyan.opacity(0.85))
                        Text("VÒNG TUA (ECU)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider().background(Color.gray.opacity(0.3))
                
                // Mức xăng
                VStack(spacing: 4) {
                    let fuel = ccuManager.telemetry.fuelPercent
                    if fuel > 0 && fuel <= 100 {
                        HStack(spacing: 2) {
                            Image(systemName: "fuelpump.fill")
                                .font(.system(size: 14))
                                .foregroundColor(fuel <= 20 ? .red : .orange)
                            Text("\(fuel)%")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(fuel <= 20 ? .red : .orange)
                        }
                        Text("NHIÊN LIỆU")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    } else {
                        Text(ccuManager.isMFiConnected || ccuManager.state == .connected ? "100%" : "--")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.orange.opacity(0.85))
                        Text("MỨC XĂNG (ECU)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            Divider().background(Color.white.opacity(0.08))
            
            // Hàng 2: Điện áp bình ắc quy, Nhiệt độ máy, Đồng bộ Pin iPhone lên xe
            HStack(spacing: 8) {
                // Điện áp bình ắc quy 12V
                HStack(spacing: 6) {
                    Image(systemName: "bolt.car.fill")
                        .foregroundColor(ccuManager.telemetry.batteryVoltage >= 12.2 ? .green : .orange)
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.1fV", ccuManager.telemetry.batteryVoltage))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(ccuManager.telemetry.batteryVoltage >= 12.2 ? "Ắc quy tốt" : "Bình yếu")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(ccuManager.telemetry.batteryVoltage >= 12.2 ? .green : .orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                
                Spacer()
                
                // Nhiệt độ nước làm mát / động cơ
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                        .foregroundColor(ccuManager.telemetry.engineTemperature > 95 ? .red : .cyan)
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ccuManager.telemetry.engineTemperature > 0 ? "\(Int(ccuManager.telemetry.engineTemperature))°C" : "85°C")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Nhiệt độ máy")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                
                Spacer()
                
                // Đồng bộ pin iPhone lên màn hình xe
                HStack(spacing: 6) {
                    Image(systemName: ccuManager.isPhoneCharging ? "battery.100.bolt" : "battery.75")
                        .foregroundColor(.green)
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 2) {
                            Text("\(ccuManager.phoneBatteryLevel)%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            if ccuManager.isPhoneCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.yellow)
                            }
                        }
                        Text("Đồng bộ xe")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            
            // Dòng trạng thái bắt tay CCU
            HStack(spacing: 6) {
                Circle()
                    .fill(ccuManager.isMFiConnected || ccuManager.state == .connected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(ccuManager.isMFiConnected || ccuManager.state == .connected
                     ? "Đã kết nối ECU & CCU • Bắt tay telemetry (309/310) • Đồng bộ icon cuộc gọi, tin nhắn & pin"
                     : "Bắt tay thu thập dữ liệu ECU (RPM, bình ắc quy, mức xăng) tự động khi bật khóa xe.")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.85))
                Spacer()
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(16)
    }
    
    // MARK: - Thẻ vị trí đỗ xe tự động (Find My Bike)
    private var parkingLocationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Thẻ
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.58, green: 0.20, blue: 0.92), Color(red: 0.40, green: 0.10, blue: 0.70)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 28, height: 28)
                        Image(systemName: "parkingsign.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("VỊ TRÍ ĐỖ XE (FIND MY BIKE)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.white)
                        Text("Tự động lưu GPS khi tắt máy xe")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if let parked = parkingManager.lastParkedLocation {
                    Text(parked.relativeTimeString)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.18))
                        .cornerRadius(6)
                }
            }
            
            if let parked = parkingManager.lastParkedLocation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.75, green: 0.40, blue: 1.0))
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(parked.address.isEmpty ? "Vị trí GPS xe đã lưu" : parked.address)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "figure.walk")
                                        .font(.system(size: 11))
                                    Text("Cách bạn \(parked.formattedDistance())")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.cyan)
                                
                                Text("•")
                                    .foregroundColor(.gray)
                                
                                Text(parked.bikeName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.08))
                    .cornerRadius(10)
                    
                    // Các nút thao tác tìm xe
                    HStack(spacing: 10) {
                        // Nút Dẫn đường đi bộ tới xe
                        Button(action: {
                            navEngine.calculateRoute(to: parked.coordinate, destinationTitle: "Xe \(parked.bikeName)")
                            ccuManager.startStreaming()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                Text("Dẫn đường tới xe")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color(red: 0.58, green: 0.20, blue: 0.92))
                            .cornerRadius(8)
                        }
                        
                        // Nút Apple Maps
                        Button(action: {
                            parked.openInAppleMaps()
                        }) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.cyan)
                                .padding(9)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }
                        
                        // Nút Google Maps
                        Button(action: {
                            parked.openInGoogleMaps()
                        }) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.green)
                                .padding(9)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }
                        
                        // Nút Xóa vị trí đỗ
                        Button(action: {
                            withAnimation {
                                parkingManager.clearParkingLocation()
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding(9)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "parkingsign")
                        .font(.system(size: 22))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chưa có vị trí đỗ xe")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                        Text("Vị trí GPS điện thoại sẽ tự động lưu lại ngay khi tắt khóa xe.")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Nút lưu thử vị trí hiện tại
                    Button(action: {
                        if let coord = navEngine.currentLocation?.coordinate {
                            parkingManager.recordParkingLocation(manualCoord: coord, bikeName: ccuManager.connectedBike?.name ?? "Yamaha NMAX")
                        } else {
                            parkingManager.recordParkingLocation(manualCoord: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009), bikeName: "Yamaha NMAX")
                        }
                    }) {
                        Text("Lưu thử")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.4), lineWidth: 1))
                    }
                }
                .padding(10)
                .background(Color(white: 0.08))
                .cornerRadius(10)
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
