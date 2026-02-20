import Foundation
import AppKit

class AutoUpdater: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String = ""
    @Published var isUpdating = false
    @Published var updateStatus: String = ""

    private let currentVersion = "4.3.0"
    private let repoOwner = "Real-Pixeldrop"
    private let repoName = "voice-clone-memo"

    init() {
        checkForUpdates()
    }

    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                return
            }

            let remoteVersion = tagName.replacingOccurrences(of: "v", with: "")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.latestVersion = remoteVersion
                if self.compareVersions(remoteVersion, isNewerThan: self.currentVersion) {
                    self.updateAvailable = true
                }
            }
        }.resume()
    }

    func performUpdate() {
        isUpdating = true
        updateStatus = "Téléchargement..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let zipURL = "https://github.com/\(self.repoOwner)/\(self.repoName)/releases/latest/download/VoiceCloneMemo.zip"
            let tmpZip = "/tmp/vcm_update.zip"
            let appPath = Bundle.main.bundlePath

            // Determine install location (use current app's parent directory)
            let installDir: String
            if appPath.hasPrefix("/Applications") {
                installDir = "/Applications"
            } else {
                installDir = (appPath as NSString).deletingLastPathComponent
            }

            // Step 1: Download
            self.updateUI("Téléchargement de la mise à jour...")
            let dl = self.shell("/usr/bin/curl -sL \(zipURL) -o \(tmpZip)")
            guard dl.status == 0 else {
                self.updateUI("Erreur de téléchargement")
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }

            // Step 2: Unzip (overwrite)
            self.updateUI("Installation...")
            let unzip = self.shell("/usr/bin/unzip -o \(tmpZip) -d \(installDir)")
            guard unzip.status == 0 else {
                self.updateUI("Erreur d'installation")
                DispatchQueue.main.async { self.isUpdating = false }
                return
            }

            // Step 3: Clear quarantine
            _ = self.shell("/usr/bin/xattr -cr \(installDir)/VoiceCloneMemo.app")

            // Step 4: Clean up
            try? FileManager.default.removeItem(atPath: tmpZip)

            self.updateUI("Redémarrage...")

            // Step 5: Relaunch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let appURL = URL(fileURLWithPath: "\(installDir)/VoiceCloneMemo.app")
                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                // Quit current instance
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func updateUI(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatus = status
        }
    }

    private func compareVersions(_ v1: String, isNewerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }

    private func shell(_ command: String) -> (status: Int32, output: String) {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, "")
        }
    }
}
