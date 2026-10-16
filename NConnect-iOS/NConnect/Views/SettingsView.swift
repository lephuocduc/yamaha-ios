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
                        Text("Trạng thái")
                        Spacer()
                        Text(ccuManager.state.rawValue)
                            .foregroundColor(.secondary)
                    }
                    
                    if let bike = ccuManager.connectedBike {
                        HStack {
                            Text("Tên Bluetooth")
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
