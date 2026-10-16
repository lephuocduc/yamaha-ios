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
        case selectPoiItem(index: Int)
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
                var height = 272
                if bytes.count >= 6 {
                    width = Int(bytes[2]) | (Int(bytes[3]) << 8)
                    height = Int(bytes[4]) | (Int(bytes[5]) << 8)
                    if width <= 0 || width > 1920 { width = 480 }
                    if height <= 0 || height > 1080 { height = 272 }
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
        case 55: // 0x37: Xe yêu cầu bắt đầu nhận hình hoặc mở danh sách
            print("[StreetCross] Menu đồng hồ: Mở danh sách / Bắt đầu nhận hình (55)")
            onHandlebarButtonReceived?(.startStreamOrOpenMenu)
            return nil
            
        case 56: // 0x38: Xe tạm dừng nhận hình → Phản hồi 20 (0x14)
            print("[StreetCross] Menu đồng hồ: Đóng danh sách / Tạm dừng nhận hình (56) → Trả 20")
            onHandlebarButtonReceived?(.pauseStreamOrCloseMenu)
            return Data([0x14, 0x00])
            
        case 49: // 0x31: Dừng lộ trình dẫn đường từ nút tay lái
            print("[StreetCross] Menu đồng hồ: Dừng lộ trình (49)")
            onHandlebarButtonReceived?(.stopRoute)
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
