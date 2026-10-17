import SwiftUI

public struct SettingsView: View {
    @ObservedObject var ccuManager: YamahaCCUManager
    
    @AppStorage("selectedBikeModel") private var selectedBikeModel = "Yamaha XMAX 300"
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("osmTileStyle") private var osmTileStyle = "OSM Chuẩn (Sáng)"
    @AppStorage("osrmServerUrl") private var osrmServerUrl = "https://router.project-osrm.org"
    
    let bikeModels = [
        "Yamaha XMAX 300",
        "Yamaha NMAX 155",
        "Yamaha YZF-R9",
        "Yamaha MT-09 / SP",
        "Yamaha XSR900 GP",
        "Xe hỗ trợ Garmin StreetCross khác"
    ]
    
    let osmTileStyles = [
        "OSM Chuẩn (Sáng)",
        "OSM Carto Dark (Tối cho xe)",
        "OSM Voyager (Sắc nét)"
    ]
    
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
                
                Section(header: Text("Bản đồ & Chỉ đường OpenStreetMap (Mã nguồn mở)")) {
                    Picker("Giao diện ngói bản đồ", selection: $osmTileStyle) {
                        ForEach(osmTileStyles, id: \.self) { style in
                            Text(style).tag(style)
                        }
                    }
                    .onChange(of: osmTileStyle) { val in
                        if val.contains("Dark") {
                            OSMTileEngine.shared.tileUrlTemplate = "https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png"
                        } else if val.contains("Voyager") {
                            OSMTileEngine.shared.tileUrlTemplate = "https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png"
                        } else {
                            OSMTileEngine.shared.tileUrlTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
                        }
                    }
                    
                    HStack {
                        Text("Máy chủ dẫn đường")
                        Spacer()
                        Text("OSRM (Open Source)")
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("✓ Không sử dụng Google Maps hay Apple Maps.")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("✓ Dữ liệu bản đồ & chỉ đường Turn-by-Turn 100% từ cộng đồng OpenStreetMap (ODbL).")
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
                
                Section(header: Text("Khắc phục 'Connection Error' trên màn hình xe")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("📱🔒")
                            Text("Giữ iPhone mở sáng và bật ứng dụng MyNMAX (không khóa màn hình).")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("ᛒ")
                            Text("Đảm bảo cả 2 kết nối Bluetooth: BLE (YCCU_...) và MFi (LinkCard).")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("🗺️📍")
                            Text("Vào Cài đặt iPhone > MyNMAX > Vị trí > Chọn 'Luôn luôn' (Always) & bật 'Vị trí chính xác'.")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.cyan)
                            Text("Bấm nút OK / Chọn ở cùm công tắc tay lái bên trái để tắt cảnh báo trên màn hình xe.")
                                .font(.caption.bold())
                                .foregroundColor(.cyan)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Nhật ký kết nối (Diagnostic Log)")) {
                    if ccuManager.diagnosticLogs.isEmpty {
                        Text("Chưa có nhật ký nào.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(ccuManager.diagnosticLogs.suffix(30), id: \.self) { logItem in
                                    Text(logItem)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                }
                
                Section(header: Text("Thông tin ứng dụng")) {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("0.5.2 (iOS Port)")
                            .foregroundColor(.secondary)
                    }
                    Text("MyNMAX - Dẫn đường và thông báo cho xe máy Yamaha NMAX có màn hình TFT.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Cài đặt")
        }
    }
}
