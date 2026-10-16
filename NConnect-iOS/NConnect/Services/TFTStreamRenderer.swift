import Foundation
import UIKit
import CoreGraphics
import MapKit
import CoreLocation
import Combine

// MARK: - Renderer tạo khung hình Bản Đồ thực tế (Map View) cho màn hình TFT xe máy Yamaha
public final class TFTStreamRenderer: ObservableObject {
    
    // Kích thước chuẩn cho khung hình dẫn đường xe máy Yamaha (NMAX / XMAX: 480 x 234 px; MT-07/09: 480 x 240 px)
    public var targetWidth: Int = 480
    public var targetHeight: Int = 234
    
    @Published public var lastFrameImage: UIImage?
    public static let zoomLevels: [CLLocationDistance] = [200.0, 400.0, 800.0, 1600.0, 3000.0]
    @Published public var currentZoomIndex: Int = 1 // Mặc định 400m
    @Published public var mapRadiusMeters: CLLocationDistance = 400.0
    
    public var zoomDescription: String {
        switch currentZoomIndex {
        case 0: return "Zoom 4x (200m)"
        case 1: return "Zoom 2x (400m)"
        case 2: return "Zoom 1x (800m)"
        case 3: return "Zoom 0.5x (1.6km)"
        default: return "Zoom Xa (3km)"
        }
    }
    
    private var isSnapshotting: Bool = false
    private var activeSnapshotter: MKMapSnapshotter?
    private var cachedMapImage: UIImage?
    private var lastSnapshotCoord: CLLocationCoordinate2D?
    private var lastSnapshotHeading: CLLocationDirection = 0.0
    private var lastSnapshotTime: Date = .distantPast
    
    // Lưu thông số gần nhất để khi bấm Zoom có thể render lại tức thì
    private var lastRenderedLocation: CLLocation?
    private var lastRenderedRoute: MKRoute?
    private var lastRenderedInstruction: NavigationInstruction?
    private var lastRenderedSpeedKmh: Double = 0.0
    private var lastRenderedTelemetry: BikeTelemetry = BikeTelemetry()
    
    public init(width: Int = 480, height: Int = 234) {
        self.targetWidth = width
        self.targetHeight = height
    }
    
    // MARK: - Điều chỉnh mức độ Zoom bản đồ (Tương thích nút + / - trên xe & app)
    public func zoomIn() {
        if currentZoomIndex > 0 {
            currentZoomIndex -= 1
        } else {
            return
        }
        mapRadiusMeters = Self.zoomLevels[currentZoomIndex]
        cachedMapImage = nil
        lastSnapshotCoord = nil
        lastSnapshotHeading = 0.0
        lastSnapshotTime = .distantPast
        triggerImmediateReRender()
    }
    
