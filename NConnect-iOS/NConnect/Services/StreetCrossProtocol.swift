import Foundation
import UIKit

// MARK: - Giao thức Garmin StreetCross dành cho màn hình TFT xe máy Yamaha
public final class StreetCrossProtocol {
    
    // UUID dịch vụ Garmin StreetCross
    public static let streetCrossUUID = "00007220-0000-1000-8000-00805F9B34FB"
    public static let softwarePartNumber = "006-B4160" // Mã phần mềm chuẩn cho XMAX / NMAX
    public static let fallbackPartNumber = "006-B3952-10"
    
    public enum HandshakeStep: Int {
        case notStarted = 0
        case step1SerialReceived = 1
        case step2DimensionsNegotiated = 2
        case step3FullyAuthenticated = 3
    }
    
    public private(set) var currentStep: HandshakeStep = .notStarted
    public var displaySpec: TFTDisplaySpec = TFTDisplaySpec()
    public private(set) var frameIndex: UInt32 = 0
    
    // Callbacks xử lý sự kiện từ xe
    public var onHandshakeCompleted: ((TFTDisplaySpec) -> Void)?
    public var onHandlebarButtonReceived: ((HandlebarButton) -> Void)?
    public var onFrameAckReceived: ((UInt32) -> Void)?
    
    public enum HandlebarButton {
        case zoomIn
        case zoomOut
        case startStreamOrOpenMenu      // Mã 55
        case pauseStreamOrCloseMenu     // Mã 56
        case stopRoute                  // Mã 49
        case goHome                     // Mã 53
        case goToWork                   // Mã 54
        case openFavorites              // Mã 55 (sub 3)
        case openGasStations            // Mã 55 (sub 4)
        case selectPoiItem(index: Int, listId: Int) // Mã 48
        case unknown(code: UInt8)
    }
    
    public init() {}
    
    public func reset() {
        currentStep = .notStarted
        frameIndex = 0
        displaySpec = TFTDisplaySpec()
    }
    
    // MARK: - Xử lý gói tin nhận từ xe máy qua Bluetooth
    public func processIncomingData(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let bytes = [UInt8](data)
        let command = bytes[0]
        
        switch currentStep {
        case .notStarted, .step1SerialReceived:
            // Bắt tay bước 1: Xe gửi Serial máy
            // Phản hồi: Lệnh 81 (0x51) + 33 (0x21)
            if command == 0x01 || data.count >= 8 {
                let serialStr = String(bytes: bytes.prefix(16), encoding: .ascii) ?? "CCU-YAMAHA"
                print("[StreetCross] Bắt tay 1/3: Xe gửi serial '\(serialStr)' → Trả 0x51 + 0x21")
                currentStep = .step1SerialReceived
                return Data([0x51, 0x21, 0x00, 0x00])
            }
            
        case .step2DimensionsNegotiated:
            // Bắt tay bước 2 & 3: Xe xác thực và gửi kích thước màn hình
            if command == 0x53 || command == 0x83 {
                // Đọc kích thước màn hình xe trả về (thường là 480x272 hoặc 400x240)
                var width = 480
                var height = 234
                if bytes.count >= 6 {
                    width = Int(bytes[2]) | (Int(bytes[3]) << 8)
                    height = Int(bytes[4]) | (Int(bytes[5]) << 8)
                    if width <= 0 || width > 1920 { width = 480 }
                    if height <= 0 || height > 1080 { height = 234 }
                }
                
                displaySpec = TFTDisplaySpec(width: width, height: height, softwarePart: Self.softwarePartNumber, isReady: true)
                print("[StreetCross] Bắt tay 2/3: Màn hình TFT = \(width)x\(height) → Gửi phản hồi 0x84")
                
                // Trả về gói 84 (0x54) xác nhận kích thước
                var resp = Data([0x54, 0x01])
                resp.append(Self.softwarePartNumber.data(using: .ascii) ?? Data())
                return resp
            } else if command == 0x82 {
                // Bắt tay 3/3: Xe xác nhận (82 = 1)
                let status = bytes.count > 1 ? bytes[1] : 0
                if status == 1 {
                    currentStep = .step3FullyAuthenticated
                    displaySpec.isReadyForStreaming = true
                    print("[StreetCross] ✓ Bắt tay 3/3: Xe xác nhận thành công (82 = 1)! Bắt đầu truyền hình")
                    onHandshakeCompleted?(displaySpec)
                    return buildInitialConfigPacket()
                } else {
                    print("[StreetCross] ✗ Xe từ chối xác thực (82 = \(status))")
                }
            }
            
        case .step3FullyAuthenticated:
            // Xử lý các lệnh điều khiển từ phím bấm tay lái khi đang chạy
            return handleOperationalCommands(command: command, bytes: bytes)
        }
        
        return nil
    }
    
