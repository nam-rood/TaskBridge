import SwiftUI

struct SettingsView: View {
    // 使用 AppStorage 自动绑定 UserDefaults
    @AppStorage("feishuAppId") private var appId: String = ""
    @AppStorage("feishuAppSecret") private var appSecret: String = ""

    var body: some View {
        Form {
            Section(header: Text("飞书开放平台配置").font(.headline)) {
                TextField("App ID:", text: $appId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .help("在飞书开发者后台获取的 App ID (通常以 cli_ 开头)")

                SecureField("App Secret:", text: $appSecret)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .help("在飞书开发者后台获取的 App Secret")

                Text("请确保在飞书后台将 http://127.0.0.1:8080/callback 添加到重定向 URL 白名单中。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 10)

            HStack {
                Spacer()
                Button("关闭") {
                    // 关闭当前窗口
                    NSApplication.shared.keyWindow?.close()
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}