import Foundation
import UIKit
import CoreGraphics
import CoreLocation
import Combine

// MARK: - Trình nạp và lưu trữ ngói bản đồ OpenStreetMap (OSM Tile Engine)
public final class OSMTileEngine {
    public static let shared = OSMTileEngine()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let session: URLSession
    
    // Mặc định dùng ngói CartoDB Dark Matter (100% dữ liệu OpenStreetMap, Singapore CDN siêu nhanh, tối ưu tương phản cho màn hình xe)
    public var tileUrlTemplate: String = "https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png"
    
    public init() {
        memoryCache.countLimit = 300 // Lưu tối đa 300 ngói trong bộ nhớ RAM
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("OSMTiles")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }
    
    public func getCachedTile(x: Int, y: Int, z: Int) -> UIImage? {
        let key = "\(z)_\(x)_\(y)" as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let fileURL = cacheDirectory.appendingPathComponent("\(z)_\(x)_\(y).png")
        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            memoryCache.setObject(img, forKey: key)
            return img
        }
        return nil
    }
    
    public func fetchTile(x: Int, y: Int, z: Int, completion: @escaping (UIImage?) -> Void) {
        if let cached = getCachedTile(x: x, y: y, z: z) {
            completion(cached)
            return
        }
        
        let urlStr = tileUrlTemplate
            .replacingOccurrences(of: "{z}", with: "\(z)")
            .replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{y}", with: "\(y)")
        
        guard let url = URL(string: urlStr) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("MyNMAX-Yamaha-iOS/1.0 (contact: info@mynmax.app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6
        
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, (response as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else {
                completion(nil)
                return
            }
            let key = "\(z)_\(x)_\(y)" as NSString
            self.memoryCache.setObject(img, forKey: key)
            let fileURL = self.cacheDirectory.appendingPathComponent("\(z)_\(x)_\(y).png")
            try? data.write(to: fileURL)
            completion(img)
        }.resume()
    }
}

// MARK: - Renderer tạo khung hình Bản Đồ OpenStreetMap cho màn hình TFT xe máy Yamaha (Tối ưu hóa chạy ngầm, không nghẽn UI)
public final class TFTStreamRenderer: ObservableObject {
    
    // Kích thước chuẩn cho khung hình dẫn đường xe máy Yamaha (NMAX / XMAX: 480 x 234 px; MT-07/09: 480 x 240 px)
    public var targetWidth: Int = 480
    public var targetHeight: Int = 234
    
    @Published public var lastFrameImage: UIImage?
    public static let zoomLevels: [CLLocationDistance] = [200.0, 400.0, 800.0, 1600.0, 3000.0]
    public static let osmZooms: [Int] = [18, 17, 16, 15, 14]
    
    @Published public var currentZoomIndex: Int = 1 // Mặc định 400m (OSM Zoom 17)
    @Published public var mapRadiusMeters: CLLocationDistance = 400.0
    
    public var currentOsmZoom: Int {
        Self.osmZooms[min(max(0, currentZoomIndex), Self.osmZooms.count - 1)]
    }
    
    public var zoomDescription: String {
        switch currentZoomIndex {
        case 0: return "Zoom 4x (200m)"
        case 1: return "Zoom 2x (400m)"
        case 2: return "Zoom 1x (800m)"
        case 3: return "Zoom 0.5x (1.6km)"
        default: return "Zoom Xa (3km)"
        }
    }
    
    // Quản lý luồng render nền (Background Render Queue) để không bao giờ gây lag giao diện iPhone
    private let renderQueue = DispatchQueue(label: "com.mynmax.tftrender", qos: .userInitiated)
    private var isRenderingFrame: Bool = false
    
    // Quản lý tác vụ chạy ngầm khi màn hình tắt (Background Task Token)
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var streamSourceTimer: DispatchSourceTimer?
    private let streamQueue = DispatchQueue(label: "com.mynmax.streamQueue", qos: .userInitiated)
    
    // Lưu thông số gần nhất để khi bấm Zoom có thể render lại tức thì
    private var lastRenderedLocation: CLLocation?
    private var lastRenderedRoute: OSMRoute?
    private var lastRenderedInstruction: NavigationInstruction?
    private var lastRenderedSpeedKmh: Double = 0.0
    private var lastRenderedTelemetry: BikeTelemetry = BikeTelemetry()
    
    public init(width: Int = 480, height: Int = 234) {
        self.targetWidth = width
        self.targetHeight = height
    }
    
