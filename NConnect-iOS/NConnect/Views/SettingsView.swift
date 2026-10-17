import SwiftUI
import CoreLocation

public struct SettingsView: View {
    @ObservedObject var ccuManager: YamahaCCUManager
    
    @AppStorage("selectedBikeModel") private var selectedBikeModel = "Yamaha XMAX 300"
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("osmTileStyle") private var osmTileStyle = "CartoDB Voyager (Khuyên dùng - Bản quyền API)"
    @AppStorage("cartoApiKey") private var cartoApiKey = OSMTileEngine.defaultCartoApiKey
    @AppStorage("valhallaServerUrl") private var valhallaServerUrl = "https://valhalla1.openstreetmap.de"
    
    let bikeModels = [
        "Yamaha XMAX 300",
        "Yamaha NMAX 155",
        "Yamaha YZF-R9",
        "Yamaha MT-09 / SP",
        "Yamaha XSR900 GP",
        "Xe hỗ trợ Garmin StreetCross khác"
    ]
    
    let osmTileStyles = [
        "CartoDB Voyager (Khuyên dùng - Bản quyền API)",
        "CartoDB Positron (Bản đồ sáng tối giản)",
        "CartoDB Dark Matter (Bản đồ đêm chuyên dụng)",
        "OpenStreetMap Chuẩn (FOSSGIS)",
        "OpenStreetMap Quốc Tế (Wikimedia)",
        "OpenStreetMap Xe 2 Bánh (CyclOSM)"
    ]
    
    @ObservedObject private var savedPlaces = SavedPlacesManager.shared
    
