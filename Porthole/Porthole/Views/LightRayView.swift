import SwiftUI

/// 模拟从左上角PiP舷窗射入的丁达尔光束效果
/// 光源在屏幕外（如月光/路灯），透过舷窗投射出矩形光面
struct LightRayView: View {
    // 假设的PiP窗口位置和尺寸（左上角）
    private let pipOrigin = CGPoint(x: 20, y: 60)
    private let pipSize = CGSize(width: 150, height: 100)
    
    // 光源位置（屏幕外左上方，调整角度使光束射向右下角）
    private let lightSource = CGPoint(x: -100, y: -300)
    
    // 从光源穿过某点，延伸指定距离
    private func extendRay(from source: CGPoint, through point: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = point.x - source.x
        let dy = point.y - source.y
        let length = sqrt(dx * dx + dy * dy)
        let scale = distance / length
        return CGPoint(x: source.x + dx * scale, y: source.y + dy * scale)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            // 舷窗四个角
            let pipTopLeft = pipOrigin
            let pipTopRight = CGPoint(x: pipOrigin.x + pipSize.width, y: pipOrigin.y)
            let pipBottomLeft = CGPoint(x: pipOrigin.x, y: pipOrigin.y + pipSize.height)
            let pipBottomRight = CGPoint(x: pipOrigin.x + pipSize.width, y: pipOrigin.y + pipSize.height)
            
            let extendDist: CGFloat = max(width, height) * 2
            let farTopRight = extendRay(from: lightSource, through: pipTopRight, distance: extendDist)
            let farBottomRight = extendRay(from: lightSource, through: pipBottomRight, distance: extendDist)
            let farBottomLeft = extendRay(from: lightSource, through: pipBottomLeft, distance: extendDist)
            
            ZStack {
                // 1. 主光束体积 - 从舷窗投射出的梯形光面
                Canvas { context, size in
                    let mainBeam = Path { path in
                        path.move(to: pipTopRight)
                        path.addLine(to: farTopRight)
                        path.addLine(to: farBottomRight)
                        path.addLine(to: farBottomLeft)
                        path.addLine(to: pipBottomLeft)
                        path.addLine(to: pipBottomRight)
                        path.closeSubpath()
                    }
                    
                    context.fill(
                        mainBeam,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color(red: 1.0, green: 0.95, blue: 0.4, opacity: 0.22),
                                Color(red: 1.0, green: 0.9, blue: 0.3, opacity: 0.08),
                                Color.clear
                            ]),
                            startPoint: pipBottomRight,
                            endPoint: CGPoint(x: width, y: height)
                        )
                    )
                    
                    // 2. 光束核心 - 更亮的中心区域
                    let pipCenterRight = CGPoint(x: pipBottomRight.x, y: pipOrigin.y + pipSize.height * 0.5)
                    let pipCenterBottom = CGPoint(x: pipOrigin.x + pipSize.width * 0.5, y: pipBottomRight.y)
                    let farCenterRight = extendRay(from: lightSource, through: pipCenterRight, distance: extendDist)
                    let farCenterBottom = extendRay(from: lightSource, through: pipCenterBottom, distance: extendDist)
                    
                    let coreBeam = Path { path in
                        path.move(to: pipCenterRight)
                        path.addLine(to: farCenterRight)
                        path.addLine(to: farBottomRight)
                        path.addLine(to: farCenterBottom)
                        path.addLine(to: pipCenterBottom)
                        path.addLine(to: pipBottomRight)
                        path.closeSubpath()
                    }
                    
                    context.fill(
                        coreBeam,
                        with: .linearGradient(
                            Gradient(colors: [
                                Color(red: 1.0, green: 0.95, blue: 0.5, opacity: 0.15),
                                Color(red: 1.0, green: 0.9, blue: 0.4, opacity: 0.04),
                                Color.clear
                            ]),
                            startPoint: pipBottomRight,
                            endPoint: CGPoint(x: width, y: height)
                        )
                    )
                }
                .blur(radius: 30)
                
                // 3. 舷窗边缘的光晕 - 光线在窗框处的散射
                Canvas { context, size in
                    let inset: CGFloat = -8
                    let outset: CGFloat = 12
                    let edgeGlow = Path { path in
                        path.move(to: CGPoint(x: pipTopRight.x + inset, y: pipTopRight.y))
                        path.addLine(to: CGPoint(x: pipTopRight.x + outset, y: pipTopRight.y + outset))
                        path.addLine(to: CGPoint(x: pipBottomRight.x + outset, y: pipBottomRight.y + outset))
                        path.addLine(to: CGPoint(x: pipBottomLeft.x + outset, y: pipBottomLeft.y + outset))
                        path.addLine(to: CGPoint(x: pipBottomLeft.x, y: pipBottomLeft.y + inset))
                        path.addLine(to: CGPoint(x: pipBottomLeft.x, y: pipBottomLeft.y))
                        path.addLine(to: CGPoint(x: pipBottomRight.x, y: pipBottomRight.y))
                        path.addLine(to: CGPoint(x: pipTopRight.x, y: pipTopRight.y))
                        path.closeSubpath()
                    }
                    
                    context.fill(
                        edgeGlow,
                        with: .radialGradient(
                            Gradient(colors: [
                                Color(red: 1.0, green: 0.95, blue: 0.5, opacity: 0.25),
                                Color(red: 1.0, green: 0.9, blue: 0.4, opacity: 0.08),
                                Color.clear
                            ]),
                            center: pipBottomRight,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                }
                .blur(radius: 15)
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color(red: 10/255, green: 24/255, blue: 48/255)
        LightRayView()
        
        // 模拟PiP位置
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
            .frame(width: 150, height: 100)
            .position(x: 20 + 75, y: 60 + 50)
    }
    .ignoresSafeArea()
}