    private func beginBgTask() {
        endBgTask()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "TFTOSMStream") { [weak self] in
            self?.endBgTask()
        }
    }
    
    private func endBgTask() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
    }
    
    // MARK: - Luồng truyền hình ảnh ngầm liên tục (vẫn chạy trơn tru khi tắt màn hình)
    public func startBackgroundStreaming(ccuManager: YamahaCCUManager, navEngine: NavigationEngine) {
        stopBackgroundStreaming()
        
        let timer = DispatchSource.makeTimerSource(queue: streamQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1500))
        timer.setEventHandler { [weak self, weak ccuManager, weak navEngine] in
            guard let self = self, let ccu = ccuManager, let nav = navEngine else { return }
            
            let rawSpeed = nav.currentSpeedKmh
            let displaySpeed = rawSpeed >= 2.5 ? rawSpeed : 0.0
            
            let road = nav.currentRoadName
            if !road.isEmpty && road != "MyNMAX" {
                ccu.updateCurrentRoadNameOnTFT(road)
            }
            
            self.renderLiveMapFrame(
                location: nav.currentLocation,
                activeRoute: nav.activeRoute,
                instruction: nav.currentInstruction,
                speedKmh: displaySpeed,
                telemetry: ccu.telemetry
            ) { frameData in
                guard let data = frameData else { return }
                if ccu.isMFiConnected || ccu.state == .streaming {
                    ccu.sendLiveMapFrameToTFT(data)
                }
            }
        }
        timer.resume()
        self.streamSourceTimer = timer
    }
    
    public func stopBackgroundStreaming() {
        streamSourceTimer?.cancel()
        streamSourceTimer = nil
    }
    
    // MARK: - Điều chỉnh mức độ Zoom bản đồ (Tương thích nút + / - trên xe & app)
    public func zoomIn() {
        if currentZoomIndex > 0 {
            currentZoomIndex -= 1
        } else {
            return
        }
        mapRadiusMeters = Self.zoomLevels[currentZoomIndex]
        triggerImmediateReRender()
    }
    
    public func zoomOut() {
        if currentZoomIndex < Self.zoomLevels.count - 1 {
            currentZoomIndex += 1
        } else {
            return
        }
        mapRadiusMeters = Self.zoomLevels[currentZoomIndex]
        triggerImmediateReRender()
    }
    
    private func triggerImmediateReRender() {
        guard let loc = lastRenderedLocation else { return }
        let inst = lastRenderedInstruction ?? NavigationInstruction()
        renderLiveMapFrame(
            location: loc,
            activeRoute: lastRenderedRoute,
            instruction: inst,
            speedKmh: lastRenderedSpeedKmh,
            telemetry: lastRenderedTelemetry
        ) { _ in }
    }
    
    // MARK: - Render khung hình bản đồ OpenStreetMap chạy 100% trên luồng nền (Không bao giờ giật lag)
    public func renderLiveMapFrame(
        location: CLLocation?,
        activeRoute: OSMRoute?,
        instruction: NavigationInstruction,
        speedKmh: Double,
        telemetry: BikeTelemetry,
        completion: @escaping (Data?) -> Void
    ) {
        self.lastRenderedLocation = location
        self.lastRenderedRoute = activeRoute
        self.lastRenderedInstruction = instruction
        self.lastRenderedSpeedKmh = speedKmh
        self.lastRenderedTelemetry = telemetry
        
        // Ngăn chặn render chồng chéo gây tràn CPU
        guard !isRenderingFrame else {
            completion(nil)
            return
        }
        isRenderingFrame = true
        
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            defer { self.isRenderingFrame = false }
            
            guard let loc = location else {
                let placeholderData = self.renderFallbackMapFrame(
                    title: "OpenStreetMap",
                    subtitle: "Đang lấy tín hiệu GPS từ iPhone...",
                    speedKmh: speedKmh,
                    telemetry: telemetry
                )
                completion(placeholderData)
                return
            }
            
            let zoom = self.currentOsmZoom
            let n = pow(2.0, Double(zoom))
            let lon = loc.coordinate.longitude
            let lat = loc.coordinate.latitude
            
            let worldX = (lon + 180.0) / 360.0 * n * 256.0
            let latRad = lat * .pi / 180.0
            let worldY = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n * 256.0
            
            let centerTileX = Int(floor(worldX / 256.0))
            let centerTileY = Int(floor(worldY / 256.0))
            
            let originWorldX = Double((centerTileX - 1) * 256)
            let originWorldY = Double((centerTileY - 1) * 256)
            
            let bikeCanvasX = CGFloat(worldX - originWorldX)
            let bikeCanvasY = CGFloat(worldY - originWorldY)
            
            // Kích thước màn hình TFT đích
            let size = CGSize(width: self.targetWidth, height: self.targetHeight)
            
            UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                completion(nil)
                return
            }
            
            // 1. Nền tối chống chói ban đêm cho màn hình xe
            ctx.setFillColor(UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            
            let heading = loc.course >= 0 ? loc.course : 0.0
            let headingRad = CGFloat(heading * .pi / 180.0)
            let centerPt = CGPoint(x: CGFloat(self.targetWidth) / 2.0, y: CGFloat(self.targetHeight) / 2.0)
            
            ctx.saveGState()
            // Xoay hướng di chuyển của xe luôn hướng lên trên màn hình TFT (Heading-up)
            ctx.translateBy(x: centerPt.x, y: centerPt.y)
            ctx.rotate(by: -headingRad)
            ctx.translateBy(x: -bikeCanvasX, y: -bikeCanvasY)
            
            // 2. Vẽ 9 ngói OpenStreetMap (3x3 grid) xung quanh vị trí xe
            for dx in -1...1 {
                for dy in -1...1 {
                    let tx = centerTileX + dx
                    let ty = centerTileY + dy
                    let destRect = CGRect(x: CGFloat(dx + 1) * 256.0, y: CGFloat(dy + 1) * 256.0, width: 256.0, height: 256.0)
                    
                    if let tile = OSMTileEngine.shared.getCachedTile(x: tx, y: ty, z: zoom) {
                        tile.draw(in: destRect)
                    } else {
                        // Vẽ lưới giả lập trong khi ngói đang được tải
                        ctx.setFillColor(UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0).cgColor)
                        ctx.fill(destRect)
                        ctx.setStrokeColor(UIColor(white: 0.20, alpha: 0.3).cgColor)
                        ctx.stroke(destRect)
                        
                        // Kích hoạt nạp ngầm thuần túy (không gọi re-render tức thì để triệt tiêu lag CPU)
                        OSMTileEngine.shared.fetchTile(x: tx, y: ty, z: zoom) { _ in }
                    }
                }
            }
            
            // 3. Vẽ lộ trình OpenStreetMap (Valhalla / OSM Polyline) trong cùng hệ tọa độ ngói OSM
            if let route = activeRoute, route.coordinates.count > 1 {
                self.drawRoutePolyline(route, in: ctx, zoom: zoom, originX: originWorldX, originY: originWorldY)
            }
            
            ctx.restoreGState()
            
            // 4. Vẽ biểu tượng xe máy trung tâm màn hình (Mũi tên xanh Cyan luôn tiến về phía trước)
            self.drawMotorcycleMarker(in: ctx, center: centerPt)
            
            // 5. Thanh chỉ dẫn điều hướng Turn-by-Turn phía trên (khoảng cách + tên đường)
            self.drawTopNavigationBanner(in: ctx, size: size, instruction: instruction)
            
            // 6. Nhãn bản quyền bắt buộc của OpenStreetMap (nhỏ gọn, thanh lịch)
            self.drawOSMAttribution(in: ctx, size: size)
            
            let finalImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            DispatchQueue.main.async {
                self.lastFrameImage = finalImage
            }
            
            // Nén JPEG chất lượng cao cho giao thức Bluetooth Yamaha StreetCross
            let jpegData = finalImage?.jpegData(compressionQuality: 0.85)
            completion(jpegData)
        }
    }
    
    // MARK: - Vẽ tuyến đường lộ trình trên mặt phẳng ngói OpenStreetMap
    private func drawRoutePolyline(_ route: OSMRoute, in ctx: CGContext, zoom: Int, originX: Double, originY: Double) {
        let n = pow(2.0, Double(zoom))
        let path = UIBezierPath()
        var hasStarted = false
        
        for coord in route.coordinates {
            let ptWorldX = (coord.longitude + 180.0) / 360.0 * n * 256.0
            let ptLatRad = coord.latitude * .pi / 180.0
            let ptWorldY = (1.0 - log(tan(ptLatRad) + 1.0 / cos(ptLatRad)) / .pi) / 2.0 * n * 256.0
            
            let px = CGFloat(ptWorldX - originX)
            let py = CGFloat(ptWorldY - originY)
            
            let pt = CGPoint(x: px, y: py)
            if !hasStarted {
                path.move(to: pt)
                hasStarted = true
            } else {
                path.addLine(to: pt)
            }
        }
        
        if hasStarted {
            // Lớp viền phát sáng màu xanh Yamaha Neon
            ctx.setStrokeColor(UIColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 0.9).cgColor)
            ctx.setLineWidth(8.0)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            path.stroke()
            
            // Lớp lõi màu trắng tinh tế
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(3.5)
            path.stroke()
        }
    }
    
    // MARK: - Vẽ biểu tượng xe máy trung tâm
    private func drawMotorcycleMarker(in ctx: CGContext, center: CGPoint) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        
        // Vòng tròn hào quang phát sáng
        ctx.setFillColor(UIColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 0.25).cgColor)
        ctx.fillEllipse(in: CGRect(x: -20, y: -20, width: 40, height: 40))
        
        // Vòng tròn viền xe
        ctx.setFillColor(UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.85).cgColor)
        ctx.fillEllipse(in: CGRect(x: -10, y: -10, width: 20, height: 20))
        
        // Mũi tên định hướng xe máy luôn chỉ hướng tiến lên
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: 0, y: -14))
        arrow.addLine(to: CGPoint(x: 7, y: 8))
        arrow.addLine(to: CGPoint(x: 0, y: 4))
        arrow.addLine(to: CGPoint(x: -7, y: 8))
        arrow.close()
        
        ctx.setFillColor(UIColor.white.cgColor)
        arrow.fill()
        
        ctx.restoreGState()
    }
    
    // MARK: - Banner thông tin dẫn đường Turn-by-Turn phía trên màn hình TFT
    private func drawTopNavigationBanner(in ctx: CGContext, size: CGSize, instruction: NavigationInstruction) {
        guard instruction.isNavigating else { return }
        
        let bannerRect = CGRect(x: 10, y: 6, width: size.width - 20, height: 46)
        let bannerPath = UIBezierPath(roundedRect: bannerRect, cornerRadius: 8)
        
        ctx.setFillColor(UIColor(white: 0.08, alpha: 0.92).cgColor)
        bannerPath.fill()
        
        ctx.setStrokeColor(UIColor(red: 0.1, green: 0.85, blue: 0.4, alpha: 0.8).cgColor)
        ctx.setLineWidth(1.5)
        bannerPath.stroke()
        
        // Mũi tên chỉ hướng rẽ
        let arrowSymbol = instruction.direction.iconName
        if let arrowImage = UIImage(systemName: arrowSymbol)?.withTintColor(UIColor(red: 0.1, green: 0.95, blue: 0.4, alpha: 1.0), renderingMode: .alwaysOriginal) {
            arrowImage.draw(in: CGRect(x: 16, y: 9, width: 28, height: 28))
        }
        
        let navText = NSMutableAttributedString()
        
        // 1. Khoảng cách còn lại (ví dụ 45m, 1.2km)
        navText.append(NSAttributedString(
            string: instruction.formattedDistance + " ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 23, weight: .heavy),
                .foregroundColor: UIColor(red: 0.1, green: 0.95, blue: 0.4, alpha: 1.0)
            ]
        ))
        
        // 2. Ký tự phân cách
        navText.append(NSAttributedString(
            string: "• ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor(white: 0.6, alpha: 1.0)
            ]
        ))
        
        // 3. Tên đường tiếp theo
        let roadName = instruction.nextRoadName.isEmpty ? "Đang đi theo lộ trình OSM" : instruction.nextRoadName
        navText.append(NSAttributedString(
            string: roadName,
            attributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.white
            ]
        ))
        
        navText.draw(at: CGPoint(x: 52, y: 10))
    }
    
    // MARK: - Nhãn bản quyền OpenStreetMap
    private func drawOSMAttribution(in ctx: CGContext, size: CGSize) {
        let text = "© OpenStreetMap"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor(white: 0.6, alpha: 0.7)
        ]
        text.draw(at: CGPoint(x: size.width - 92, y: size.height - 15), withAttributes: attrs)
    }
    
    private func renderFallbackMapFrame(title: String, subtitle: String, speedKmh: Double, telemetry: BikeTelemetry) -> Data? {
        let size = CGSize(width: targetWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        ctx.setFillColor(UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        
        // Lưới tọa độ
        ctx.setStrokeColor(UIColor(white: 0.2, alpha: 0.3).cgColor)
        ctx.setLineWidth(1.0)
        for x in stride(from: 0, to: size.width, by: 40) {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: 0, to: size.height, by: 40) {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.strokePath()
        
        let tAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        title.draw(at: CGPoint(x: 24, y: 30), withAttributes: tAttrs)
        
        let sAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: UIColor.gray
        ]
        subtitle.draw(at: CGPoint(x: 24, y: 58), withAttributes: sAttrs)
        
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        DispatchQueue.main.async {
            self.lastFrameImage = img
        }
        
        return img?.jpegData(compressionQuality: 0.85)
    }
}