    // MARK: - Xử lý lệnh vận hành & phím bấm tay lái
    private func handleOperationalCommands(command: UInt8, bytes: [UInt8]) -> Data? {
        switch command {
        case 51, 57: // Phím (+) / Nút Lên trên cùm tay lái xe
            print("[StreetCross] Phím cùm xe: Phóng to (+) / Zoom In (mã \(command))")
            onHandlebarButtonReceived?(.zoomIn)
            return nil
            
        case 52, 58: // Phím (-) / Nút Xuống trên cùm tay lái xe
            print("[StreetCross] Phím cùm xe: Thu nhỏ (-) / Zoom Out (mã \(command))")
            onHandlebarButtonReceived?(.zoomOut)
            return nil
            
        case 53: // 0x35: Menu xe: Về nhà (Go home)
            print("[StreetCross] Menu đồng hồ: Lệnh 53 (Về nhà / Go home)")
            onHandlebarButtonReceived?(.goHome)
            return nil
            
        case 54: // 0x36: Menu xe: Đi làm (Go to work)
            print("[StreetCross] Menu đồng hồ: Lệnh 54 (Đi làm / Go to work)")
            onHandlebarButtonReceived?(.goToWork)
            return nil
            
        case 49: // 0x31: Dừng lộ trình dẫn đường từ nút tay lái
            print("[StreetCross] Menu đồng hồ: Dừng lộ trình (49)")
            onHandlebarButtonReceived?(.stopRoute)
            return nil
            
        case 55: // 0x37: Mở danh sách hoặc bắt đầu nhận hình
            let sub = bytes.count > 1 ? bytes[1] : 1
            if sub == 3 {
                print("[StreetCross] Menu đồng hồ: Mở danh sách Yêu thích (55, sub 3)")
                onHandlebarButtonReceived?(.openFavorites)
            } else if sub == 4 {
                print("[StreetCross] Menu đồng hồ: Mở danh sách Cây xăng (55, sub 4)")
                onHandlebarButtonReceived?(.openGasStations)
            } else {
                print("[StreetCross] Menu đồng hồ: Bắt đầu nhận hình (55, sub \(sub))")
                onHandlebarButtonReceived?(.startStreamOrOpenMenu)
            }
            return nil
            
        case 56: // 0x38: Xe tạm dừng nhận hình / đóng danh sách → Phản hồi 20 (0x14)
            print("[StreetCross] Menu đồng hồ: Đóng danh sách / Tạm dừng nhận hình (56) → Trả 20")
            onHandlebarButtonReceived?(.pauseStreamOrCloseMenu)
            return Data([0x14, 0x00])
            
        case 48: // 0x30: Chọn mục POI từ danh sách
            let itemIdx = bytes.count > 1 ? Int(bytes[1]) : 0
            let listId = bytes.count > 2 ? Int(bytes[2]) : 0
            print("[StreetCross] Menu đồng hồ: Chọn mục \(itemIdx) của danh sách \(listId) (48)")
            onHandlebarButtonReceived?(.selectPoiItem(index: itemIdx, listId: listId))
            return nil
            
        case 0x06: // ACK khung hình từ màn hình TFT
            if bytes.count >= 5 {
                let ackIndex = UInt32(bytes[1]) | (UInt32(bytes[2]) << 8) | (UInt32(bytes[3]) << 16) | (UInt32(bytes[4]) << 24)
                onFrameAckReceived?(ackIndex)
            }
            return nil
            
        default:
            print("[StreetCross] Lệnh từ xe: 0x\(String(format: "%02X", command)) (\(bytes.count)B)")
            onHandlebarButtonReceived?(.unknown(code: command))
            return nil
        }
    }
    
    // MARK: - Gói cấu hình ban đầu
    private func buildInitialConfigPacket() -> Data {
        var packet = Data([0x20, 0x00, 0x01, 0x00])
        packet.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // Chế độ hiển thị đồ họa
        return packet
    }
    
