import Foundation
import AppKit

class AutoUpdater: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String = ""
    @Published var isUpdating = false
    @Published var updateStatus: String = ""
    @Published var updateError: String?
    @Published var isChecking = false

    let currentVersion = "5.1.0"
    private let repoOwner = "Real-Pixeldrop"
    private let repoName = "voice-clone-memo"

    init() {
        // Delay check to let the UI load first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkForUpdates()
        }
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
                self.isChecking = false
                if self.compareVersions(remoteVersion, isNewerThan: self.currentVersion) {
                    self.updateAvailable = true
                }
            }
        }.resume()
    }

    func performUpdate() {
        isUpdating = true
        updateError = nil
        updateStatus = "Téléchargement en cours..."

        let zipURLString = "https://github.com/\(repoOwner)/\(repoName)/releases/latest/download/VoiceCloneMemo.zip"
        guard let zipURL = URL(string: zipURLString) else {
            failUpdate("URL invalide")
            return
        }

        // Use URLSession to download (more reliable than shell curl)
        let downloadTask = URLSession.shared.downloadTask(with: zipURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                self.failUpdate("Erreur téléchargement : \(error.localizedDescription)")
                return
            }

            guard let tempURL = tempURL else {
                self.failUpdate("Fichier téléchargé introuvable")
                return
            }

            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                self.failUpdate("Erreur serveur (HTTP \(httpResponse.statusCode))")
                return
            }

            self.updateUI("Installation...")

            // Copy to /tmp for processing
            let tmpZip = URL(fileURLWithPath: "/tmp/vcm_update.zip")
            try? FileManager.default.removeItem(at: tmpZip)
            do {
                try FileManager.default.copyItem(at: tempURL, to: tmpZip)
            } catch {
                self.failUpdate("Erreur copie : \(error.localizedDescription)")
                return
            }

            // Determine install directory
            let appPath = Bundle.main.bundlePath
            let installDir: String
            if appPath.hasPrefix("/Applications") {
                installDir = "/Applications"
            } else {
                installDir = (appPath as NSString).deletingLastPathComponent
            }

            // Unzip
            let unzipTask = Process()
            unzipTask.launchPath = "/usr/bin/unzip"
            unzipTask.arguments = ["-o", tmpZip.path, "-d", installDir]
            unzipTask.standardOutput = FileHandle.nullDevice
            unzipTask.standardError = Pipe()

            do {
                try unzipTask.run()
                unzipTask.waitUntilExit()
            } catch {
                self.failUpdate("Erreur décompression : \(error.localizedDescription)")
                return
            }

            if unzipTask.terminationStatus != 0 {
                // Read stderr for details
                if let errPipe = unzipTask.standardError as? Pipe {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "inconnue"
                    self.failUpdate("Erreur unzip (\(unzipTask.terminationStatus)): \(errStr)")
                } else {
                    self.failUpdate("Erreur unzip (code \(unzipTask.terminationStatus))")
                }
                return
            }

            // Clear quarantine
            let xattrTask = Process()
            xattrTask.launchPath = "/usr/bin/xattr"
            xattrTask.arguments = ["-cr", "\(installDir)/VoiceCloneMemo.app"]
            xattrTask.standardOutput = FileHandle.nullDevice
            xattrTask.standardError = FileHandle.nullDevice
            try? xattrTask.run()
            xattrTask.waitUntilExit()

            // Clean up
            try? FileManager.default.removeItem(at: tmpZip)

            self.updateUI("Redémarrage...")

            // Relaunch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let appURL = URL(fileURLWithPath: "\(installDir)/VoiceCloneMemo.app")

                // Use open command (most reliable way to relaunch)
                let openTask = Process()
                openTask.launchPath = "/usr/bin/open"
                openTask.arguments = ["-n", appURL.path]
                try? openTask.run()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    NSApp.terminate(nil)
                }
            }
        }

        downloadTask.resume()
    }

    private func failUpdate(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.updateError = message
            self?.updateStatus = ""
            self?.isUpdating = false
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
}
