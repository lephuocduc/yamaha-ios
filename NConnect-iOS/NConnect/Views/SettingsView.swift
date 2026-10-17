import SwiftUI

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
    
    @ObservedObject private var notificationManager = AppNotificationManager.shared
    @State private var showShortcutsGuide = false
    
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
                
                Section(header: Text("Thông báo ứng dụng lên màn hình xe (TFT)")) {
                    Toggle("Hiển thị thông báo lên màn hình xe", isOn: $notificationManager.isNotificationsEnabled)
                    
                    Stepper(value: $notificationManager.displayDurationSeconds, in: 3...30) {
                        HStack {
                            Text("Thời gian hiển thị:")
                            Spacer()
                            Text("\(notificationManager.displayDurationSeconds) giây")
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Cuộc gọi đến: Nền xanh lá cây, hiện tên/số điện thoại liên tục cho tới khi cuộc gọi kết thúc.")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("• Thông báo ứng dụng (Zalo, Messenger, SMS...): Tự động tắt sau \(notificationManager.displayDurationSeconds) giây.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    
                    // Nút bấm thử nghiệm
                    VStack(spacing: 8) {
                        Button(action: {
                            notificationManager.postNotification(
                                appName: "Zalo",
                                sender: "Nguyễn Văn A",
                                message: "Chiều nay đi uống cà phê nhé!"
                            )
                        }) {
                            HStack {
                                Image(systemName: "message.fill")
                                Text("Gửi thử thông báo Zalo lên xe")
                                Spacer()
                                Text("\(notificationManager.displayDurationSeconds)s")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            notificationManager.postNotification(
                                appName: "Tin nhắn",
                                sender: "0901234567",
                                message: "Mã OTP của bạn là 8866. Hết hạn trong 5 phút."
                            )
                        }) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text("Gửi thử thông báo SMS lên xe")
                                Spacer()
                                Text("\(notificationManager.displayDurationSeconds)s")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .foregroundColor(.green)
                        }
                        
                        Button(action: {
                            CallNotificationManager.shared.triggerIncomingCall(callerName: "Nguyễn Văn A (0901234567)")
                        }) {
                            HStack {
                                Image(systemName: "phone.fill")
                                Text("Thử nghiệm cuộc gọi đến (Màu xanh)")
                                Spacer()
                                Text("Hiện liên tục")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                Section(header: Text("Hướng dẫn nhận thông báo tự động từ iPhone")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📩 Cách 1: Qua chuẩn Bluetooth ANCS của xe")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Vào Cài đặt iPhone → Bluetooth → chọn tên xe Yamaha → Bật \"Chia sẻ thông báo hệ thống\". Mọi thông báo sẽ được iOS chuyển thẳng lên màn hình xe.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider().background(Color.gray.opacity(0.3))
                        
                        Text("⚡ Cách 2: Qua Phím tắt iOS (Shortcuts Automation)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Tạo Tự động hoá: Khi nhận tin nhắn Zalo/SMS → Mở URL:\nmynmax://notify?app=Zalo&sender=Nam&message=Alo")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.cyan)
                        
                        Divider().background(Color.gray.opacity(0.3))
                        
                        Text("📞 Điều khiển cuộc gọi bằng cùm xe:")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("• Phím (+): Nhận / Trả lời cuộc gọi đến.\n• Phím (-): Từ chối / Kết thúc cuộc gọi.\n• Khi không có cuộc gọi, phím (+) và (-) dùng để phóng to / thu nhỏ bản đồ.")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Thông tin ứng dụng")) {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text("0.5.14 (Build 40)")
                            .foregroundColor(.secondary)
                    }
                    Text("MyNMAX - Dẫn đường và thông báo cho xe máy Yamaha có màn hình TFT.")
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
