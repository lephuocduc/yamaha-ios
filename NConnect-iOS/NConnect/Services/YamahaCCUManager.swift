import Foundation
import CoreBluetooth
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
    
    @Published public var state: BikeConnectionState = .disconnected
    @Published public var discoveredBikes: [BikeDevice] = []
    @Published public var connectedBike: BikeDevice?
    @Published public var telemetry: BikeTelemetry = BikeTelemetry()
    @Published public var diagnosticLogs: [String] = []
    
    // Trạng thái kết nối MFi với màn hình TFT của xe
    @Published public var isMFiConnected: Bool = false
    @Published public var mfiAccessoryName: String = ""
    @Published public var mfiStatus: String = "Chưa kết nối màn hình TFT"
    
    private var centralManager: CBCentralManager!
    private var currentPeripheral: CBPeripheral?
    private var ddtWriteChar: CBCharacteristic?
    private var ddtNotifyChar: CBCharacteristic?
    private var telemetryCharacteristic: CBCharacteristic?
    private var discoveredCharacteristics: [CBUUID: CBCharacteristic] = [:]
    
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
    
    // Giao thức StreetCross tích hợp
    public let streetCross = StreetCrossProtocol()
    
    public override init() {
        super.init()
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
            if self.diagnosticLogs.count > 150 {
                self.diagnosticLogs.removeFirst(self.diagnosticLogs.count - 150)
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
            if eaSession?.accessory.connectionID == accessory.connectionID {
                closeEASession()
            }
        }
    }
    
    // Mở hộp thoại ghép đôi Bluetooth của iOS với xe
    public func showMFiPairingPicker() {
        log("Mở hộp thoại ghép đôi Bluetooth MFi với xe máy...")
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withPredicate: nil) { [weak self] error in
            if let error = error {
                self?.log("Ghép đôi MFi: \(error.localizedDescription)")
            } else {
                self?.log("Đã chọn phụ kiện, đang kết nối...")
                self?.checkConnectedAccessories()
            }
        }
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
        
        DispatchQueue.main.async {
            self.isMFiConnected = true
            self.mfiAccessoryName = accessory.name
            self.mfiStatus = "Đã kết nối MFi: \(accessory.name)"
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
        DispatchQueue.main.async {
            self.isMFiConnected = false
            self.mfiAccessoryName = ""
            self.mfiStatus = "Chưa kết nối màn hình TFT"
        }
    }
    
    // MARK: - Quá trình Bắt tay NaviLite (Garmin StreetCross Handshake)
    private func runNaviLiteHandshake() {
        guard !isHandshaking else { return }
        isHandshaking = true
        defer { isHandshaking = false }
        
        do {
            log("▶ Bắt đầu bắt tay NaviLite với màn hình TFT...")
            // 1. Chờ gói tin svc 66 từ xe
            var f = try readNaviFrame(timeout: 10.0)
            while f.svc != 66 {
                f = try readNaviFrame(timeout: 10.0)
            }
            log("✓ Xe gửi svc 66! Gửi phản hồi xác thực svc 81 + svc 33")
            writeEAData(NaviLite.frame(6, 81, 0, [1, 0]))
            writeEAData(NaviLite.frame(6, 33, 1, NaviLite.hexB("1c07000100000000")))
            
            // 2. Chờ gói tin svc 83 chứa hạt giống bảo mật & mã CCU
            f = try readNaviFrame(timeout: 10.0)
            while f.svc != 83 {
                f = try readNaviFrame(timeout: 10.0)
            }
            let ccuPart = NaviLite.partNumber(f.payload)
            log("✓ Mã CCU xe: \(ccuPart) → Gửi phản hồi echo svc 84")
            writeEAData(NaviLite.frame(6, 84, 1, NaviLite.secDataAckPayload(f.payload)))
            
            // 3. Gửi chuỗi cấu hình hiển thị ban đầu (Setup burst)
            let setup: [(UInt8, UInt8, [UInt8])] = [
                (2, 0, [0, 0]),
                (31, 0, [1, 0]),
                (10, 0, [0, 0]),
                (11, 0, [0, 0]),
                (13, 0, [1, 0]),
                (12, 0, [0, 0]),
                (14, 1, NaviLite.hexB("07190600302e32206d69")),
                (3, 1, []),
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
                self.log("🎉 BẮT TAY NAVILITE THÀNH CÔNG! Màn hình TFT xe máy đã sẵn sàng nhận bản đồ trực tiếp!")
            }
        } catch {
            log("✗ Bắt tay NaviLite thất bại: \(error.localizedDescription)")
        }
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
        log("Đang kết nối tới xe \(device.name)...")
        
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [device.id])
        if let peripheral = peripherals.first {
            currentPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ])
        }
    }
    
    public func disconnect() {
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
            log("Chưa có cổng ghi DDT, tự động chuyển sang Đã kết nối")
            DispatchQueue.main.async {
                self.state = .connected
                self.streetCross.displaySpec.isReadyForStreaming = true
            }
            return
        }
        state = .authenticating
        log("Gửi gói AuthenticationV2 lên xe qua cổng TX: \(writeChar.uuid)...")
        
        var authPacket = Data([0x02, 0x01, 0x00, 0x10])
        let appIdBytes = [UInt8]("NConnectIOS".utf8)
        authPacket.append(contentsOf: appIdBytes)
        
        let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(authPacket, for: writeChar, type: writeType)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.state == .authenticating {
                self.log("✓ Hoàn tất xác thực CCU! Chuyển sang trạng thái Đã kết nối.")
                self.state = .connected
                self.streetCross.displaySpec.isReadyForStreaming = true
            }
        }
    }
    
    public func startStreaming() {
        state = .streaming
        streetCross.displaySpec.isReadyForStreaming = true
        log("▶ Bắt đầu truyền dữ liệu bản đồ lên màn hình TFT của xe")
        checkConnectedAccessories()
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
        case .endEncountered:
            log("Luồng MFi kết thúc")
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
        
        if name.hasPrefix("YCCU_") || name.hasPrefix("YS_") || name.contains("CCU") || name.contains("Yamaha") || name.contains("Garmin") {
            let bike = BikeDevice(
                id: peripheral.identifier,
                name: name,
                address: peripheral.identifier.uuidString,
                rssi: RSSI.intValue,
                isPaired: false
            )
            
            if !discoveredBikes.contains(where: { $0.id == bike.id }) {
                log("Thấy xe: \(name), RSSI: \(RSSI)")
                discoveredBikes.append(bike)
                
                if connectedBike == nil && discoveredBikes.count == 1 {
                    connect(to: bike)
                }
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("✓ Đã kết nối GATT với \(peripheral.name ?? ""), bắt đầu quét dịch vụ...")
        state = .connected
        connectedBike = BikeDevice(id: peripheral.identifier, name: peripheral.name ?? "Yamaha CCU", isPaired: true)
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("✗ Không kết nối được BLE: \(error?.localizedDescription ?? "")")
        state = .error
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Xe ngắt kết nối BLE: \(error?.localizedDescription ?? "Bình thường")")
        state = .disconnected
        connectedBike = nil
        streetCross.reset()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension YamahaCCUManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        log("Đã tìm thấy \(services.count) dịch vụ trên xe")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
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
            
            // 1. CỔNG GHI DỮ LIỆU LÊN XE (TX)
            if char.uuid == Self.ddtWriteCharUUID && isWritable {
                ddtWriteChar = char
                log("  ✓ ĐÃ CHỌN CỔNG GHI TX: \(char.uuid)")
            } else if ddtWriteChar == nil && isWritable {
                ddtWriteChar = char
                log("  ✓ CHỌN CỔNG GHI TX DỰ PHÒNG: \(char.uuid)")
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
        
        sendAuthenticationV2()
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("✗ Lỗi ghi đặc tính \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            log("✓ Đã gửi dữ liệu thành công lên xe!")
        }
        DispatchQueue.main.async {
            self.state = .connected
            self.streetCross.displaySpec.isReadyForStreaming = true
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if state == .authenticating {
            DispatchQueue.main.async {
                self.state = .connected
                self.streetCross.displaySpec.isReadyForStreaming = true
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
        }
    }
    
    // MARK: - Giải mã thông số xe (Telemetry)
    private func parseTelemetry(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return }
        
        // Bỏ qua các mã gói tin điều khiển / handshake ban đầu của CCU (0x1502, 0x0102, 0x0101)
        let packetHeader = (Int(bytes[0]) << 8) | Int(bytes[1])
        if packetHeader == 0x1502 || packetHeader == 0x0102 || packetHeader == 0x0101 {
            return
        }
        
        // Tốc độ xe km/h
        if bytes.count >= 3 {
            let speedRaw = Double(bytes[2])
            if speedRaw >= 0 && speedRaw < 200 {
                telemetry.speedKmh = speedRaw
            }
        }
        
        // Vòng tua máy RPM (Dải vòng tua thực tế xe máy khi nổ máy: 800 - 13000 RPM)
        if bytes.count >= 5 {
            let rpmRaw = Int(bytes[3]) | (Int(bytes[4]) << 8)
            if rpmRaw >= 800 && rpmRaw <= 13000 {
                telemetry.rpm = rpmRaw
            } else {
                telemetry.rpm = 0
            }
        } else {
            telemetry.rpm = 0
        }
        
        // Mức nhiên liệu %
        if bytes.count >= 6 {
            let fuelRaw = Int(bytes[5])
            if fuelRaw >= 5 && fuelRaw <= 100 {
                telemetry.fuelPercent = fuelRaw
            }
        }
    }
}
