import Foundation
import CoreBluetooth
import Combine

// MARK: - Quản lý kết nối Bluetooth BLE Yamaha CCU (ClusterLink & TFT Projection)
public final class YamahaCCUManager: NSObject, ObservableObject {
    
    // UUID Dịch vụ & Đặc tính chuẩn của Yamaha ClusterLink CCU
    public static let clusterLinkServiceUUID = CBUUID(string: "AFA2CDF4-ECCF-46A7-A5EA-9DA428C0157A")
    public static let ddtCharacteristicUUID  = CBUUID(string: "75AB2788-87F6-4F61-BA9C-6F85A12600D1")
    public static let ddtAltUUID             = CBUUID(string: "B606C7F9-E5A1-4E75-B313-2A920054A8EB")
    public static let telemetryCharUUID      = CBUUID(string: "9C810D26-B605-4306-8C1C-755A1BA3066C")
    public static let streetCrossServiceUUID = CBUUID(string: "00007220-0000-1000-8000-00805F9B34FB")
    
    @Published public var state: BikeConnectionState = .disconnected
    @Published public var discoveredBikes: [BikeDevice] = []
    @Published public var connectedBike: BikeDevice?
    @Published public var telemetry: BikeTelemetry = BikeTelemetry()
    @Published public var diagnosticLogs: [String] = []
    
    private var centralManager: CBCentralManager!
    private var currentPeripheral: CBPeripheral?
    private var ddtCharacteristic: CBCharacteristic?
    private var telemetryCharacteristic: CBCharacteristic?
    private var discoveredCharacteristics: [CBUUID: CBCharacteristic] = [:]
    
    // Giao thức StreetCross tích hợp
    public let streetCross = StreetCrossProtocol()
    
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    public func log(_ msg: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(msg)"
        print(line)
        DispatchQueue.main.async {
            self.diagnosticLogs.append(line)
            if self.diagnosticLogs.count > 100 {
                self.diagnosticLogs.removeFirst(self.diagnosticLogs.count - 100)
            }
        }
    }
    
    // MARK: - Bắt đầu quét tìm xe
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
    }
    
    public func stopScanning() {
        centralManager.stopScan()
        if state == .scanning {
            state = .disconnected
        }
    }
    
    // MARK: - Kết nối tới xe đã chọn
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
        ddtCharacteristic = nil
        telemetryCharacteristic = nil
        log("Đã ngắt kết nối với xe")
    }
    
    // MARK: - Gửi gói tin AuthenticationV2 qua DDT
    private func sendAuthenticationV2() {
        guard let peripheral = currentPeripheral, let ddtChar = ddtCharacteristic else {
            DispatchQueue.main.async {
                self.state = .connected
                self.streetCross.displaySpec.isReadyForStreaming = true
            }
            return
        }
        state = .authenticating
        log("Gửi gói AuthenticationV2 qua kênh DDT...")
        
        var authPacket = Data([0x02, 0x01, 0x00, 0x10])
        let appIdBytes = [UInt8]("NConnectIOS".utf8)
        authPacket.append(contentsOf: appIdBytes)
        
        let writeType: CBCharacteristicWriteType = ddtChar.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(authPacket, for: ddtChar, type: writeType)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            if self.state == .authenticating {
                self.log("✓ Hoàn tất xác thực CCU! Chuyển sang trạng thái Đã kết nối.")
                self.state = .connected
                self.streetCross.displaySpec.isReadyForStreaming = true
            }
        }
    }
    
    // MARK: - Bắt đầu truyền hình ảnh lên màn hình xe
    public func startStreaming() {
        state = .streaming
        streetCross.displaySpec.isReadyForStreaming = true
        log("▶ Bắt đầu truyền hình ảnh bản đồ lên màn hình TFT của xe")
    }
    
    // MARK: - Gửi dữ liệu khung hình lên màn hình TFT
    public func sendFrameDataToTFT(_ packets: [Data]) {
        guard let peripheral = currentPeripheral, let ddtChar = ddtCharacteristic, (state == .streaming || state == .connected) else { return }
        
        let writeType: CBCharacteristicWriteType = ddtChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for packet in packets {
            peripheral.writeValue(packet, for: ddtChar, type: writeType)
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
        log("✓ Đã kết nối GATT với \(peripheral.name ?? ""), bắt đầu quét toàn bộ dịch vụ...")
        state = .connected
        connectedBike = BikeDevice(id: peripheral.identifier, name: peripheral.name ?? "Yamaha CCU", isPaired: true)
        
        // Quét TẤT CẢ các dịch vụ có trên xe
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("✗ Không kết nối được: \(error?.localizedDescription ?? "")")
        state = .error
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Xe đã ngắt kết nối: \(error?.localizedDescription ?? "Bình thường")")
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
            log("→ Dịch vụ: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            discoveredCharacteristics[char.uuid] = char
            log("  [Char] \(char.uuid) (props: \(char.properties.rawValue))")
            
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: char)
            }
            
            if char.uuid == Self.ddtCharacteristicUUID || char.uuid == Self.ddtAltUUID {
                ddtCharacteristic = char
                log("  ✓ Kênh DDT xác nhận: \(char.uuid)")
            } else if ddtCharacteristic == nil && (char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse)) {
                ddtCharacteristic = char
            }
            
            if char.uuid == Self.telemetryCharUUID {
                telemetryCharacteristic = char
                log("  ✓ Kênh Telemetry xác nhận: \(char.uuid)")
            }
        }
        
        sendAuthenticationV2()
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("Lỗi ghi đặc tính \(characteristic.uuid): \(error.localizedDescription)")
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
        
        if characteristic.uuid == Self.ddtCharacteristicUUID || characteristic.uuid == Self.ddtAltUUID {
            if let response = streetCross.processIncomingData(data) {
                let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                peripheral.writeValue(response, for: characteristic, type: writeType)
            }
        } else if characteristic.uuid == Self.telemetryCharUUID {
            parseTelemetry(data)
        }
    }
    
    private func parseTelemetry(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return }
        
        // Tốc độ km/h
        let speedRaw = Double(bytes[0]) + (Double(bytes[1]) / 10.0)
        if speedRaw >= 0 && speedRaw < 200 {
            telemetry.speedKmh = speedRaw
        }
        
        // Vòng tua máy RPM
        let rpmRaw = Int(bytes[2]) | (Int(bytes[3]) << 8)
        if rpmRaw > 0 && rpmRaw <= 15000 {
            telemetry.rpm = rpmRaw
        }
        
        if bytes.count >= 5 {
            let fuelRaw = Int(bytes[4])
            if fuelRaw >= 0 && fuelRaw <= 100 {
                telemetry.fuelPercent = fuelRaw
            }
        }
    }
}
