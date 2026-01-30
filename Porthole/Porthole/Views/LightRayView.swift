import SwiftUI

struct LightRayView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Core Beam - Intense, Holy Light
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    
                    // Start from top-left corner, slightly inside
                    path.move(to: CGPoint(x: 0, y: 0))
                    // Wide beam extending to bottom-right
                    path.addLine(to: CGPoint(x: width * 1.5, y: height * 1.5))
                    path.addLine(to: CGPoint(x: width * 0.8, y: height * 1.5))
                    // Back to top-left
                    path.addLine(to: CGPoint(x: 0, y: height * 0.1))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1.0, green: 0.98, blue: 0.9).opacity(0.7), // Very bright, almost white-gold
                            Color(red: 1.0, green: 0.9, blue: 0.6).opacity(0.4),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 30)
                
                // 2. Secondary Wide Beam - Atmospheric Volume
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: width * 2.0, y: height * 1.2))
                    path.addLine(to: CGPoint(x: width * 0.4, y: height * 1.2))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1.0, green: 0.9, blue: 0.5).opacity(0.4), // Warm gold
                            Color(red: 1.0, green: 0.8, blue: 0.3).opacity(0.15),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottom
                    )
                )
                .blur(radius: 50)
                
                // 3. Ambient Holy Glow - Top Left
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.95, blue: 0.8).opacity(0.5),
                        Color(red: 1.0, green: 0.9, blue: 0.6).opacity(0.2),
                        Color.clear
                    ]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.8
                )
                .blendMode(.plusLighter) // Additive blend for "holy" feel
                
                // 4. Subtle God Rays (Fan shape)
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: width * 1.2, y: height))
                    path.addLine(to: CGPoint(x: width * 1.0, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 20)
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.black
        LightRayView()
    }
}
