import SwiftUI
import AppKit

@main
struct VoiceCloneMemoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var voiceManager = VoiceManager()
    var localServer: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.badge.plus", accessibilityDescription: "Voice Clone Memo")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainView(voiceManager: voiceManager))

        // Auto-start local server if installed
        startLocalServerIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        localServer?.terminate()
    }

    func startLocalServerIfNeeded() {
        let startScript = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voiceclonememo/start.sh")

        guard FileManager.default.fileExists(atPath: startScript.path) else { return }

        // Check if server is already running
        if let url = URL(string: "http://localhost:5123/health") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 1
            let semaphore = DispatchSemaphore(value: 0)
            var isRunning = false
            URLSession.shared.dataTask(with: request) { data, _, _ in
                isRunning = data != nil
                semaphore.signal()
            }.resume()
            semaphore.wait()
            if isRunning { return }
        }

        // Start server in background
        DispatchQueue.global().async { [weak self] in
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = [startScript.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            self?.localServer = task
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