    // MARK: - Đóng gói Frame ảnh JPEG nén để stream lên màn hình TFT
    public func encodeJPEGFrameForTFT(_ jpegData: Data) -> [Data] {
        guard jpegData.count >= 2048 else {
            print("[StreetCross] Cảnh báo: Kích thước JPEG quá nhỏ (\(jpegData.count)B), cần >= 2048B")
            return []
        }
        
        frameIndex &+= 1
        let currentIdx = frameIndex
        
        // Header khung hình: [0x05, FrameIdx(4B), TotalSize(4B)]
        var frameHeader = Data([0x05])
        var idxLE = currentIdx.littleEndian
        var sizeLE = UInt32(jpegData.count).littleEndian
        frameHeader.append(Data(bytes: &idxLE, count: 4))
        frameHeader.append(Data(bytes: &sizeLE, count: 4))
        
        // Cắt thành các chunk vừa với MTU Bluetooth (~512 bytes)
        let chunkSize = 500
        var packets: [Data] = []
        var fullPayload = frameHeader
        fullPayload.append(jpegData)
        
        var offset = 0
        while offset < fullPayload.count {
            let chunkLen = min(chunkSize, fullPayload.count - offset)
            let chunk = fullPayload.subdata(in: offset..<(offset + chunkLen))
            packets.append(chunk)
            offset += chunkLen
        }
        
        return packets
    }
    
    // MARK: - Gói tin Turn-by-Turn (Mũi tên chỉ đường + Khoảng cách + Tên đường)
    public func buildTurnByTurnPacket(instruction: NavigationInstruction) -> Data {
        var packet = Data([0x30]) // Lệnh hiển thị dẫn đường
        
        // Mũi tên chỉ hướng (1 byte)
        packet.append(UInt8(instruction.direction.rawValue))
        
        // Khoảng cách (4 bytes LE)
        var distLE = UInt32(instruction.distanceMeters).littleEndian
        packet.append(Data(bytes: &distLE, count: 4))
        
        // Tên đường hiện tại / sắp tới (UTF-8)
        let roadData = instruction.nextRoadName.data(using: .utf8) ?? Data()
        var roadLen = UInt16(roadData.count).littleEndian
        packet.append(Data(bytes: &roadLen, count: 2))
        packet.append(roadData)
        
        return packet
    }
}

// MARK: - NaviLite Protocol Codec (Garmin StreetCross wire format on Yamaha TFT)
public struct NaviFrame {
    public let svc: Int
    public let payload: [UInt8]
    
    public init(svc: Int, payload: [UInt8]) {
        self.svc = svc
        self.payload = payload
    }
}

public enum NaviLite {
    public static let FT_PHONE: UInt8 = 6
    
    private static let CRC_TABLE: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i) << 24
            for _ in 0..<8 {
                c = (c & 0x80000000) != 0 ? ((c << 1) ^ 0x04C11DB7) : (c << 1)
            }
            t[i] = c & 0xffffffff
        }
        return t
    }()
    
    public static func crc32Mpeg2(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data {
            c = ((c << 8) ^ CRC_TABLE[Int(((c >> 24) ^ UInt32(b)) & 0xff)]) & 0xffffffff
        }
        return c
    }
    
    /// Đóng gói khung tin NaviLite: "nAl@" | version 1 | frameType | serviceType | size(4 LE) | pdt | crc(4 LE) | payload
    public static func frame(_ ft: UInt8, _ svc: UInt8, _ pdt: UInt8, _ payload: [UInt8]) -> Data {
        let size = payload.count
        let h: [UInt8] = [
            0x6e, 0x41, 0x6c, 0x40, // "nAl@" magic
            1,                      // version 1
            ft,                     // frameType (e.g. 6 = PHONE)
            svc,                    // serviceType
            UInt8(size & 0xff),
            UInt8((size >> 8) & 0xff),
            UInt8((size >> 16) & 0xff),
            UInt8((size >> 24) & 0xff),
            pdt                     // payloadDataType (0 = VALUE, 1 = POINTER)
        ]
        var hp = h
        hp.append(contentsOf: payload)
        let crc = crc32Mpeg2(hp)
        
        var out = Data(h)
        var crcLE = crc.littleEndian
        out.append(Data(bytes: &crcLE, count: 4))
        out.append(Data(payload))
        return out
    }
    
    /// Echo-auth: xe gửi hạt giống bảo mật (SEC_DATA); điện thoại phản hồi 4 byte cuối XOR 0x0a
    public static func secDataAckPayload(_ seed: [UInt8]) -> [UInt8] {
        let n = 4
        guard seed.count >= n else { return [0, 0, 0, 0] }
        return (0..<n).map { seed[seed.count - n + $0] ^ 0x0a }
    }
    
    public static func partNumber(_ seed: [UInt8]) -> String {
        guard seed.count > 4 else { return "?" }
        let raw = seed[0..<(seed.count - 4)].map { $0 ^ 0x0a }
        return String(bytes: raw, encoding: .ascii) ?? "?"
    }
    
    public static func hexB(_ s: String) -> [UInt8] {
        var r = [UInt8]()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
            if let val = UInt8(s[i..<j], radix: 16) {
                r.append(val)
            }
            i = j
        }
        return r
    }
}

