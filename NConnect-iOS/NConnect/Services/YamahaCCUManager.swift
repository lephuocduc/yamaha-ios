import Foundation
import CoreBluetooth
import Combine

// MARK: - Quản lý kết nối Bluetooth BLE Yamaha CCU (ClusterLink)
public final class YamahaCCUManager: NSObject, ObservableObject {
    
    // UUID Dịch vụ & Đặc tính chuẩn của Yamaha ClusterLink CCU
    public static let clusterLinkServiceUUID = CBUUID(string: "AFA2CDF4-ECCF-46A7-A5EA-9DA428C0157A")
    public static let ddtCharacteristicUUID  = CBUUID(string: "B606C7F9-E5A1-4E75-B313-2A920054A8EB")
    public static let telemetryCharUUID      = CBUUID(string: "9C810D26-B605-4306-8C1C-755A1BA3066C")
    public static let commandCharUUID        = CBUUID(string: "AB8D233A-CC58-4932-B397-A3751911E021")
    
    @Published public var state: BikeConnectionState = .disconnected
    @Published public var discoveredBikes: [BikeDevice] = []
    @Published public var connectedBike: BikeDevice?
    @Published public var telemetry: BikeTelemetry = BikeTelemetry()
    
    private var centralManager: CBCentralManager!
    private var currentPeripheral: CBPeripheral?
    private var ddtCharacteristic: CBCharacteristic?
    private var telemetryCharacteristic: CBCharacteristic?
    
    // Giao thức StreetCross tích hợp
    public let streetCross = StreetCrossProtocol()
    
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    // MARK: - Bắt đầu quét tìm xe
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[YamahaCCU] Bluetooth chưa sẵn sàng (\(centralManager.state.rawValue))")
            return
        }
        state = .scanning
        discoveredBikes.removeAll()
        print("[YamahaCCU] Bắt đầu quét BLE tìm xe Yamaha (YCCU_...)...")
        
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
        print("[YamahaCCU] Đang kết nối tới xe \(device.name)...")
        
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
    }
    
    // MARK: - Gửi gói tin AuthenticationV2 qua DDT
    private func sendAuthenticationV2() {
        guard let peripheral = currentPeripheral, let ddtChar = ddtCharacteristic else { return }
        state = .authenticating
        print("[YamahaCCU] Bước 5: Gửi AuthenticationV2 qua kênh DDT...")
        
        // Gói xác thực V2 chuẩn của Yamaha ClusterLink
        var authPacket = Data([0x02, 0x01, 0x00, 0x10])
        let appIdBytes = [UInt8]("NConnectIOS".utf8)
        authPacket.append(contentsOf: appIdBytes)
        
        peripheral.writeValue(authPacket, for: ddtChar, type: .withResponse)
    }
    
    // MARK: - Gửi dữ liệu khung hình lên màn hình TFT
    public func sendFrameDataToTFT(_ packets: [Data]) {
        guard let peripheral = currentPeripheral, let ddtChar = ddtCharacteristic, state == .streaming || state == .connected else { return }
        
        for packet in packets {
            peripheral.writeValue(packet, for: ddtChar, type: .withoutResponse)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension YamahaCCUManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[YamahaCCU] Bluetooth đã BẬT")
            startScanning()
        case .poweredOff:
            print("[YamahaCCU] Bluetooth đã TẮT")
            state = .error
        default:
            break
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        
        // Lọc các thiết bị xe máy Yamaha: Bắt đầu bằng YCCU_ hoặc YS hoặc CCU
        if name.hasPrefix("YCCU_") || name.hasPrefix("YS_") || name.contains("CCU") || name.contains("Yamaha") {
            let bike = BikeDevice(
                id: peripheral.identifier,
                name: name,
                address: peripheral.identifier.uuidString,
                rssi: RSSI.intValue,
                isPaired: false
            )
            
            if !discoveredBikes.contains(where: { $0.id == bike.id }) {
                print("[YamahaCCU] Thấy xe: \(name), RSSI: \(RSSI)")
                discoveredBikes.append(bike)
                
                // Tự động kết nối nếu là xe quen thuộc
                if connectedBike == nil && discoveredBikes.count == 1 {
                    connect(to: bike)
                }
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[YamahaCCU] ✓ Đã kết nối GATT với xe \(peripheral.name ?? ""), bắt đầu tìm dịch vụ ClusterLink...")
        state = .connected
        connectedBike = BikeDevice(id: peripheral.identifier, name: peripheral.name ?? "Yamaha CCU", isPaired: true)
        
        peripheral.discoverServices([Self.clusterLinkServiceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[YamahaCCU] ✗ Không kết nối được: \(error?.localizedDescription ?? "")")
        state = .error
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[YamahaCCU] Xe đã ngắt kết nối: \(error?.localizedDescription ?? "Bình thường")")
        state = .disconnected
        connectedBike = nil
        streetCross.reset()
        
        // Tự động quét lại để kết nối lại khi bật xe
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.startScanning()
        }
    }
}

// MARK: - CBPeripheralDelegate
extension YamahaCCUManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == Self.clusterLinkServiceUUID {
                print("[YamahaCCU] Thấy dịch vụ ClusterLink! Đang đọc các đặc tính...")
                peripheral.discoverCharacteristics([
                    Self.ddtCharacteristicUUID,
                    Self.telemetryCharUUID,
                    Self.commandCharUUID
                ], for: service)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == Self.ddtCharacteristicUUID {
                ddtCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("[YamahaCCU] Đã kích hoạt kênh DDT. Bắt đầu xác thực AuthenticationV2...")
                sendAuthenticationV2()
            } else if char.uuid == Self.telemetryCharUUID {
                telemetryCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if characteristic.uuid == Self.ddtCharacteristicUUID {
            // Xử lý gói tin DDT qua StreetCross protocol
            if let response = streetCross.processIncomingData(data) {
                peripheral.writeValue(response, for: characteristic, type: .withResponse)
            }
        } else if characteristic.uuid == Self.telemetryCharUUID {
            // Cập nhật thông số tức thời của xe (Tốc độ, RPM, Xăng)
            parseTelemetry(data)
        }
    }
    
    private func parseTelemetry(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return }
        
        // Tốc độ km/h
        let speedRaw = Double(bytes[0]) + (Double(bytes[1]) / 10.0)
        telemetry.speedKmh = speedRaw
        
        // Vòng tua máy RPM
        let rpmRaw = Int(bytes[2]) | (Int(bytes[3]) << 8)
        telemetry.rpm = rpmRaw
        
        // Phần trăm xăng
        telemetry.fuelPercent = Int(bytes[4])
    }
}
