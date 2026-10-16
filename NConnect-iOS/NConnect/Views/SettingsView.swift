import SwiftUI

public struct SettingsView: View {
    @ObservedObject var ccuManager: YamahaCCUManager
    
    @AppStorage("selectedBikeModel") private var selectedBikeModel = "Yamaha XMAX 300"
    @AppStorage("mapProvider") private var mapProvider = "OpenStreetMap"
    @AppStorage("googleMapsApiKey") private var googleMapsApiKey = ""
    @AppStorage("autoReconnect") private var autoReconnect = true
    
    let bikeModels = [
        "Yamaha XMAX 300",
        "Yamaha NMAX 155",
        "Yamaha YZF-R9",
        "Yamaha MT-09 / SP",
        "Yamaha XSR900 GP",
        "Xe hỗ trợ Garmin StreetCross khác"
    ]
    
    let mapProviders = ["OpenStreetMap (Miễn phí)", "Google Maps SDK"]
    
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
                
                Section(header: Text("Cấu hình Bản đồ")) {
                    Picker("Nhà cung cấp bản đồ", selection: $mapProvider) {
                        ForEach(mapProviders, id: \.self) { provider in
                            Text(provider).tag(provider)
                        }
                    }
                    
                    if mapProvider.contains("Google") {
                        SecureField("Google Maps API Key", text: $googleMapsApiKey)
                    }
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
                            Text("Giữ iPhone mở sáng và bật ứng dụng NConnect (không khóa màn hình).")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("ᛒ")
                            Text("Đảm bảo cả 2 kết nối Bluetooth: BLE (YCCU_...) và MFi (LinkCard).")
                                .font(.caption)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("🗺️📍")
                            Text("Vào Cài đặt iPhone > NConnect > Vị trí > Chọn 'Luôn luôn' (Always) & bật 'Vị trí chính xác'.")
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
                    Text("NConnect - Dẫn đường và thông báo cho xe máy Yamaha có màn hình TFT.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Cài đặt")
        }
    }
}
