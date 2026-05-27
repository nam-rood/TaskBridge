import SwiftUI
import AppKit
import UserNotifications

struct MenuBarContentView: View {
    @StateObject private var eventKitManager = EventKitManager.shared
    @State private var isFeishuAuthorized = FeishuAPIClient.shared.userAccessToken != nil
    @State private var isLoggingIn = false
    @State private var syncState: SyncActionState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            MenuSection("状态") {
                StatusPill(
                    title: "提醒事项",
                    message: eventKitManager.isAuthorized ? "已授权，可以同步 Apple Reminders" : "需要授权后才能同步",
                    color: eventKitManager.isAuthorized ? .green : .orange,
                    systemImage: eventKitManager.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )

                StatusPill(
                    title: "飞书账号",
                    message: isFeishuAuthorized ? "已登录，可以访问飞书任务" : "需要登录飞书账号",
                    color: isFeishuAuthorized ? .green : .orange,
                    systemImage: isFeishuAuthorized ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark"
                )
            }

            MenuSection("操作") {
                if !eventKitManager.isAuthorized {
                    Button("授权提醒事项访问") {
                        requestReminderAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isFeishuAuthorized {
                    Button("退出飞书登录", role: .destructive) {
                        logoutFromFeishu()
                    }
                } else {
                    Button(isLoggingIn ? "正在打开浏览器..." : "飞书授权登录") {
                        loginToFeishu()
                    }
                    .disabled(isLoggingIn)
                }

                Button(syncState == .running ? "同步中..." : "立即同步") {
                    performSync()
                }
                .disabled(syncState == .running)
            }

            if let syncMessage = syncState.message {
                StatusPill(
                    title: syncState.title,
                    message: syncMessage,
                    color: syncState.color,
                    systemImage: syncState.systemImage
                )
            }

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 220)
        .onAppear(perform: refreshStatus)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("LarkFlow")
                    .font(.headline)
                Text("飞书任务与提醒事项同步")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .help("偏好设置")

            Spacer()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func refreshStatus() {
        eventKitManager.checkAuthorizationStatus()
        isFeishuAuthorized = FeishuAPIClient.shared.userAccessToken != nil
    }

    private func requestReminderAccess() {
        eventKitManager.requestAccess { granted in
            if granted {
                (NSApp.delegate as? AppDelegate)?.startSyncIfReady(triggerImmediateSync: true)
            }
        }
    }

    private func loginToFeishu() {
        isLoggingIn = true
        FeishuOAuthManager.shared.startLogin { result in
            DispatchQueue.main.async {
                isLoggingIn = false

                switch result {
                case .success:
                    isFeishuAuthorized = true
                    syncState = .idle
                    NSApp.activate(ignoringOtherApps: true)
                    (NSApp.delegate as? AppDelegate)?.startSyncIfReady(triggerImmediateSync: true)
                case .failure(let error):
                    syncState = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func logoutFromFeishu() {
        FeishuAPIClient.shared.clearAuthorizationState()
        SyncEngine.shared.stopAutomaticSync()
        isFeishuAuthorized = false
        syncState = .idle
    }

    private func performSync() {
        syncState = .running
        SyncEngine.shared.syncBidirectionally { success, message in
            DispatchQueue.main.async {
                syncState = success ? .success(message) : .failure(message)
                deliverSyncNotification(success: success, message: message)
            }
        }
    }

    private func deliverSyncNotification(success: Bool, message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = success ? "同步成功" : "同步失败"
            content.body = message

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}

private enum SyncActionState: Equatable {
    case idle
    case running
    case success(String)
    case failure(String)

    var title: String {
        switch self {
        case .idle:
            return "同步状态"
        case .running:
            return "正在同步"
        case .success:
            return "同步成功"
        case .failure:
            return "同步失败"
        }
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .running:
            return "正在同步飞书任务与 Apple Reminders"
        case .success(let message), .failure(let message):
            return message
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "circle"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        }
    }
}

private struct MenuSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            content
        }
    }
}

private struct StatusPill: View {
    let title: String
    let message: String
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
