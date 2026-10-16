import Foundation
import UIKit
import CoreGraphics
import MapKit
import CoreLocation
import Combine

// MARK: - Renderer tạo khung hình Bản Đồ thực tế (Map View) cho màn hình TFT xe máy Yamaha
public final class TFTStreamRenderer: ObservableObject {
    
    // Kích thước chuẩn cho màn hình TFT (Yamaha XMAX / NMAX 4.2-inch: 480 x 272 px)
    public var targetWidth: Int = 480
    public var targetHeight: Int = 272
    
    @Published public var lastFrameImage: UIImage?
    
    private var isSnapshotting: Bool = false
    private var cachedMapImage: UIImage?
    private var lastSnapshotCoord: CLLocationCoordinate2D?
    private var lastSnapshotTime: Date = .distantPast
    
    public init(width: Int = 480, height: Int = 272) {
        self.targetWidth = width
        self.targetHeight = height
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
        let shouldTakeNewSnapshot = (cachedMapImage == nil) ||
            (now.timeIntervalSince(lastSnapshotTime) > 2.0) ||
            (lastSnapshotCoord != nil && loc.distance(from: CLLocation(latitude: lastSnapshotCoord!.latitude, longitude: lastSnapshotCoord!.longitude)) > 15.0)
        
        if shouldTakeNewSnapshot && !isSnapshotting {
            isSnapshotting = true
            
            let options = MKMapSnapshotter.Options()
            // Tỷ lệ khung hình 480 x 272
            options.size = CGSize(width: targetWidth, height: targetHeight)
            options.region = MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 550, longitudinalMeters: 550)
            options.mapType = .standard
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark) // Giao diện tối chuyên nghiệp cho xe
            
            let snapshotter = MKMapSnapshotter(options: options)
            snapshotter.start { [weak self] snapshot, error in
                guard let self = self else { return }
                self.isSnapshotting = false
                
                if let snap = snapshot {
                    self.cachedMapImage = snap.image
                    self.lastSnapshotCoord = loc.coordinate
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
            // Tái sử dụng bản đồ đã cache để vẽ HUD tốc độ/mũi tên mượt mà tức thì
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
        
        // 1. Nền bản đồ thực tế
        if let map = mapImage {
            map.draw(in: CGRect(origin: .zero, size: size))
        } else {
            ctx.setFillColor(UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            drawGridLines(in: ctx, size: size)
        }
        
        // 2. Vẽ tuyến đường dẫn đường (nếu có lộ trình)
        if let route = activeRoute {
            drawRoutePolyline(route, in: ctx, size: size, centerCoord: location.coordinate)
        }
        
        // 3. Vẽ biểu tượng vị trí xe máy ở giữa màn hình
        drawMotorcycleMarker(in: ctx, center: CGPoint(x: size.width / 2, y: size.height / 2), heading: location.course)
        
        // 4. Lớp phủ thanh trạng thái phía trên (Top HUD: Tên đường hoặc Hướng rẽ)
        drawTopNavigationBanner(in: ctx, size: size, instruction: instruction)
        
        // 5. Đồng hồ tốc độ góc dưới bên trái (Yamaha Racing Style)
        drawSpeedometerHUD(in: ctx, size: size, speedKmh: speedKmh, telemetry: telemetry)
        
        // 6. Huy hiệu Yamaha / Trạng thái góc dưới bên phải
        drawStatusBadge(in: ctx, size: size, telemetry: telemetry)
        
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        DispatchQueue.main.async {
            self.lastFrameImage = finalImage
        }
        
        // Nén JPEG chất lượng cao (yêu cầu chuẩn giao thức Yamaha StreetCross > 2048 bytes)
        return finalImage?.jpegData(compressionQuality: 0.85)
    }
    
    // MARK: - Vẽ biểu tượng xe máy trung tâm
    private func drawMotorcycleMarker(in ctx: CGContext, center: CGPoint, heading: CLLocationDirection) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        
        // Xoay theo hướng di chuyển của xe (nếu GPS có course)
        if heading >= 0 {
            let radians = CGFloat(heading * .pi / 180.0)
            ctx.rotate(by: radians)
        }
        
        // Vòng tròn hào quang phát sáng
        ctx.setFillColor(UIColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 0.25).cgColor)
        ctx.fillEllipse(in: CGRect(x: -20, y: -20, width: 40, height: 40))
        
        // Vòng tròn viền xe
        ctx.setFillColor(UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.8).cgColor)
        ctx.fillEllipse(in: CGRect(x: -10, y: -10, width: 20, height: 20))
        
