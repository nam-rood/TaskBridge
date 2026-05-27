import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("feishuAppId") private var appId: String = ""
    @AppStorage("feishuAppSecret") private var appSecret: String = ""

    private let callbackURL = "http://127.0.0.1:21016/callback"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 14) {
                credentialsSection
                callbackSection
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(22)
        .frame(width: 520, height: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text("偏好设置")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("配置飞书开放平台应用，用于任务同步授权")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var credentialsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                SettingsField(
                    title: "App ID",
                    help: "在飞书开发者后台获取，通常以 cli_ 开头"
                ) {
                    TextField("cli_xxxxxxxxxxxxxxxx", text: $appId)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsField(
                    title: "App Secret",
                    help: "请妥善保管，不要提交到代码仓库"
                ) {
                    SecureField("输入 App Secret", text: $appSecret)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("飞书开放平台配置", systemImage: "lock.rectangle")
                .font(.headline)
        }
    }

    private var callbackSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("请在飞书开发者后台的安全设置中，将下面的地址加入重定向 URL 白名单。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(callbackURL)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(callbackURL, forType: .string)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("授权回调地址", systemImage: "link")
                .font(.headline)
        }
    }

    private var footer: some View {
        HStack {
            Label(statusText, systemImage: isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(isConfigured ? .green : .orange)

            Spacer()

            Button("关闭") {
                NSApplication.shared.keyWindow?.performClose(nil)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var isConfigured: Bool {
        !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !appSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusText: String {
        isConfigured ? "飞书配置已填写" : "请填写 App ID 和 App Secret"
    }
}

private struct SettingsField<Content: View>: View {
    let title: String
    let help: String
    let content: Content

    init(title: String, help: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.content = content()
    }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 86, alignment: .trailing)

                content
            }

            GridRow {
                Color.clear
                    .frame(width: 86, height: 0)

                Text(help)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
