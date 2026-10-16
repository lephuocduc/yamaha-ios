import SwiftUI
import MapKit

public struct LiveNavigationView: View {
    @ObservedObject var navEngine: NavigationEngine
    @ObservedObject var ccuManager: YamahaCCUManager
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009), // TP.HCM
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    public init(navEngine: NavigationEngine, ccuManager: YamahaCCUManager) {
        self.navEngine = navEngine
        self.ccuManager = ccuManager
    }
    
    public var body: some View {
        ZStack {
            // Bản đồ nền
            Map(coordinateRegion: $region, showsUserLocation: true)
                .ignoresSafeArea()
            
            VStack {
                // Card Turn-by-Turn phía trên (HUD)
                if navEngine.isNavigating {
                    turnByTurnHUD
                        .padding(.top, 10)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Thanh điều khiển dưới cùng
                bottomControls
                    .padding()
            }
        }
        .onReceive(navEngine.$currentLocation) { loc in
            if let loc = loc {
                withAnimation {
                    region.center = loc.coordinate
                }
            }
        }
    }
    
    private var turnByTurnHUD: some View {
        HStack(spacing: 16) {
            Image(systemName: navEngine.currentInstruction.direction.iconName)
                .font(.system(size: 38, weight: .bold))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(navEngine.currentInstruction.formattedDistance)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text(navEngine.currentInstruction.nextRoadName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Tốc độ hiện tại
            VStack {
                let speed = ccuManager.telemetry.speedKmh > 0 ? ccuManager.telemetry.speedKmh : navEngine.currentSpeedKmh
                Text("\(Int(speed))")
                    .font(.title.bold())
                    .foregroundColor(.white)
                Text("km/h")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.95))
        .cornerRadius(16)
        .shadow(radius: 8)
    }
    
    private var bottomControls: some View {
        HStack {
            if navEngine.isNavigating {
                Button(action: {
                    navEngine.stopNavigation()
                }) {
                    Label("Dừng dẫn đường", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(14)
                }
            } else {
                Text("Chưa bắt đầu lộ trình")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.15))
                    .cornerRadius(14)
            }
        }
    }
}