    public func zoomOut() {
        if currentZoomIndex < Self.zoomLevels.count - 1 {
            currentZoomIndex += 1
        } else {
            return
        }
        mapRadiusMeters = Self.zoomLevels[currentZoomIndex]
        cachedMapImage = nil
        lastSnapshotCoord = nil
        lastSnapshotHeading = 0.0
        lastSnapshotTime = .distantPast
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
    
    // MARK: - Chụp và render khung hình bản đồ động theo vị trí thực tế của xe
    public func renderLiveMapFrame(
        location: CLLocation?,
        activeRoute: MKRoute?,
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
        
        guard let loc = location else {
            // Nếu chưa có vị trí GPS, vẽ khung khởi tạo bản đồ
            let placeholderData = renderFallbackMapFrame(
                title: "Đang tải bản đồ...",
                subtitle: "Đang lấy tín hiệu GPS từ iPhone",
                speedKmh: speedKmh,
                telemetry: telemetry
            )
            completion(placeholderData)
            return
        }
        
        let now = Date()
        let dist = lastSnapshotCoord != nil ? loc.distance(from: CLLocation(latitude: lastSnapshotCoord!.latitude, longitude: lastSnapshotCoord!.longitude)) : 999.0
        let currentHeading = loc.course >= 0 ? loc.course : 0.0
        let headingDiff = abs(currentHeading - lastSnapshotHeading)
        let timeSinceLast = now.timeIntervalSince(lastSnapshotTime)
        
        // Điều kiện chụp khung hình bản đồ nền mới:
        // 1. Chưa có ảnh ban đầu
        // 2. Xe đã di chuyển hơn 25 mét hoặc rẽ góc lớn hơn 30 độ
        // 3. Hoặc đã hơn 4 giây và xe có di chuyển
        let shouldTakeNewSnapshot = (cachedMapImage == nil) ||
            (dist > 25.0) ||
            (headingDiff > 30.0 && timeSinceLast >= 2.0) ||
            (timeSinceLast >= 4.0 && dist > 10.0)
        
        if shouldTakeNewSnapshot && !isSnapshotting {
            isSnapshotting = true
            
            let padding: CGFloat = 80.0
            let snapSize = CGSize(width: CGFloat(targetWidth) + padding, height: CGFloat(targetHeight) + padding)
            
            let options = MKMapSnapshotter.Options()
            options.size = snapSize
            options.camera = MKMapCamera(
                lookingAtCenter: loc.coordinate,
                fromDistance: mapRadiusMeters * 2.2,
                pitch: 0,
                heading: currentHeading
            )
            options.mapType = .standard
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
            
            let snapshotter = MKMapSnapshotter(options: options)
            self.activeSnapshotter = snapshotter // Giữ strong reference để ARC không hủy tác vụ chụp ngầm
            
            snapshotter.start(with: .main) { [weak self] snapshot, error in
                guard let self = self else { return }
                self.isSnapshotting = false
                self.activeSnapshotter = nil
                
                if let error = error {
                    print("[TFTStreamRenderer] Lỗi chụp bản đồ: \(error.localizedDescription)")
                }
                
                if let snap = snapshot {
                    self.cachedMapImage = snap.image
                    self.lastSnapshotCoord = loc.coordinate
                    self.lastSnapshotHeading = currentHeading
                    self.lastSnapshotTime = Date()
                }
                
                let frameData = self.compositeMapWithHUD(
                    mapImage: self.cachedMapImage,
                    location: loc,
                    activeRoute: activeRoute,
                    instruction: instruction,
                    speedKmh: speedKmh,
                    telemetry: telemetry
                )
                completion(frameData)
            }
        } else {
            // Tái sử dụng bản đồ đã nạp và áp dụng dịch chuyển pixel theo GPS thời gian thực (không độ trễ)
            let frameData = compositeMapWithHUD(
                mapImage: cachedMapImage,
                location: loc,
                activeRoute: activeRoute,
                instruction: instruction,
                speedKmh: speedKmh,
                telemetry: telemetry
            )
            completion(frameData)
        }
    }
    
    // MARK: - Ghép lớp bản đồ + Đường đi + Mũi tên xe + Bảng đồng hồ HUD
    private func compositeMapWithHUD(
        mapImage: UIImage?,
        location: CLLocation,
        activeRoute: MKRoute?,
        instruction: NavigationInstruction,
        speedKmh: Double,
        telemetry: BikeTelemetry
    ) -> Data? {
        let size = CGSize(width: targetWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        let padding: CGFloat = 80.0
        let snapSize = CGSize(width: CGFloat(targetWidth) + padding, height: CGFloat(targetHeight) + padding)
        
        // 1. Nền bản đồ thực tế với tính toán dịch chuyển pixel liên tục theo GPS
        if let map = mapImage {
            var screenOffsetX: CGFloat = 0.0
            var screenOffsetY: CGFloat = 0.0
            
            if let snapCoord = lastSnapshotCoord {
                let dLat = (location.coordinate.latitude - snapCoord.latitude) * 111_000.0 // mét về hướng Bắc
                let dLon = (location.coordinate.longitude - snapCoord.longitude) * 111_000.0 * cos(snapCoord.latitude * .pi / 180.0) // mét về hướng Đông
                
                let rad = lastSnapshotHeading * .pi / 180.0
                let forwardMeters = dLat * cos(rad) + dLon * sin(rad)
                let rightMeters = dLon * cos(rad) - dLat * sin(rad)
                
                let ppm = Double(targetWidth) / (mapRadiusMeters * 2.2)
                screenOffsetX = CGFloat(rightMeters * ppm)
                screenOffsetY = CGFloat(-forwardMeters * ppm)
            }
            
            // Căn giữa ảnh đệm (-padding / 2) và trượt theo độ dời GPS tức thời
            let originX = -padding / 2.0 - screenOffsetX
            let originY = -padding / 2.0 - screenOffsetY
            map.draw(in: CGRect(x: originX, y: originY, width: snapSize.width, height: snapSize.height))
        } else {
            ctx.setFillColor(UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            drawGridLines(in: ctx, size: size)
        }
        
        // 2. Vẽ tuyến đường dẫn đường (nếu có lộ trình) xoay đồng bộ theo hướng camera
        if let route = activeRoute {
            drawRoutePolyline(route, in: ctx, size: size, centerCoord: location.coordinate, heading: lastSnapshotHeading)
        }
        
        // 3. Vẽ biểu tượng vị trí xe máy ở giữa màn hình (hướng xe tương đối so với camera)
        let relativeHeading = location.course >= 0 ? (location.course - lastSnapshotHeading) : 0.0
        drawMotorcycleMarker(in: ctx, center: CGPoint(x: size.width / 2, y: size.height / 2), relativeHeading: relativeHeading)
        
        // 4. Lớp phủ thanh trạng thái phía trên (Top HUD: Tên đường hoặc Hướng rẽ)
        drawTopNavigationBanner(in: ctx, size: size, instruction: instruction)
        
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        DispatchQueue.main.async {
            self.lastFrameImage = finalImage
        }
        
        // Nén JPEG chất lượng cao (yêu cầu chuẩn giao thức Yamaha StreetCross > 2048 bytes)
        return finalImage?.jpegData(compressionQuality: 0.85)
    }
    
    // MARK: - Vẽ biểu tượng xe máy trung tâm
    private func drawMotorcycleMarker(in ctx: CGContext, center: CGPoint, relativeHeading: CLLocationDirection) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        
        // Xoay theo góc lệch tương đối của xe so với hướng bản đồ
        let radians = CGFloat(relativeHeading * .pi / 180.0)
        ctx.rotate(by: radians)
        
        // Vòng tròn hào quang phát sáng
        ctx.setFillColor(UIColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 0.25).cgColor)
        ctx.fillEllipse(in: CGRect(x: -20, y: -20, width: 40, height: 40))
        
        // Vòng tròn viền xe
        ctx.setFillColor(UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.8).cgColor)
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
    
    // MARK: - Vẽ tuyến đường (Route Polyline) xoay đồng bộ theo camera
    private func drawRoutePolyline(_ route: MKRoute, in ctx: CGContext, size: CGSize, centerCoord: CLLocationCoordinate2D, heading: CLLocationDirection) {
        let pointCount = route.polyline.pointCount
        guard pointCount > 1 else { return }
        
        let points = route.polyline.points()
        let path = UIBezierPath()
        var hasStarted = false
        
        let centerPoint = MKMapPoint(centerCoord)
        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(centerCoord.latitude)
        let ppm = Double(size.width) / (mapRadiusMeters * 2.2)
        let rad = heading * .pi / 180.0
        
        for i in 0..<min(pointCount, 250) {
            let p = points[i]
            let dxMeters = (p.x - centerPoint.x) / mapPointsPerMeter
            let dyMeters = (p.y - centerPoint.y) / mapPointsPerMeter
            
            // MapPoint y tăng về phía Nam, nên khoảng cách Bắc = -dyMeters
            let northMeters = -dyMeters
            let eastMeters = dxMeters
            
            // Xoay theo camera heading
            let forwardMeters = northMeters * cos(rad) + eastMeters * sin(rad)
            let rightMeters = eastMeters * cos(rad) - northMeters * sin(rad)
            
            let screenX = size.width / 2.0 + CGFloat(rightMeters * ppm)
            let screenY = size.height / 2.0 - CGFloat(forwardMeters * ppm)
            
            if screenX >= -80 && screenX <= size.width + 80 && screenY >= -80 && screenY <= size.height + 80 {
                let pt = CGPoint(x: screenX, y: screenY)
                if !hasStarted {
                    path.move(to: pt)
                    hasStarted = true
                } else {
                    path.addLine(to: pt)
                }
            }
        }
        
        if hasStarted {
            ctx.setStrokeColor(UIColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.85).cgColor)
            ctx.setLineWidth(7.0)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            path.stroke()
            
            // Viền lõi trắng sáng cho tuyến đường
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(3.0)
            path.stroke()
        }
    }
    