    public init(ccuManager: YamahaCCUManager) {
        self.ccuManager = ccuManager
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Dòng xe Yamaha")) {
                    Picker("Mẫu xe", selection: $selectedBikeModel) {
                        ForEach(bikeModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    
                    Toggle("Tự động kết nối khi bật xe", isOn: $autoReconnect)
                }
                
                Section(header: Text("Bản đồ & Thuật toán dẫn đường")) {
                    Picker("Giao diện bản đồ hiển thị", selection: $osmTileStyle) {
                        ForEach(osmTileStyles, id: \.self) { style in
                            Text(style).tag(style)
                        }
                    }
                    .onChange(of: osmTileStyle) { _ in
                        updateTileTemplate()
                    }
                    
                    if osmTileStyle.contains("CartoDB") {
                        HStack {
                            Text("Carto API Key")
                            Spacer()
                            TextField("API Key", text: $cartoApiKey)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.cyan)
                                .onChange(of: cartoApiKey) { _ in
                                    updateTileTemplate()
                                }
                        }
                    }
                    
                    HStack {
                        Text("Tầng thuật toán dẫn đường")
                        Spacer()
                        Text("Valhalla Engine")
                            .foregroundColor(.cyan)
                    }
                    
                    HStack {
                        Text("Chế độ phương tiện")
                        Spacer()
                        Text("Motorcycle (Xe máy)")
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("✓ Bản đồ CartoDB Voyager bản quyền với API Key riêng của bạn (sạch bóng, không watermark).")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("✓ Tầng thuật toán: Valhalla Routing Engine chuyên biệt cho xe máy (tiếng Việt).")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("✓ Tốc độ nạp ngói cực nhanh qua mạng lưới Carto CDN toàn cầu.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 2)
                }
                
                Section(header: Text("Thông tin thiết bị kết nối")) {
                    HStack {
                        Text("Trạng thái BLE")
                        Spacer()
                        Text(ccuManager.state.rawValue)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Màn hình TFT (MFi)")
                        Spacer()
                        Text(ccuManager.isMFiConnected ? "Đã kết nối (\(ccuManager.mfiAccessoryName))" : "Chưa kết nối")
                            .foregroundColor(ccuManager.isMFiConnected ? .green : .secondary)
                    }
                    
                    if !ccuManager.isMFiConnected {
                        Button(action: {
                            ccuManager.showMFiPairingPicker()
                        }) {
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                Text("Ghép đôi màn hình xe (MFi Bluetooth)")
                            }
                            .foregroundColor(.cyan)
                        }
                    }
                    
                    if let bike = ccuManager.connectedBike {
                        HStack {
                            Text("Tên Bluetooth BLE")
                            Spacer()
                            Text(bike.name)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Độ phân giải TFT")
                        Spacer()
                        Text("\(ccuManager.streetCross.displaySpec.width) × \(ccuManager.streetCross.displaySpec.height)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Mã phần mềm Garmin")
                        Spacer()
                        Text(StreetCrossProtocol.softwarePartNumber)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Nhật ký kết nối & Chẩn đoán (Diagnostic Log)")) {
                    HStack(spacing: 12) {
                        Button(action: {
                            let allLogs = ccuManager.diagnosticLogs.joined(separator: "\n")
                            UIPasteboard.general.string = allLogs.isEmpty ? "Chưa có log" : allLogs
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc.fill")
                                Text("Sao chép nhật ký")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cyan)
                            .cornerRadius(8)
                        }
                        
                        Button(action: {
                            let allLogs = ccuManager.diagnosticLogs.joined(separator: "\n")
                            let av = UIActivityViewController(activityItems: [allLogs], applicationActivities: nil)
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootVC = windowScene.windows.first?.rootViewController {
                                rootVC.present(av, animated: true)
                            }
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Xuất file log")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if ccuManager.diagnosticLogs.isEmpty {
                        Text("Chưa có nhật ký nào.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(ccuManager.diagnosticLogs.suffix(60), id: \.self) { logItem in
                                    Text(logItem)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                }
                

                
                Section(header: Text("Địa điểm trên Menu xe máy (Home, Work, Gas, Fav)")) {
                    // 1. NHÀ (Go home - Mã 53)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "house.fill")
                                .foregroundColor(.orange)
                            Text("Địa chỉ Nhà (Go home)")
                                .fontWeight(.semibold)
                            Spacer()
                            if savedPlaces.homePlace != nil {
                                Text("Đã lưu")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            } else {
                                Text("Chưa cài")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        if let home = savedPlaces.homePlace {
                            Text("\(home.name): \(String(format: "%.4f", home.latitude)), \(String(format: "%.4f", home.longitude))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                savedPlaces.clearHome()
                            }) {
                                Text("Xoá địa chỉ Nhà")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        } else {
                            Button(action: {
                                if let loc = CLLocationManager().location?.coordinate {
                                    savedPlaces.setHome(name: "Nhà riêng", coordinate: loc)
                                } else {
                                    savedPlaces.setHome(name: "Nhà riêng", coordinate: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009))
                                }
                            }) {
                                HStack {
                                    Image(systemName: "location.fill")
                                    Text("Lấy vị trí GPS hiện tại làm Nhà")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // 2. NƠI LÀM VIỆC (Go to work - Mã 54)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "briefcase.fill")
                                .foregroundColor(.blue)
                            Text("Nơi làm việc (Go to work)")
                                .fontWeight(.semibold)
                            Spacer()
                            if savedPlaces.workPlace != nil {
                                Text("Đã lưu")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            } else {
                                Text("Chưa cài")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        if let work = savedPlaces.workPlace {
                            Text("\(work.name): \(String(format: "%.4f", work.latitude)), \(String(format: "%.4f", work.longitude))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                savedPlaces.clearWork()
                            }) {
                                Text("Xoá nơi làm việc")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        } else {
                            Button(action: {
                                if let loc = CLLocationManager().location?.coordinate {
                                    savedPlaces.setWork(name: "Công ty", coordinate: loc)
                                } else {
                                    savedPlaces.setWork(name: "Công ty", coordinate: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009))
                                }
                            }) {
                                HStack {
                                    Image(systemName: "location.fill")
                                    Text("Lấy vị trí GPS hiện tại làm Chỗ làm")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // 3. CÂY XĂNG GẦN NHẤT (Gas station - Mã 55 sub 4)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "fuelpump.fill")
                                .foregroundColor(.green)
                            Text("Tìm cây xăng gần nhất (Gas station)")
                                .fontWeight(.semibold)
                        }
                        Text("Khi chọn 'Gas station' trên cùm xe, hệ thống sẽ tự động quét trạm xăng gần vị trí xe nhất và bắt đầu dẫn đường tức thì.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Thông tin ứng dụng")) {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("0.5.23 (Build 49)")
                            .foregroundColor(.secondary)
                    }
                    Text("MyNMAX - Dẫn đường Turn-by-Turn cho xe máy Yamaha có màn hình TFT.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Cài đặt")
            .onAppear {
                updateTileTemplate()
            }
        }
    }
    
    private func updateTileTemplate() {
        let key = cartoApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? OSMTileEngine.defaultCartoApiKey : cartoApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let tmpl: String
        let styleKey: String
        if osmTileStyle.contains("Voyager") {
            tmpl = "https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png?key=\(key)"
            styleKey = "voyager"
        } else if osmTileStyle.contains("Positron") {
            tmpl = "https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png?key=\(key)"
            styleKey = "positron"
        } else if osmTileStyle.contains("Dark Matter") {
            tmpl = "https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?key=\(key)"
            styleKey = "darkmatter"
        } else if osmTileStyle.contains("Wikimedia") {
            tmpl = "https://maps.wikimedia.org/osm-intl/{z}/{x}/{y}.png"
            styleKey = "wikimedia"
        } else if osmTileStyle.contains("CyclOSM") {
            tmpl = "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png"
            styleKey = "cyclosm"
        } else {
            tmpl = "https://tile.openstreetmap.de/{z}/{x}/{y}.png"
            styleKey = "osm_standard"
        }
        OSMTileEngine.shared.updateStyle(template: tmpl, styleKey: styleKey)
        UserDefaults.standard.set(tmpl, forKey: "savedTileUrlTemplate")
        UserDefaults.standard.set(styleKey, forKey: "savedTileStyleKey")
    }
}
