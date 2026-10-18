import Foundation
import UIKit
import CoreBluetooth
import CoreLocation
import ExternalAccessory
import Combine

// MARK: - Quản lý kết nối Yamaha CCU (Hỗ trợ cả BLE Telemetry & MFi ExternalAccessory cho màn hình TFT)
public final class YamahaCCUManager: NSObject, ObservableObject {
    
    // UUID Dịch vụ & Đặc tính chuẩn của Yamaha ClusterLink CCU
    public static let clusterLinkServiceUUID = CBUUID(string: "AFA2CDF4-ECCF-46A7-A5EA-9DA428C0157A")
    // Cổng GHI dữ liệu lên xe (TX): B606C7F9...
    public static let ddtWriteCharUUID       = CBUUID(string: "B606C7F9-E5A1-4E75-B313-2A920054A8EB")
    // Cổng NHẬN thông báo từ xe (RX): 75AB2788...
    public static let ddtNotifyCharUUID      = CBUUID(string: "75AB2788-87F6-4F61-BA9C-6F85A12600D1")
    public static let telemetryCharUUID      = CBUUID(string: "9C810D26-B605-4306-8C1C-755A1BA3066C")
    public static let streetCrossServiceUUID = CBUUID(string: "00007220-0000-1000-8000-00805F9B34FB")
    
    // Giao thức MFi External Accessory của Garmin / Yamaha NaviLite
    public static let dashProtocol = "com.garmin.navilite.data"
    public static var shared: YamahaCCUManager?
    
    // MARK: - Nhận diện thiết bị CCU chuẩn xe máy Yamaha & Lọc bỏ Smartwatch/Loa/Tai nghe
    public static func isYamahaBikeCCU(name: String, advertisementData: [String: Any]) -> Bool {
        // 1. Ưu tiên kiểm tra UUID dịch vụ trong gói tin BLE Advertisement
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if serviceUUIDs.contains(clusterLinkServiceUUID) || serviceUUIDs.contains(streetCrossServiceUUID) {
                return true
            }
        }
        
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        
        // 2. DANH SÁCH ĐEN TUYỆT ĐỐI (Loại bỏ triệt để Smartwatch, Tai nghe, Loa, Thiết bị gia dụng)
        let blacklistKeywords = [
            // Smartwatch & Wearables (Garmin, Apple, Samsung, Xiaomi...)
            "watch", "forerunner", "fenix", "epix", "venu", "vivo", "instinct",
            "descent", "approach", "marq", "tactix", "enduro", "smartband", "band",
            "fitbit", "galaxy watch", "apple watch", "wearable",
            // Loa, Âm thanh & Tai nghe (Yamaha soundbar, earbuds, loa gia đình...)
            "soundbar", "speaker", "loa", "earbud", "earphone", "headphone", "headset",
            "airpod", "tai nghe", "receiver", "ampli", "amp", "musiccast",
            "audio", "subwoofer", "sound",
            // Nhạc cụ Yamaha
            "piano", "keyboard", "guitar", "clavinova", "disklavier", "organ",
            // TV gia dụng
            "tv", "tivi", "television", "bravia"
        ]
        
        for bad in blacklistKeywords {
            if lower.contains(bad) {
                return false
            }
        }
        
        // 3. TIỀN TỐ ĐỊNH DANH CHUẨN CỦA CCU XE MÁY YAMAHA
        if lower.hasPrefix("ccu-") || lower.hasPrefix("ccu_") || lower.hasPrefix("ccu") ||
           lower.hasPrefix("yccu_") || lower.hasPrefix("yccu-") || lower.hasPrefix("yccu") ||
           lower.hasPrefix("ys_") || lower.hasPrefix("ys-") ||
           lower.hasPrefix("mynmax") {
            return true
        }
        
        // 4. CÁC TÊN TƯƠNG THÍCH VỚI HỆ THỐNG Y-CONNECT CHÍNH HÃNG
        if lower.contains("y-connect") || lower.contains("yconnect") ||
           lower.contains("yamaha ccu") || lower.contains("yamaha-ccu") || lower.contains("yamaha_ccu") {
            return true
        }
        
        // 5. NẾU TÊN CÓ "YAMAHA", CHỈ CHẤP NHẬN KHI KÈM TÊN XE MÁY HOẶC CỤM ĐỒNG HỒ
        if lower.contains("yamaha") {
            let bikeModelKeywords = [
                "nmax", "nvx", "aerox", "xmax", "tmax", "tracer", "mt-", "mt0",
                "r15", "r3", "r7", "r1", "fazzio", "filano", "pg-1", "lexi",
                "ccu", "cluster", "meter", "dash", "moto", "bike", "tft"
            ]
            for model in bikeModelKeywords {
                if lower.contains(model) {
                    return true
                }
            }
            return false
        }
        
        // 6. NẾU TÊN CÓ "GARMIN", CHỈ CHẤP NHẬN KHI LÀ MÀN HÌNH ĐỒNG HỒ XE (STREETCROSS / NAVILITE)
        if lower.contains("garmin") {
            let bikeClusterKeywords = ["streetcross", "navilite", "cluster", "meter", "dash", "tft", "yamaha"]
            for kw in bikeClusterKeywords {
                if lower.contains(kw) {
                    return true
                }
            }
            return false
        }
        