        // Mũi tên định hướng xe máy
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
    
    // MARK: - Vẽ tuyến đường (Route Polyline)
    private func drawRoutePolyline(_ route: MKRoute, in ctx: CGContext, size: CGSize, centerCoord: CLLocationCoordinate2D) {
        let pointCount = route.polyline.pointCount
        guard pointCount > 1 else { return }
        
        let points = route.polyline.points()
        let path = UIBezierPath()
        var hasStarted = false
        
        // Tính độ lệch tọa độ tương đối so với tâm màn hình
        let metersPerPointX = 550.0 / Double(size.width)
        let metersPerPointY = 550.0 / Double(size.height)
        
        let centerPoint = MKMapPoint(centerCoord)
        
        for i in 0..<min(pointCount, 200) {
            let p = points[i]
            let dxMeters = p.x - centerPoint.x
            let dyMeters = p.y - centerPoint.y
            
            let screenX = size.width / 2.0 + CGFloat(dxMeters / metersPerPointX)
            let screenY = size.height / 2.0 + CGFloat(dyMeters / metersPerPointY)
            
            if screenX >= -50 && screenX <= size.width + 50 && screenY >= -50 && screenY <= size.height + 50 {
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
    
    // MARK: - Vẽ banner thông tin phía trên
    private func drawTopNavigationBanner(in ctx: CGContext, size: CGSize, instruction: NavigationInstruction) {
        let bannerRect = CGRect(x: 10, y: 8, width: size.width - 20, height: 50)
        let bannerPath = UIBezierPath(roundedRect: bannerRect, cornerRadius: 8)
        
        ctx.setFillColor(UIColor(white: 0.08, alpha: 0.88).cgColor)
        bannerPath.fill()
        
        ctx.setStrokeColor(UIColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.7).cgColor)
        ctx.setLineWidth(1.5)
        bannerPath.stroke()
        
        if instruction.isNavigating {
            // Mũi tên chỉ hướng
            let arrowSymbol = instruction.direction.iconName
            if let arrowImage = UIImage(systemName: arrowSymbol)?.withTintColor(.green, renderingMode: .alwaysOriginal) {
                arrowImage.draw(in: CGRect(x: 20, y: 16, width: 34, height: 34))
            }
            
            // Khoảng cách
            let distAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .heavy),
                .foregroundColor: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)
            ]
            instruction.formattedDistance.draw(at: CGPoint(x: 62, y: 14), withAttributes: distAttrs)
            
            // Tên đường kế tiếp
            let roadAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let roadName = instruction.nextRoadName.isEmpty ? "Đang đi theo lộ trình" : instruction.nextRoadName
            roadName.draw(at: CGPoint(x: 62, y: 34), withAttributes: roadAttrs)
        } else {
            // Chế độ xem bản đồ tự do
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
            ]
            "BẢN ĐỒ DẪN ĐƯỜNG YAMAHA".draw(at: CGPoint(x: 22, y: 14), withAttributes: titleAttrs)
            
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.lightGray
            ]
            "NConnect Live Map • Chọn điểm đến để dẫn đường".draw(at: CGPoint(x: 22, y: 34), withAttributes: subAttrs)
        }
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
        
        drawSpeedometerHUD(in: ctx, size: size, speedKmh: speedKmh, telemetry: telemetry)
        drawStatusBadge(in: ctx, size: size, telemetry: telemetry)
        
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        DispatchQueue.main.async {
            self.lastFrameImage = img
        }
        
        return img?.jpegData(compressionQuality: 0.85)
    }
}
