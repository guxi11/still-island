import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("隐私政策")
                    .font(.largeTitle)
                    .bold()
                
                Text("最后更新日期：2026年1月29日")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Group {
                    Text("1. 数据收集与存储")
                        .font(.headline)
                    Text("Porthole 非常重视您的隐私。我们不收集、不存储、也不上传您的任何个人数据。所有的使用统计数据、设置偏好均仅存储在您的设备本地。")
                }
                
                Group {
                    Text("2. 相机权限")
                        .font(.headline)
                    Text("Porthole 的“真实连接”功能需要使用您的相机权限，以便在画中画窗口中显示实时画面。")
                    Text("• 相机数据仅用于实时显示，不会被录制、保存或上传到任何服务器。")
                    Text("• 您可以随时在系统设置中关闭相机权限。")
                }
                
                Group {
                    Text("3. 画中画功能")
                        .font(.headline)
                    Text("应用使用 iOS 的画中画（Picture-in-Picture）技术来悬浮显示内容。此功能仅用于显示您选择的内容（如时钟、番茄钟、猫咪动画或相机画面），不会监控您的其他屏幕活动。")
                }
                
                Group {
                    Text("4. 使用统计")
                        .font(.headline)
                    Text("应用内的统计功能（如专注时长、回归生活次数）仅基于本地记录的数据生成，用于帮助您了解自己的数字生活习惯。这些数据完全私有，不会与第三方共享。")
                }
                
                Group {
                    Text("5. 联系我们")
                        .font(.headline)
                    Text("如果您对本隐私政策有任何疑问，请通过 App Store 支持页面联系我们。")
                }
            }
            .padding()
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
