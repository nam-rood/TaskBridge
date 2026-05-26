import SwiftUI
import EventKit

@main
struct LarkFlowApp: App {
    // 使用 NSApplicationDelegateAdaptor 来处理一些传统的 AppDelegate 事件（如果需要）
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 使用 MenuBarExtra 创建菜单栏应用
        MenuBarExtra("LarkFlow", systemImage: "arrow.triangle.2.circlepath") {
            ContentView()
        }
        // 隐藏 Dock 图标，使其成为纯粹的后台/菜单栏应用
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        print("LarkFlow Agent Started!")

        // 初始化数据库
        _ = DatabaseManager.shared

        // TODO: 请求 EventKit 权限
        // TODO: 启动定时轮询任务
    }
}

struct ContentView: View {
    @StateObject private var eventKitManager = EventKitManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("LarkFlow")
                .font(.headline)

            if !eventKitManager.isAuthorized {
                Text("需要提醒事项权限")
                    .font(.caption)
                    .foregroundColor(.red)

                Button("授权访问") {
                    eventKitManager.requestAccess { granted in
                        print("授权结果: \(granted)")
                    }
                }
            } else {
                Text("权限已就绪")
                    .font(.caption)
                    .foregroundColor(.green)

                Button("创建测试任务") {
                    eventKitManager.createTestReminder(title: "来自 LarkFlow 的测试任务 - \(Date().formatted(date: .omitted, time: .standard))")
                }
            }

                if FeishuAPIClient.shared.userAccessToken == nil {
                    Button("飞书授权登录") {
                        print("正在拉起浏览器进行飞书授权...")
                        FeishuOAuthManager.shared.startLogin { result in
                            switch result {
                            case .success(let token):
                                print("🎉 授权成功！拿到 User Access Token: \(token)")
                                // 强制刷新 UI
                                DispatchQueue.main.async {
                                    NSApp.activate(ignoringOtherApps: true)
                                }
                            case .failure(let error):
                                print("❌ 授权失败: \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    Text("飞书已授权 ✅")
                        .font(.caption)
                        .foregroundColor(.green)

                    Button("退出登录") {
                        FeishuAPIClient.shared.userAccessToken = nil
                    }
                }

                Button("立即同步") {
                    print("手动触发同步...")
                    SyncEngine.shared.syncFeishuToApple { success, message in
                        print(message)
                        // 同步完成后弹个通知告诉主人
                        let notification = NSUserNotification()
                        notification.title = success ? "同步成功" : "同步失败"
                        notification.informativeText = message
                        NSUserNotificationCenter.default.deliver(notification)
                    }
                }

                Button("偏好设置...") {
                    print("打开设置...")
                    openSettingsWindow()
                }

                Divider()

            Button("退出 LarkFlow") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 200)
    }

    // 打开独立的设置窗口
    private func openSettingsWindow() {
        // 检查是否已经有设置窗口打开了
        for window in NSApplication.shared.windows {
            if window.title == "LarkFlow 偏好设置" {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        // 创建新的设置窗口
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LarkFlow 偏好设置"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}