    // MARK: - Vẽ banner thông tin phía trên (Chỉ hiển thị khi đang dẫn đường)
    private func drawTopNavigationBanner(in ctx: CGContext, size: CGSize, instruction: NavigationInstruction) {
        // Chỉ vẽ khung dẫn đường khi đang có lộ trình dẫn đường thực tế
        guard instruction.isNavigating else { return }
        
        let bannerRect = CGRect(x: 10, y: 6, width: size.width - 20, height: 46)
        let bannerPath = UIBezierPath(roundedRect: bannerRect, cornerRadius: 8)
        
        ctx.setFillColor(UIColor(white: 0.08, alpha: 0.92).cgColor)
        bannerPath.fill()
        
        ctx.setStrokeColor(UIColor(red: 0.1, green: 0.85, blue: 0.4, alpha: 0.8).cgColor)
        ctx.setLineWidth(1.5)
        bannerPath.stroke()
        
        // Mũi tên chỉ hướng
        let arrowSymbol = instruction.direction.iconName
        if let arrowImage = UIImage(systemName: arrowSymbol)?.withTintColor(UIColor(red: 0.1, green: 0.95, blue: 0.4, alpha: 1.0), renderingMode: .alwaysOriginal) {
            arrowImage.draw(in: CGRect(x: 16, y: 9, width: 28, height: 28))
        }
        
        // Dòng chữ điều hướng: Khoảng cách + Tên đường trên cùng 1 hàng, chữ phóng to cực đậm
        let navText = NSMutableAttributedString()
        
        // 1. Khoảng cách (ví dụ 45m, 1.2km) - Font 23pt cực to, màu xanh lá neon
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
        
        // 3. Tên đường kế tiếp - Font 20pt to rõ, màu trắng tinh
        let roadName = instruction.nextRoadName.isEmpty ? "Đang đi theo lộ trình" : instruction.nextRoadName
        navText.append(NSAttributedString(
            string: roadName,
            attributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.white
            ]
        ))
        
