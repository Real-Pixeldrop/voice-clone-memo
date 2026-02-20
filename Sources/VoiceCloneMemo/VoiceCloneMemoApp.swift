import SwiftUI
import AppKit
import AVFoundation
import UserNotifications
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

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
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

        // Request notification permission
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }

        // Register notification actions
        let listenAction = UNNotificationAction(identifier: "LISTEN", title: "Écouter", options: [.foreground])
        let retryAction = UNNotificationAction(identifier: "RETRY", title: "Réessayer", options: [.foreground])
        let successCategory = UNNotificationCategory(identifier: "TTS_SUCCESS", actions: [listenAction], intentIdentifiers: [])
        let errorCategory = UNNotificationCategory(identifier: "TTS_ERROR", actions: [retryAction], intentIdentifiers: [])
        center.setNotificationCategories([successCategory, errorCategory])

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

        // Watch for generation completion to send notifications
        voiceManager.$lastGeneratedURL.receive(on: DispatchQueue.main).sink { [weak self] url in
            guard let self = self, url != nil else { return }
            self.sendSuccessNotification()
        }.store(in: &cancellables)

        voiceManager.$lastError.receive(on: DispatchQueue.main).sink { [weak self] error in
            guard let self = self, let error = error else { return }
            self.sendErrorNotification(message: error)
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Notifications

    func sendSuccessNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Mémo vocal prêt"
        content.body = "Ta génération audio est terminée."
        content.sound = .default
        content.categoryIdentifier = "TTS_SUCCESS"

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func sendErrorNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Génération échouée"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = "TTS_ERROR"

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground (popover might be closed)
        completionHandler([.banner, .sound])
    }

    // Handle notification action tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "LISTEN":
            // Open popover to show player
            if let button = statusItem.button {
                if !popover.isShown {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        case "RETRY":
            // Open popover so user can retry
            if let button = statusItem.button {
                if !popover.isShown {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        default:
            // Default tap: open popover
            if let button = statusItem.button {
                if !popover.isShown {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        completionHandler()
    }

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
