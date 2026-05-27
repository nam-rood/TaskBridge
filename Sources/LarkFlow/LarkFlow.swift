import SwiftUI
import AppKit

@main
struct LarkFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("LarkFlow", systemImage: "arrow.triangle.2.circlepath") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var readinessRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        print("LarkFlow Agent Started!")

        _ = DatabaseManager.shared
        _ = AppleToFeishuSync.shared

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        startSyncIfReady(triggerImmediateSync: true)
    }

    @objc private func handleWake() {
        startSyncIfReady(triggerImmediateSync: true)
    }

    func startSyncIfReady(triggerImmediateSync: Bool) {
        EventKitManager.shared.checkAuthorizationStatus()

        let defaults = UserDefaults.standard
        let formatter = ISO8601DateFormatter()
        defaults.set(formatter.string(from: Date()), forKey: "debugLastStartSyncCheckAt")
        defaults.set(EventKitManager.shared.isAuthorized, forKey: "debugLastStartSyncAuthorized")
        defaults.set(FeishuAPIClient.shared.userAccessToken != nil, forKey: "debugLastStartSyncHasToken")
        defaults.set(triggerImmediateSync, forKey: "debugLastStartSyncImmediate")

        guard EventKitManager.shared.isAuthorized,
              FeishuAPIClient.shared.userAccessToken != nil else {
            defaults.set("not_ready", forKey: "debugLastStartSyncResult")
            SyncEngine.shared.stopAutomaticSync()

            scheduleReadinessRetryIfNeeded()
            return
        }

        defaults.set("ready", forKey: "debugLastStartSyncResult")
        readinessRetryTimer?.invalidate()
        readinessRetryTimer = nil

        SyncEngine.shared.startAutomaticSync()
        if triggerImmediateSync {
            SyncEngine.shared.syncBidirectionally { success, message in
                print(success ? "同步完成：\(message)" : "同步失败：\(message)")
            }
        }
    }

    private func scheduleReadinessRetryIfNeeded() {
        guard readinessRetryTimer == nil else { return }

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            EventKitManager.shared.checkAuthorizationStatus()
            if EventKitManager.shared.isAuthorized,
               FeishuAPIClient.shared.userAccessToken != nil {
                timer.invalidate()
                self.readinessRetryTimer = nil
                self.startSyncIfReady(triggerImmediateSync: true)
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        readinessRetryTimer = timer
    }
}