        navText.draw(at: CGPoint(x: 52, y: 10))
    }
    
    // MARK: - Đồng hồ đo tốc độ góc dưới bên trái
    private func drawSpeedometerHUD(in ctx: CGContext, size: CGSize, speedKmh: Double, telemetry: BikeTelemetry) {
        let hudRect = CGRect(x: 10, y: size.height - 62, width: 110, height: 54)
        let hudPath = UIBezierPath(roundedRect: hudRect, cornerRadius: 8)
        
        ctx.setFillColor(UIColor(white: 0.08, alpha: 0.88).cgColor)
        hudPath.fill()
        
        ctx.setStrokeColor(UIColor(white: 0.3, alpha: 0.5).cgColor)
        ctx.setLineWidth(1.0)
        hudPath.stroke()
        
        let speedVal = Int(telemetry.speedKmh > 0 ? telemetry.speedKmh : max(0, speedKmh))
        let speedStr = "\(speedVal)"
        let speedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 34, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        speedStr.draw(at: CGPoint(x: 18, y: size.height - 60), withAttributes: speedAttrs)
        
        let kmhAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        ]
        "KM/H".draw(at: CGPoint(x: 68, y: size.height - 40), withAttributes: kmhAttrs)
    }
    
    // MARK: - Huy hiệu thông tin góc dưới bên phải
    private func drawStatusBadge(in ctx: CGContext, size: CGSize, telemetry: BikeTelemetry) {
        let badgeRect = CGRect(x: size.width - 105, y: size.height - 38, width: 95, height: 30)
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 6)
        
        ctx.setFillColor(UIColor(white: 0.08, alpha: 0.88).cgColor)
        badgePath.fill()
        
        let text = telemetry.fuelPercent > 0 ? "⛽ \(telemetry.fuelPercent)%" : "YAMAHA"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: telemetry.fuelPercent > 0 ? UIColor.orange : UIColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 1.0)
        ]
        text.draw(at: CGPoint(x: size.width - 92, y: size.height - 32), withAttributes: attrs)
    }
    
    private func drawGridLines(in ctx: CGContext, size: CGSize) {
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
        drawGridLines(in: ctx, size: size)
        
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
