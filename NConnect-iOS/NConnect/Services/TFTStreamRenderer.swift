import Foundation
import UIKit
import CoreGraphics

// MARK: - Renderer tạo khung hình ảnh tối ưu cho màn hình TFT xe máy Yamaha
public final class TFTStreamRenderer {
    
    // Kích thước chuẩn cho màn hình TFT (Yamaha XMAX / NMAX 4.2-inch)
    public var targetWidth: Int = 480
    public var targetHeight: Int = 272
    
    public init(width: Int = 480, height: Int = 272) {
        self.targetWidth = width
        self.targetHeight = height
    }
    
    // MARK: - Render một khung hình đồ họa dẫn đường cho đồng hồ TFT
    public func renderNavigationFrame(
        instruction: NavigationInstruction,
        telemetry: BikeTelemetry,
        mapSnapshot: UIImage? = nil
    ) -> Data? {
        let size = CGSize(width: targetWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // 1. Nền màn hình TFT (Màu đen sâu tương phản cao để nhìn rõ dưới trời nắng)
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        
        // 2. Vẽ hình bản đồ (nếu có snapshot)
        if let map = mapSnapshot {
            map.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            
            // Lớp phủ mờ (vignette/dim) để làm nổi bật thông tin tốc độ và mũi tên
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.4).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        } else {
            // Nền đồ họa vector giả lập cung đường
            drawVectorBackground(in: ctx, size: size)
        }
        
        // 3. Khung dẫn đường Turn-by-Turn phía trên (HUD Card)
        let hudRect = CGRect(x: 12, y: 10, width: size.width - 24, height: 75)
        let hudPath = UIBezierPath(roundedRect: hudRect, cornerRadius: 10)
        ctx.setFillColor(UIColor(white: 0.12, alpha: 0.9).cgColor)
        hudPath.fill()
        
        // Viền xanh Yamaha Racing Blue
        ctx.setStrokeColor(UIColor(red: 0.0, green: 0.45, blue: 0.95, alpha: 1.0).cgColor)
        ctx.setLineWidth(2.0)
        hudPath.stroke()
        
        // Mũi tên chỉ hướng
        let arrowSymbol = instruction.direction.iconName
        if let arrowImage = UIImage(systemName: arrowSymbol)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            arrowImage.draw(in: CGRect(x: 24, y: 22, width: 48, height: 48))
        }
        
        // Khoảng cách tới ngã rẽ (Font to, rõ ràng)
        let distText = instruction.formattedDistance
        let distAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0) // Màu xanh lá dạ quang
        ]
        distText.draw(at: CGPoint(x: 88, y: 18), withAttributes: distAttrs)
        
        // Tên đường sắp tới
        let roadText = instruction.nextRoadName.isEmpty ? "Đang đi theo lộ trình" : instruction.nextRoadName
        let roadAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: UIColor.white
        ]
        roadText.draw(at: CGPoint(x: 88, y: 48), withAttributes: roadAttrs)
        
        // 4. Thanh trạng thái phía dưới (Tốc độ km/h & Xăng)
        let speedText = String(format: "%.0f", telemetry.speedKmh)
        let speedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
            .foregroundColor: UIColor.white
        ]
        speedText.draw(at: CGPoint(x: 24, y: size.height - 65), withAttributes: speedAttrs)
        
        let kmhAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.lightGray
        ]
        "KM/H".draw(at: CGPoint(x: 80, y: size.height - 40), withAttributes: kmhAttrs)
        
        // Mức xăng
        let fuelText = "⛽ \(telemetry.fuelPercent)%"
        let fuelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: telemetry.fuelPercent > 20 ? UIColor.white : UIColor.systemRed
        ]
        fuelText.draw(at: CGPoint(x: size.width - 95, y: size.height - 40), withAttributes: fuelAttrs)
        
        // Lấy UIImage và nén JPEG
        let renderedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Nén định dạng JPEG chất lượng cao (nconnect protocol yêu cầu kích thước > 2048 bytes)
        return renderedImage?.jpegData(compressionQuality: 0.85)
    }
    
    private func drawVectorBackground(in ctx: CGContext, size: CGSize) {
        // Vẽ cung đường 3D tượng trưng
        ctx.setStrokeColor(UIColor(white: 0.3, alpha: 0.5).cgColor)
        ctx.setLineWidth(40.0)
        ctx.move(to: CGPoint(x: size.width / 2, y: size.height))
        ctx.addCurve(
            to: CGPoint(x: size.width * 0.65, y: size.height * 0.45),
            control1: CGPoint(x: size.width / 2, y: size.height * 0.75),
            control2: CGPoint(x: size.width * 0.6, y: size.height * 0.6)
        )
        ctx.strokePath()
        
        // Vạch dẫn đường màu xanh Yamaha sáng
        ctx.setStrokeColor(UIColor(red: 0.0, green: 0.55, blue: 1.0, alpha: 0.9).cgColor)
        ctx.setLineWidth(16.0)
        ctx.move(to: CGPoint(x: size.width / 2, y: size.height))
        ctx.addCurve(
            to: CGPoint(x: size.width * 0.65, y: size.height * 0.45),
            control1: CGPoint(x: size.width / 2, y: size.height * 0.75),
            control2: CGPoint(x: size.width * 0.6, y: size.height * 0.6)
        )
        ctx.strokePath()
    }
}
