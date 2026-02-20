import SwiftUI
import AppKit
import AVFoundation
import Combine

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
    var setupManager = SetupManager()
    var autoUpdater = AutoUpdater()
    var localServer: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Request microphone permission at launch (not when clicking record)
        // This prevents the permission dialog from closing the popover
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.badge.plus", accessibilityDescription: "Voice Clone Memo")
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        updatePopoverContent()

        // Watch for setup completion to switch views
        setupManager.$isComplete.receive(on: DispatchQueue.main).sink { [weak self] complete in
            guard let self = self else { return }
            if complete {
                self.updatePopoverContent()
                self.startLocalServerIfNeeded()
            }
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func updatePopoverContent() {
        if setupManager.isSetupNeeded {
            popover.contentViewController = NSHostingController(
                rootView: SetupView(setupManager: setupManager)
            )
        } else {
            popover.contentViewController = NSHostingController(
                rootView: MainView(voiceManager: voiceManager, autoUpdater: autoUpdater)
            )
        }
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
        let event = NSApp.currentEvent

        // Right-click → context menu
        if event?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quitter Voice Clone Memo", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            button.performClick(nil)
            // Reset menu so left-click opens popover again
            DispatchQueue.main.async { self.statusItem.menu = nil }
            return
        }

        // Left-click → popover
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func quitApp() {
        localServer?.terminate()
        NSApp.terminate(nil)
    }
}