        return false
    }
    
    @Published public var state: BikeConnectionState = .disconnected
    @Published public var discoveredBikes: [BikeDevice] = []
    @Published public var connectedBike: BikeDevice?
    @Published public var telemetry: BikeTelemetry = BikeTelemetry()
    @Published public var diagnosticLogs: [String] = []
    
    @Published public var isMFiConnected: Bool = false
    @Published public var mfiAccessoryName: String = ""
    @Published public var mfiStatus: String = "Chưa kết nối màn hình TFT"
    @Published public var currentRoadNameOnTFT: String = "MyNMAX"
    @Published public var phoneBatteryLevel: Int = 100
    @Published public var isPhoneCharging: Bool = false
    public var lastSentRoadName: String = ""
    
    // Callbacks xử lý nút bấm từ cùm tay lái xe (+ / - / Zoom / Hủy dẫn đường / Menu)
    public var onZoomIn: (() -> Void)?
    public var onZoomOut: (() -> Void)?
    public var onStopRoute: (() -> Void)?
    public var onGoHome: (() -> Void)?
    public var onGoToWork: (() -> Void)?
    public var onFindGasStation: (() -> Void)?
    public var onOpenFavorites: (() -> Void)?
    public var onSelectPoi: ((Int, Int) -> Void)?
    
    // Lưu trữ danh sách POI gần nhất đã gửi lên xe (Mã 3 = Favorites, Mã 4 = Gas stations)
    public var lastSentFavorites: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    public var lastSentGasStations: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    
    private var centralManager: CBCentralManager!
    private var currentPeripheral: CBPeripheral?
    private var ddtWriteChar: CBCharacteristic?
    private var ddtNotifyChar: CBCharacteristic?
    private var telemetryCharacteristic: CBCharacteristic?
    private var discoveredCharacteristics: [CBUUID: CBCharacteristic] = [:]
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    
    // Quản lý kênh MFi External Accessory
    private var eaSession: EASession?
    private var eaInput: InputStream?
    private var eaOutput: OutputStream?
    private weak var eaStreamThread: Thread?
    private let eaCond = NSCondition()
    private var eaInBuf = Data()
    private let eaOutLock = NSLock()
    private var eaOutQueue = Data()
    private var naviSeq: UInt16 = 1
    private var isHandshaking: Bool = false
    private var wasConnectedToBike: Bool = false
    
    // Giao thức StreetCross tích hợp
    public let streetCross = StreetCrossProtocol()
    
    public override init() {
        super.init()
        Self.shared = self
        streetCross.onHandlebarButtonReceived = { [weak self] btn in
            switch btn {
            case .zoomIn:
                DispatchQueue.main.async { self?.onZoomIn?() }
            case .zoomOut:
                DispatchQueue.main.async { self?.onZoomOut?() }
            case .stopRoute:
                DispatchQueue.main.async { self?.onStopRoute?() }
            case .goHome:
                DispatchQueue.main.async { self?.onGoHome?() }
            case .goToWork:
                DispatchQueue.main.async { self?.onGoToWork?() }
            case .openGasStations:
                DispatchQueue.main.async { self?.onFindGasStation?() }
            case .openFavorites:
                DispatchQueue.main.async { self?.onOpenFavorites?() }
            case .selectPoiItem(let index, let listId):
                DispatchQueue.main.async { self?.onSelectPoi?(index, listId) }
            default:
                break
            }
        }
        centralManager = CBCentralManager(delegate: self, queue: .main)
        setupExternalAccessory()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        closeEASession()
    }
    
    public func log(_ msg: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(msg)"
        print(line)
        DispatchQueue.main.async {
            self.diagnosticLogs.append(line)
            if self.diagnosticLogs.count > 500 {
                self.diagnosticLogs.removeFirst(self.diagnosticLogs.count - 500)
            }
        }
    }
    
    // MARK: - Quản lý Apple External Accessory (MFi Garmin TFT)
    private func setupExternalAccessory() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryConnected(_:)),
            name: .EAAccessoryDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDisconnected(_:)),
            name: .EAAccessoryDidDisconnect,
            object: nil
        )
        EAAccessoryManager.shared().registerForLocalNotifications()
        
        // Kiểm tra phụ kiện xe đã kết nối sẵn
        checkConnectedAccessories()
    }
    
    public func checkConnectedAccessories() {
        let accessories = EAAccessoryManager.shared().connectedAccessories
        log("Tìm thấy \(accessories.count) phụ kiện MFi trên iPhone")
        for acc in accessories {
            log(" • \(acc.name) (protocols: \(acc.protocolStrings))")
            if acc.protocolStrings.contains(Self.dashProtocol) {
                connectExternalAccessory(acc)
                return
            }
        }
    }
    
    @objc private func accessoryConnected(_ notification: Notification) {
        if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
            log("Phụ kiện MFi vừa kết nối: \(accessory.name)")
            if accessory.protocolStrings.contains(Self.dashProtocol) {
                connectExternalAccessory(accessory)
            }
        }
    }
    
    @objc private func accessoryDisconnected(_ notification: Notification) {
        if let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory {
            log("Phụ kiện MFi ngắt kết nối: \(accessory.name)")
            if eaSession?.accessory?.connectionID == accessory.connectionID {
                triggerParkingSaveIfAppropriate()
                closeEASession()
            }
        }
    }
    
    // Mở hộp thoại ghép đôi Bluetooth của iOS với xe
    public func showMFiPairingPicker() {
        log("Mở hộp thoại ghép đôi Bluetooth MFi với xe máy...")
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil, completion: { [weak self] (error: Error?) in
            if let error = error {
                self?.log("Ghép đôi MFi: \(error.localizedDescription)")
            } else {
                self?.log("Đã chọn phụ kiện, đang kết nối...")
                self?.checkConnectedAccessories()
            }
        })
    }
    
    private func connectExternalAccessory(_ accessory: EAAccessory) {
        guard eaSession == nil else { return }
        log("Đang mở EASession với màn hình TFT: \(accessory.name)...")
        
        guard let session = EASession(accessory: accessory, forProtocol: Self.dashProtocol) else {
            log("✗ Không thể tạo EASession (Màn hình xe từ chối giao thức \(Self.dashProtocol))")
            return
        }
        
        eaSession = session
        eaInput = session.inputStream
        eaOutput = session.outputStream
        isMFiConnected = true
        
        DispatchQueue.main.async {
            self.isMFiConnected = true
            self.mfiAccessoryName = accessory.name
            self.mfiStatus = "Đã kết nối MFi: \(accessory.name)"
            self.state = .streaming
            self.streetCross.displaySpec.isReadyForStreaming = true
            self.onBikeConnectedSuccessfully()
        }
        
        // Khởi chạy luồng I/O ngầm
        let thread = Thread { [weak self] in
            guard let self = self, let inp = self.eaInput, let outp = self.eaOutput else { return }
            inp.delegate = self
            outp.delegate = self
            inp.schedule(in: .current, forMode: .default)
            outp.schedule(in: .current, forMode: .default)
            inp.open()
            outp.open()
            RunLoop.current.run()
        }
        thread.name = "nconnect-ea-io"
        thread.start()
        eaStreamThread = thread
        
        // Bắt đầu quá trình bắt tay NaviLite
        Thread.detachNewThread { [weak self] in
            self?.runNaviLiteHandshake()
        }
    }
    
    private func closeEASession() {
        eaInput?.close()
        eaOutput?.close()
        eaSession = nil
        eaStreamThread = nil
        eaInBuf.removeAll()
        eaOutLock.lock()
        eaOutQueue.removeAll()
        eaOutLock.unlock()
        eaCond.lock()
        eaCond.broadcast()
        eaCond.unlock()
        DispatchQueue.main.async {
            self.isMFiConnected = false
            self.mfiAccessoryName = ""
            self.mfiStatus = "Chưa kết nối màn hình TFT"
            if self.state == .streaming {
                self.state = self.connectedBike != nil ? .connected : .disconnected
            }
        }
    }
    
    // MARK: - Quá trình Lắng nghe & Bắt tay NaviLite liên tục (Garmin StreetCross Service Dispatcher)
    private func runNaviLiteHandshake() {
        guard !isHandshaking else { return }
        isHandshaking = true
        defer { isHandshaking = false }
        
        log("▶ Khởi động bộ nhận lệnh NaviLite liên tục với màn hình TFT...")
        
        while eaSession != nil && eaInput != nil {
            do {
                // Đọc frame tiếp theo từ xe, timeout 5s để định kỳ kiểm tra kết nối MFi
                let f = try readNaviFrame(timeout: 5.0)
                // Lọc bỏ log định kỳ của các gói tin tần số cao (Heartbeat svc 80, Poll svc 65) để tránh tràn 500 dòng log chẩn đoán
                if f.svc != 65 && f.svc != 80 {
                    log("[NaviLite] ← Xe gửi svc \(f.svc) (\(f.payload.count)B)")
                }
                
                switch f.svc {
                case 80:
                    // Heartbeat & Frame ACK định kỳ từ đồng hồ xe (chứa 16-bit sequence counter: 1C 00, 1D 00...)
                    // Báo hiệu màn hình TFT vẫn đang nhận và vẽ các khung hình bản đồ trơn tru
                    break
                    
                case 65:
                    // Gói tin Idle Poll định kỳ từ xe (data: 00 00 00)
                    break
                    
                case 66:
                    log("✓ Xe gửi svc 66! Gửi phản hồi xác thực svc 81 + svc 33")
                    writeEAData(NaviLite.frame(6, 81, 0, [1, 0]))
                    writeEAData(NaviLite.frame(6, 33, 1, NaviLite.hexB("1c07000100000000")))
                    
                case 83:
                    let ccuPart = NaviLite.partNumber(f.payload)
                    log("✓ Mã CCU xe: \(ccuPart) → Gửi phản hồi echo svc 84 + setup burst")
                    writeEAData(NaviLite.frame(6, 84, 1, NaviLite.secDataAckPayload(f.payload)))
                    
                    // Setup burst cấu hình hiển thị ban đầu chuẩn Garmin StreetCross (Service 3, 4, 14 & Service 2)
                    let currentRoad = (!self.lastSentRoadName.isEmpty && self.lastSentRoadName != "MyNMAX") ? self.lastSentRoadName : "YAMAHA"
                    let roadBytes = [UInt8](currentRoad.prefix(64).utf8)
                    let roadPayload: [UInt8] = [0x07, 0x1A, UInt8(roadBytes.count & 0xff), 0x00] + roadBytes
                    
                    // Gói tin Service 4 nạp tên đường footer ban đầu (icon 1 = mũi tên thẳng)
                    let s4Init: [UInt8] = [1, 0, 0, 0, 0, 1, UInt8(roadBytes.count), 0x6D] + roadBytes
                    
                    let hasHome = (SavedPlacesManager.shared.homePlace != nil) || (UserDefaults.standard.data(forKey: "nconnect_home_location") != nil)
                    let hasWork = (SavedPlacesManager.shared.workPlace != nil) || (UserDefaults.standard.data(forKey: "nconnect_work_location") != nil)
                    let setup: [(UInt8, UInt8, [UInt8])] = [
                        (2, 0, [1, 0]),
                        (31, 0, [1, 0]),
                        (10, 0, [hasHome ? 1 : 0, 0]),  // Service 10: Trạng thái bật/tắt nút 'Go home'
                        (11, 0, [hasWork ? 1 : 0, 0]),  // Service 11: Trạng thái bật/tắt nút 'Go to work'
                        (13, 0, [1, 0]),
                        (12, 0, [0, 0]),
                        (3, 1, roadBytes),       // Service 3: Gửi trực tiếp chuỗi tên đường (Chuẩn Lo3/c;->f)
                        (4, 1, s4Init),          // Service 4: Turn-by-Turn footer
                        (1, 3, roadBytes),
                        (1, 14, roadPayload),
                        (14, 1, roadPayload),    // Service 14: Lệnh Sub 0x1A (Chuẩn Lo3/c;->j)
                        (17, 1, NaviLite.hexB("00000000036d7068")),
                        (13, 0, [1, 0]),
                        (12, 0, [1, 0])
                    ]
                    for (s, p, pl) in setup {
                        writeEAData(NaviLite.frame(6, s, p, pl))
                    }
                    
                    DispatchQueue.main.async {
                        self.state = .streaming
                        self.streetCross.displaySpec.isReadyForStreaming = true
                        self.onBikeConnectedSuccessfully()
                        self.log("🎉 BẮT TAY NAVILITE THÀNH CÔNG! Màn hình TFT đã sẵn sàng nhận hình ảnh bản đồ!")
                    }
                    
                case 56:
                    log("Menu xe: Tạm dừng nhận hình (56) → Trả 20")
                    writeEAData(NaviLite.frame(6, 20, 0, [0, 0]))
                    
                case 51, 57:
                    log("Phím cùm xe: Phóng to (+) / Zoom In (mã svc \(f.svc))")
                    // Phản hồi ACK ngay cho xe để xe mở khóa sự kiện phím tiếp theo (chuẩn Lo3/c;->j(""))
                    writeEAData(NaviLite.frame(6, 14, 1, [0x07, 0x1A, 0x00, 0x00]))
                    DispatchQueue.main.async {
                        self.onZoomIn?()
                    }
                    
                case 52, 58:
                    log("Phím cùm xe: Thu nhỏ (-) / Zoom Out (mã svc \(f.svc))")
                    // Phản hồi ACK ngay cho xe để xe mở khóa sự kiện phím tiếp theo (chuẩn Lo3/c;->j(""))
                    writeEAData(NaviLite.frame(6, 14, 1, [0x07, 0x1A, 0x00, 0x00]))
                    DispatchQueue.main.async {
                        self.onZoomOut?()
                    }
                    
                case 53:
                    log("Menu đồng hồ xe: Lệnh 53 (Về nhà / Go home)")
                    writeEAData(NaviLite.frame(6, 14, 1, [0x07, 0x1A, 0x00, 0x00]))
                    DispatchQueue.main.async {
                        self.onGoHome?()
                    }
                    
                case 54:
                    log("Menu đồng hồ xe: Lệnh 54 (Đi làm / Go to work)")
                    writeEAData(NaviLite.frame(6, 14, 1, [0x07, 0x1A, 0x00, 0x00]))
                    DispatchQueue.main.async {
                        self.onGoToWork?()
                    }
                    
                case 49:
                    log("Phím cùm xe: Dừng lộ trình dẫn đường (49)")
                    writeEAData(NaviLite.frame(6, 14, 1, [0x07, 0x1A, 0x00, 0x00]))
                    DispatchQueue.main.async {
                        self.onStopRoute?()
                    }
                    
                case 55:
                    let sub = f.payload.count > 0 ? f.payload[0] : 1
                    if sub == 3 {
                        log("Menu đồng hồ xe: Mở danh sách Yêu thích (55, sub 3)")
                        DispatchQueue.main.async {
                            self.onOpenFavorites?()
                        }
                    } else if sub == 4 {
                        log("Menu đồng hồ xe: Mở danh sách Trạm xăng (55, sub 4)")
                        DispatchQueue.main.async {
                            self.onFindGasStation?()
                        }
                    } else {
                        log("Màn hình xe: Tiếp tục nhận hình ảnh bản đồ (55, sub \(sub))")
                        DispatchQueue.main.async {
                            self.state = .streaming
                            self.streetCross.displaySpec.isReadyForStreaming = true
                        }
                    }
                    
                case 48:
                    let itemIndex = f.payload.count > 0 ? Int(f.payload[0]) : 0
                    let listId = f.payload.count > 1 ? Int(f.payload[1]) : 0
                    log("Menu đồng hồ xe: Chọn mục \(itemIndex) của danh sách \(listId) (48)")
                    DispatchQueue.main.async {
                        self.onSelectPoi?(itemIndex, listId)
                    }
                    
                default:
                    if f.svc != 0x06 {
                        log("[NaviLite] Phím xe/Lệnh: svc \(f.svc) (data: \(f.payload.prefix(6).map { String(format: "%02X", $0) }.joined(separator: " ")))")
                    }
                    break
                }
            } catch {
                // Hết thời gian chờ nhận gói tin trong chu kỳ 5s, tiếp tục lắng nghe nếu còn kết nối
                continue
            }
        }
        log("Dừng luồng lắng nghe NaviLite do phiên MFi kết thúc.")
    }
    
    // Đọc frame NaviLite từ buffer nhận
    private func readNaviBytes(_ n: Int, timeout: TimeInterval) throws -> [UInt8] {
        eaCond.lock()
        defer { eaCond.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while eaInBuf.count < n {
            if !eaCond.wait(until: deadline) {
                throw NSError(domain: "NaviLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hết thời gian chờ nhận dữ liệu từ xe"])
            }
        }
        let out = [UInt8](eaInBuf.prefix(n))
        eaInBuf.removeFirst(n)
        return out
    }
    
    private func readNaviFrame(timeout: TimeInterval) throws -> NaviFrame {
        var h = try readNaviBytes(16, timeout: timeout)
        while !(h[0] == 0x6e && h[1] == 0x41 && h[2] == 0x6c && h[3] == 0x40) {
            let b = try readNaviBytes(1, timeout: timeout)
            h.removeFirst()
            h.append(b[0])
        }
        let size = Int(h[7]) | (Int(h[8]) << 8) | (Int(h[9]) << 16) | (Int(h[10]) << 24)
        let payload = size > 0 ? try readNaviBytes(size, timeout: timeout) : []
        return NaviFrame(svc: Int(h[6]), payload: payload)
    }
    
    // Ghi dữ liệu ra OutputStream của MFi Accessory
    public func writeEAData(_ data: Data) {
        eaOutLock.lock()
        eaOutQueue.append(data)
        eaOutLock.unlock()
        if let t = eaStreamThread {
            perform(#selector(flushEAOutput), on: t, with: nil, waitUntilDone: false)
        }
    }
    
    @objc private func flushEAOutput() {
        guard let out = eaOutput else { return }
        eaOutLock.lock()
        while !eaOutQueue.isEmpty && out.hasSpaceAvailable {
            let n = eaOutQueue.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> Int in
                out.write(p.bindMemory(to: UInt8.self).baseAddress!, maxLength: eaOutQueue.count)
            }
            if n > 0 {
                eaOutQueue.removeFirst(n)
            } else {
                break
            }
        }
        eaOutLock.unlock()
    }
    
    // MARK: - Bắt đầu quét tìm xe qua BLE
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            log("Bluetooth chưa sẵn sàng (\(centralManager.state.rawValue))")
            return
        }
        state = .scanning
        discoveredBikes.removeAll()
        discoveredPeripherals.removeAll()
        log("Bắt đầu quét BLE tìm xe Yamaha...")
        
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        checkConnectedAccessories()
    }
    
    public func stopScanning() {
        centralManager.stopScan()
        if state == .scanning {
            state = .disconnected
        }
    }
    
    // MARK: - Kết nối tới xe đã chọn qua BLE
    public func connect(to device: BikeDevice) {
        stopScanning()
        state = .connecting
        connectedBike = device
        log("Đang kết nối tới xe \(device.name)...")
        
        let peripheral = discoveredPeripherals[device.id] ?? centralManager.retrievePeripherals(withIdentifiers: [device.id]).first
        if let peripheral = peripheral {
            currentPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ])
        } else {
            log("✗ Không tìm thấy thiết bị \(device.name) trong bộ nhớ, tiếp tục quét...")
            connectedBike = nil
            state = .disconnected
            startScanning()
        }
    }
    
    public func cancelPeripheralAndResumeScan(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
        currentPeripheral = nil
        connectedBike = nil
        state = .disconnected
        discoveredCharacteristics.removeAll()
        ddtWriteChar = nil
        ddtNotifyChar = nil
        telemetryCharacteristic = nil
        streetCross.reset()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, self.currentPeripheral == nil else { return }
            self.startScanning()
        }
    }
    
    public func disconnect() {
        triggerParkingSaveIfAppropriate()
        if let peripheral = currentPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        currentPeripheral = nil
        connectedBike = nil
        state = .disconnected
        streetCross.reset()
        discoveredCharacteristics.removeAll()
        ddtWriteChar = nil
        ddtNotifyChar = nil
        telemetryCharacteristic = nil
        closeEASession()
        log("Đã ngắt kết nối với xe")
    }
    
    // MARK: - Gửi gói tin AuthenticationV2 qua kênh ghi DDT (TX)
    private func sendAuthenticationV2() {
        guard let peripheral = currentPeripheral, let writeChar = ddtWriteChar else {
            log("✗ Không có cổng ghi DDT trên thiết bị, ngắt kết nối.")
            if let p = currentPeripheral {
                cancelPeripheralAndResumeScan(p)
            }
            return
        }
        guard state != .authenticating && state != .connected && state != .streaming else { return }
        state = .authenticating
        log("Gửi gói AuthenticationV2 lên xe qua cổng TX: \(writeChar.uuid)...")
        
        var authPacket = Data([0x02, 0x01, 0x00, 0x10])
        let appIdBytes = [UInt8]("NConnectIOS".utf8)
        authPacket.append(contentsOf: appIdBytes)
        
        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(authPacket, for: writeChar, type: writeType)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            if self.state == .authenticating && self.currentPeripheral != nil && self.ddtWriteChar != nil {
                self.log("✓ Hoàn tất xác thực CCU! Chuyển sang trạng thái Đã kết nối.")
                self.state = .connected
                self.streetCross.displaySpec.isReadyForStreaming = true
                self.onBikeConnectedSuccessfully()
            }
        }
    }
    
    public func startStreaming() {
        state = .streaming
        streetCross.displaySpec.isReadyForStreaming = true
        log("▶ Bắt đầu truyền dữ liệu bản đồ lên màn hình TFT của xe")
        checkConnectedAccessories()
        if isMFiConnected && !isHandshaking {
            Thread.detachNewThread { [weak self] in
                self?.runNaviLiteHandshake()
            }
        }
    }
    
    // MARK: - Cập nhật tên con đường xe đang chạy + ETA lên thanh footer của màn hình xe (Chuẩn Garmin svc 2, svc 3, svc 4 & svc 14)
    public func updateCurrentRoadNameOnTFT(_ rawRoadName: String, distanceMeters: Double = 0.0, maneuverIcon: UInt8 = 0, etaText: String = "") {
        var cleanRoad = cleanVietnameseForGarmin(rawRoadName).uppercased()
        if cleanRoad.isEmpty {
            cleanRoad = "YAMAHA"
        }
        
        var fullFooter = cleanRoad
        if !etaText.isEmpty && !cleanRoad.contains(" - ") {
            let cleanEta = cleanVietnameseForGarmin(etaText).uppercased()
            if !cleanEta.isEmpty {
                fullFooter = "\(cleanRoad) - \(cleanEta)"
            }
        }
        lastSentRoadName = fullFooter
        
        DispatchQueue.main.async {
            self.currentRoadNameOnTFT = fullFooter
        }
        
        guard isMFiConnected && eaOutput != nil else { return }
        
        let roadBytes = [UInt8](fullFooter.prefix(128).utf8)
        
        // 1. GỬI SERVICE 2 (PDT 0): Kích hoạt chế độ dẫn đường trên đồng hồ xe (Active Navigation Mode: [1, 0])
        writeEAData(NaviLite.frame(6, 2, 0, [1, 0]))
        
        // 2. GỬI SERVICE 3 (PDT 1): Chuẩn APK Lo3/c;->f - Gửi trực tiếp chuỗi tên đường để nạp đè chữ 'Road' trong ROM xe
        writeEAData(NaviLite.frame(6, 3, 1, roadBytes))
        
        // 3. GỬI SERVICE 4 (PDT 1): Chuẩn APK Lm3/r;->l (Mũi tên chỉ hướng + Khoảng cách + Đơn vị + Tên đường)
        var unitStr = "m"
        var distVal = Float(distanceMeters)
        if distanceMeters >= 1000.0 {
            unitStr = "km"
            distVal = Float(distanceMeters / 1000.0)
        }
        let unitBytes = [UInt8](unitStr.utf8)
        
        var s4 = [UInt8]()
        // Mũi tên: nếu icon = 0 (đi thẳng/chạy tự do), gán icon = 1 (mũi tên đi thẳng chuẩn StreetCross)
        let iconByte = maneuverIcon == 0 ? 1 : maneuverIcon
        s4.append(iconByte)
        var floatLE = distVal.bitPattern.littleEndian
        withUnsafeBytes(of: floatLE) { s4.append(contentsOf: $0) }
        s4.append(UInt8(unitBytes.count))
        s4.append(UInt8(roadBytes.count))
        s4.append(contentsOf: unitBytes)
        s4.append(contentsOf: roadBytes)
        
        writeEAData(NaviLite.frame(6, 4, 1, s4))
        
        // 4. GỬI SERVICE 14 (PDT 1): Chuẩn APK Lo3/c;->j (Lệnh 0x1A hiển thị tên đường trực tiếp lên thanh footer xe)
        let roadPayload: [UInt8] = [0x07, 0x1A, UInt8(roadBytes.count & 0xff), 0x00] + roadBytes
        writeEAData(NaviLite.frame(6, 14, 1, roadPayload))
        
        // 5. GỬI SERVICE 2 (PDT 1): Giờ dự kiến đến / thời gian trong ngày (chuẩn APK Lm3/r;->l line 664)
        let calendar = Calendar.current
        let now = Date()
        let currentMinuteOfDay = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let etaMin = UInt16(min(1439, currentMinuteOfDay))
        let arrivePayload: [UInt8] = [0x03, UInt8(etaMin & 0xff), UInt8((etaMin >> 8) & 0xff), 0x00]
        writeEAData(NaviLite.frame(6, 2, 1, arrivePayload))
    }
    
    // MARK: - Tắt chế độ dẫn đường trên đồng hồ xe khi dừng hoặc tới đích (chuẩn APK Lo3/c;->b([0, 0], 2, 0))
    public func stopNavigationOnTFT() {
        guard isMFiConnected && eaOutput != nil else { return }
        log("Đồng hồ xe: Tắt khung dẫn đường (Service 2 = [0, 0])")
        writeEAData(NaviLite.frame(6, 2, 0, [0, 0]))
        lastSentRoadName = ""
        DispatchQueue.main.async {
            self.currentRoadNameOnTFT = ""
        }
    }
    
    // MARK: - Cập nhật trạng thái Menu xe (Nhà / Nơi làm việc) qua Service 10 & 11
    public func updateMenuCapabilities(hasHome: Bool, hasWork: Bool) {
        guard isMFiConnected && eaOutput != nil else { return }
        log("Cập nhật trạng thái Menu xe: Nhà = \(hasHome ? "Bật" : "Tắt"), Chỗ làm = \(hasWork ? "Bật" : "Tắt")")
        writeEAData(NaviLite.frame(6, 10, 0, [hasHome ? 1 : 0, 0]))
        writeEAData(NaviLite.frame(6, 11, 0, [hasWork ? 1 : 0, 0]))
    }
    
    // MARK: - Gửi danh sách POI (Yêu thích / Trạm xăng) lên menu màn hình TFT xe máy (Chuẩn Garmin StreetCross Service 7/8 & 98/99)
    public func sendPoiListToTFT(listId: Int, items: [(name: String, coordinate: CLLocationCoordinate2D)], currentLoc: CLLocationCoordinate2D?) {
        guard isMFiConnected && eaOutput != nil else {
            if listId == 3 {
                self.lastSentFavorites = items
            } else {
                self.lastSentGasStations = items
            }
            return
        }
        
        let maxItems = min(items.count, 20)
        let headerService: UInt8 = (listId == 3) ? 7 : 8
        let itemService: UInt8 = (listId == 3) ? 98 : 99
        
        if listId == 3 {
            self.lastSentFavorites = Array(items.prefix(maxItems))
        } else {
            self.lastSentGasStations = Array(items.prefix(maxItems))
        }
        
        // 1. Gửi gói tin Header khai báo số lượng mục: [count_low, count_high, 0]
        let countPayload: [UInt8] = [UInt8(maxItems & 0xff), UInt8((maxItems >> 8) & 0xff), 0]
        writeEAData(NaviLite.frame(6, headerService, 1, countPayload))
        log("Gửi Header danh sách \(listId == 3 ? "Yêu thích" : "Trạm xăng") (svc \(headerService)): \(maxItems) mục")
        
        guard maxItems > 0 else { return }
        
        let userLoc = currentLoc != nil ? CLLocation(latitude: currentLoc!.latitude, longitude: currentLoc!.longitude) : nil
        
        // 2. Gửi từng mục POI (Service 98 / 99)
        for i in 0..<maxItems {
            let item = items[i]
            let itemLoc = CLLocation(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
            
            let distMeters: Double = userLoc != nil ? userLoc!.distance(from: itemLoc) : 0.0
            let distStr: String
            if distMeters < 1000 {
                distStr = "\(Int(round(distMeters))) m"
            } else {
                distStr = String(format: "%.1f km", distMeters / 1000.0)
            }
            
            var bearingInt: Int = 0
            if let u = currentLoc {
                let lat1 = u.latitude * .pi / 180.0
                let lon1 = u.longitude * .pi / 180.0
                let lat2 = item.coordinate.latitude * .pi / 180.0
                let lon2 = item.coordinate.longitude * .pi / 180.0
                let dLon = lon2 - lon1
                let y = sin(dLon) * cos(lat2)
                let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
                var deg = atan2(y, x) * 180.0 / .pi
                if deg < 0 { deg += 360.0 }
                bearingInt = Int(round(deg)) % 360
            }
            
            let cleanName = cleanVietnameseForGarmin(item.name).uppercased()
            let cleanDist = distStr
            
            guard let nameData = cleanName.data(using: .utf8),
                  let distData = cleanDist.data(using: .utf8) else { continue }
            
            var p = Data()
            p.append(UInt8(i & 0xff))
            p.append(UInt8((i >> 8) & 0xff))
            p.append(UInt8(bearingInt & 0xff))
            p.append(UInt8((bearingInt >> 8) & 0xff))
            p.append(UInt8(1)) // icon/type
            p.append(UInt8(min(nameData.count, 144)))
            p.append(UInt8(min(distData.count, 144)))
            
            let floatDistBits = Float(distMeters).bitPattern
            p.append(UInt8(floatDistBits & 0xff))
            p.append(UInt8((floatDistBits >> 8) & 0xff))
            p.append(UInt8((floatDistBits >> 16) & 0xff))
            p.append(UInt8((floatDistBits >> 24) & 0xff))
            
            p.append(distData.prefix(144))
            p.append(nameData.prefix(144))
            
            writeEAData(NaviLite.frame(6, itemService, 1, [UInt8](p)))
        }
        log("Đã gửi trọn bộ \(maxItems) mục của danh sách \(listId == 3 ? "Yêu thích" : "Trạm xăng") (svc \(itemService)) lên xe")
    }
    
    public func cleanVietnameseForGarmin(_ str: String) -> String {
        var clean = str
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
        
        if clean.hasPrefix("Duong ") {
            clean = String(clean.dropFirst(6))
        } else if clean.hasPrefix("duong ") {
            clean = String(clean.dropFirst(6))
        } else if clean.hasPrefix("Pho ") {
            clean = String(clean.dropFirst(4))
        } else if clean.hasPrefix("Hem ") {
            clean = String(clean.dropFirst(4))
        }
        
        clean = clean.filter { $0.isASCII && $0.asciiValue != nil && $0.asciiValue! >= 32 && $0.asciiValue! <= 126 }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Truyền khung hình JPEG trực tiếp lên màn hình TFT xe
    public func sendLiveMapFrameToTFT(_ jpegData: Data) {
        // 1. ƯU TIÊN KÊNH MFi EXTERNAL ACCESSORY (Chuẩn Garmin StreetCross / NaviLite)
        if isMFiConnected && eaOutput != nil {
            var payload: [UInt8] = [3, UInt8(naviSeq & 0xff), UInt8((naviSeq >> 8) & 0xff)]
            payload.append(contentsOf: [UInt8](jpegData))
            naviSeq &+= 1
            let wirePacket = NaviLite.frame(6, 0, 1, payload)
            writeEAData(wirePacket)
            return
        }
        
        // 2. KÊNH BLE DỰ PHÒNG (Gửi qua DDT TX B606...)
        if let peripheral = currentPeripheral, let writeChar = ddtWriteChar, (state == .streaming || state == .connected) {
            let packets = streetCross.encodeJPEGFrameForTFT(jpegData)
            let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            for packet in packets {
                peripheral.writeValue(packet, for: writeChar, type: writeType)
            }
        }
    }
    
    public func sendFrameDataToTFT(_ packets: [Data]) {
        guard let peripheral = currentPeripheral, let writeChar = ddtWriteChar, (state == .streaming || state == .connected) else { return }
        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for packet in packets {
            peripheral.writeValue(packet, for: writeChar, type: writeType)
        }
    }
}

// MARK: - StreamDelegate cho MFi ExternalAccessory
extension YamahaCCUManager: StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            if let inp = eaInput {
                var buf = [UInt8](repeating: 0, count: 4096)
                let n = inp.read(&buf, maxLength: buf.count)
                if n > 0 {
                    eaCond.lock()
                    eaInBuf.append(contentsOf: buf[0..<n])
                    eaCond.signal()
                    eaCond.unlock()
                }
            }
        case .hasSpaceAvailable:
            flushEAOutput()
        case .errorOccurred:
            log("✗ Lỗi luồng MFi: \(aStream.streamError?.localizedDescription ?? "Không xác định")")
            closeEASession()
        case .endEncountered:
            log("Luồng MFi kết thúc")
            closeEASession()
        default:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension YamahaCCUManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("Bluetooth đã BẬT, sẵn sàng quét xe")
            startScanning()
        case .poweredOff:
            log("Bluetooth đã TẮT")
            state = .error
        case .unauthorized:
            log("Chưa cấp quyền Bluetooth trong Cài đặt iPhone")
            state = .error
        default:
            break
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard !name.isEmpty else { return }
        
        // Lưu tham chiếu peripheral để dùng khi connect
        discoveredPeripherals[peripheral.identifier] = peripheral
        
        // Kiểm tra nghiêm ngặt: Phải đúng là Yamaha CCU hoặc TFT Cluster, loại bỏ hoàn toàn Smartwatch, Loa, Tai nghe
        if Self.isYamahaBikeCCU(name: name, advertisementData: advertisementData) {
            let bike = BikeDevice(
                id: peripheral.identifier,
                name: name,
                address: peripheral.identifier.uuidString,
                rssi: RSSI.intValue,
                isPaired: false
            )
            
            if !discoveredBikes.contains(where: { $0.id == bike.id }) {
                log("Thấy xe Yamaha hợp lệ: \(name), RSSI: \(RSSI)")
                discoveredBikes.append(bike)
                
                // Chỉ tự động kết nối nếu hiện tại chưa kết nối và đang ở trạng thái tìm xe
                if connectedBike == nil && (state == .scanning || state == .disconnected) {
                    connect(to: bike)
                }
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("✓ Đã kết nối tầng liên kết với \(peripheral.name ?? ""), đang xác minh dịch vụ CCU xe...")
        // CHÚ Ý: Giữ trạng thái .connecting, KHÔNG gán .connected cho đến khi xác thực thành công đặc tính CCU!
        state = .connecting
        connectedBike = BikeDevice(id: peripheral.identifier, name: peripheral.name ?? "Yamaha CCU", isPaired: true)
        discoveredCharacteristics.removeAll()
        ddtWriteChar = nil
        ddtNotifyChar = nil
        telemetryCharacteristic = nil
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("✗ Không kết nối được BLE: \(error?.localizedDescription ?? "")")
        state = .error
        currentPeripheral = nil
        connectedBike = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.currentPeripheral == nil else { return }
            self.startScanning()
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Xe ngắt kết nối BLE: \(error?.localizedDescription ?? "Đã tắt khóa xe")")
        triggerParkingSaveIfAppropriate()
        state = .disconnected
        currentPeripheral = nil
        connectedBike = nil
        streetCross.reset()
        discoveredCharacteristics.removeAll()
        ddtWriteChar = nil
        ddtNotifyChar = nil
        telemetryCharacteristic = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, self.currentPeripheral == nil else { return }
            self.startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension YamahaCCUManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, !services.isEmpty else {
            log("✗ Không tìm thấy dịch vụ nào trên \(peripheral.name ?? ""), hủy kết nối.")
            cancelPeripheralAndResumeScan(peripheral)
            return
        }
        log("Đã tìm thấy \(services.count) dịch vụ trên thiết bị \(peripheral.name ?? "")")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        
        // Đặt timeout 4s kiểm tra: nếu sau 4s mà không phát hiện đặc tính CCU nào thì ngắt kết nối
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self, self.currentPeripheral === peripheral else { return }
            if self.state == .connecting && self.ddtWriteChar == nil && self.ddtNotifyChar == nil && self.telemetryCharacteristic == nil {
                self.log("✗ Quá thời gian xác minh đặc tính CCU xe máy. Ngắt kết nối để tránh nhận nhầm.")
                self.cancelPeripheralAndResumeScan(peripheral)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            discoveredCharacteristics[char.uuid] = char
            let isWritable = char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse)
            
            // Đăng ký nhận thông báo từ tất cả đặc tính có notify / indicate
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: char)
            }
            
            // 1. CỔNG GHI DỮ LIỆU LÊN XE (TX) - Chỉ nhận đúng UUID chuẩn Yamaha CCU
            if char.uuid == Self.ddtWriteCharUUID && isWritable {
                ddtWriteChar = char
                log("  ✓ ĐÃ CHỌN CỔNG GHI TX: \(char.uuid)")
            }
            
            // 2. CỔNG NHẬN DỮ LIỆU TỪ XE (RX)
            if char.uuid == Self.ddtNotifyCharUUID {
                ddtNotifyChar = char
                log("  ✓ ĐÃ CHỌN CỔNG NHẬN RX: \(char.uuid)")
            }
            
            // 3. CỔNG THÔNG SỐ XE (TELEMETRY)
            if char.uuid == Self.telemetryCharUUID {
                telemetryCharacteristic = char
                log("  ✓ ĐÃ CHỌN CỔNG TELEMETRY: \(char.uuid)")
            }
        }
        
        // Nếu đã tìm thấy cổng TX CCU thì tiến hành xác thực ngay
        if ddtWriteChar != nil {
            if state != .authenticating && state != .connected && state != .streaming {
                sendAuthenticationV2()
            }
        } else {
            // Kiểm tra xem tất cả dịch vụ đã được quét xong chưa
            let allServicesChecked = peripheral.services?.allSatisfy { $0.characteristics != nil } ?? false
            if allServicesChecked {
                if ddtNotifyChar != nil || telemetryCharacteristic != nil {
                    log("✓ Đã nhận diện CCU xe qua cổng RX/Telemetry!")
                    DispatchQueue.main.async {
                        self.state = .connected
                        self.streetCross.displaySpec.isReadyForStreaming = true
                    }
                } else {
                    log("✗ Thiết bị '\(peripheral.name ?? "")' không có đặc tính CCU Yamaha. Hủy kết nối.")
                    cancelPeripheralAndResumeScan(peripheral)
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("✗ Lỗi ghi đặc tính \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            log("✓ Đã gửi dữ liệu thành công lên xe!")
        }
        if state == .authenticating {
            DispatchQueue.main.async {
                self.state = .connected
                self.streetCross.displaySpec.isReadyForStreaming = true
                self.onBikeConnectedSuccessfully()
                self.log("✓ Đã kết nối và xác thực thành công với xe máy!")
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if state == .authenticating {
            DispatchQueue.main.async {
                self.state = .connected
                self.streetCross.displaySpec.isReadyForStreaming = true
                self.onBikeConnectedSuccessfully()
                self.log("✓ Xe đã phản hồi xác thực! Chuyển sang trạng thái Đã kết nối.")
            }
        }
        
        // Nhận dữ liệu phản hồi từ cổng RX hoặc cổng TX
        if characteristic.uuid == Self.ddtNotifyCharUUID || characteristic.uuid == Self.ddtWriteCharUUID {
            if let response = streetCross.processIncomingData(data) {
                if let writeChar = ddtWriteChar {
                    let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                    peripheral.writeValue(response, for: writeChar, type: writeType)
                }
            }
        } else if characteristic.uuid == Self.telemetryCharUUID {
            parseTelemetry(data)
        } else if characteristic.uuid.uuidString.uppercased().hasPrefix("E974B9A1") {
            // Luồng thông số ECU / Chẩn đoán tốc độ cao từ xe (16B, 109B, 61B liên tục 3 lần/giây)
            // Lọc bỏ để không làm trôi 500 dòng log chẩn đoán quan trọng của người dùng
        } else {
            let hex = data.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
            log("📡 BLE Notify [\(characteristic.uuid.uuidString.prefix(8))]: \(hex) (\(data.count)B)")
        }
    }
    
    // MARK: - Đồng bộ & Stub thông báo
    public func syncPhoneBatteryAndStatusToCluster() {}
    public func sendCallIndicatorToCluster(isActive: Bool) {}
    public func sendMessageIndicatorToCluster(appName: String, sender: String, message: String) {}
    public func clearMessageIndicatorOnCluster() {}
    
    // MARK: - Tự động ghi nhớ vị trí đỗ xe khi tắt máy (Find My Bike) & Theo dõi lộ trình
    private func onBikeConnectedSuccessfully() {
        wasConnectedToBike = true
        let bikeName = connectedBike?.name ?? (!mfiAccessoryName.isEmpty ? mfiAccessoryName : "Yamaha NMAX")
        if let currentCoord = NavigationEngine.shared?.currentLocation?.coordinate {
            TripHistoryManager.shared.startTripSession(at: currentCoord, bikeName: bikeName)
        }
    }
    
    private func triggerParkingSaveIfAppropriate() {
        guard wasConnectedToBike else { return }
        wasConnectedToBike = false
        
        let bikeName = connectedBike?.name ?? (!mfiAccessoryName.isEmpty ? mfiAccessoryName : "Yamaha NMAX")
        let currentCoord = NavigationEngine.shared?.currentLocation?.coordinate
        
        // Kết thúc phiên theo dõi lộ trình:
        // - Nếu quãng đường >= 50m: Tự động lưu vào Lịch sử lộ trình và cập nhật mốc thời gian đỗ xe mới.
        // - Nếu quãng đường < 50m (mở khóa xe rồi tắt nhưng không chạy): Bỏ qua lộ trình và GIỮ NGUYÊN thời gian đỗ xe trước đó!
        if TripHistoryManager.shared.isRecordingSession {
            TripHistoryManager.shared.endTripSession(at: currentCoord)
        } else if let coord = currentCoord {
            ParkingLocationManager.shared.recordParkingLocation(coordinate: coord, bikeName: bikeName, forceNewTimestamp: false)
        }
    }
    
    // MARK: - Bắt tay ECU (Handshake ACK)
    private func parseTelemetry(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return }
        
        // 1. Phản hồi Bắt tay ECU (Handshake ACK) khi xe gửi gói 309 (0x0135: [0x01, 0x35, sub] hoặc [0x35, 0x01, sub])
        if (bytes[0] == 0x01 && bytes[1] == 0x35) || (bytes[0] == 0x35 && bytes[1] == 0x01) {
            let sub = bytes.count > 2 ? bytes[2] : 0x00
            log("🤝 Bắt tay ECU: Xe gửi mã 309 (0x0135, sub=\(sub)) -> Phản hồi mã 310 (0x0136)")
            if let peripheral = currentPeripheral, let writeChar = ddtWriteChar {
                let ackPayload = Data([0x36, 0x01, sub])
                let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                peripheral.writeValue(ackPayload, for: writeChar, type: writeType)
            }
            return
        }
        
        // 2. Tín hiệu tắt khóa xe / ngắt kết nối từ ECU (Command 312 = 0x0138)
        if (bytes[0] == 0x01 && bytes[1] == 0x38) || (bytes[0] == 0x38 && bytes[1] == 0x01) {
            log("🛵 [ECU] Xe phát tín hiệu tắt khóa điện (Command 312: 0x0138)")
            triggerParkingSaveIfAppropriate()
            return
        }
    }
}
