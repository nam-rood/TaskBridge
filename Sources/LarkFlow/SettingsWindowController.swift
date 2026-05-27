import SwiftUI
import AppKit

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {}

    func show() {
        if let window {
            present(window)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LarkFlow 偏好设置"
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 520, height: 360))
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        centerOnMainScreen(window)
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            self.centerOnMainScreen(window)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func centerOnMainScreen(_ window: NSWindow) {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            window.center()
            return
        }

        let windowFrame = window.frame
        let origin = NSPoint(
            x: screenFrame.midX - windowFrame.width / 2,
            y: screenFrame.midY - windowFrame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              let currentWindow = window,
              closingWindow === currentWindow else {
            return
        }

        window = nil
    }
}
