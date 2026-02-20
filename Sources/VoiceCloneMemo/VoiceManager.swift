import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import Combine

enum TTSProvider: String, Codable, CaseIterable {
    case local = "Qwen3 Local"
    case fish = "Fish Audio"
    case qwen = "Qwen3 (Alibaba)"
    case elevenLabs = "ElevenLabs"
    case openai = "OpenAI TTS"
    case system = "Voix système (macOS)"

    var needsApiKey: Bool {
        switch self {
        case .fish, .qwen, .elevenLabs, .openai: return true
        case .local, .system: return false
        }
    }

    var icon: String {
        switch self {
        case .local: return "desktopcomputer"
        case .fish: return "fish"
        case .qwen: return "brain"
        case .elevenLabs: return "waveform"
        case .openai: return "sparkles"
        case .system: return "desktopcomputer"
        }
    }

    var description: String {
        switch self {
        case .local: return "Gratuit, 100% sur ton Mac, pas besoin d'internet"
        case .fish: return "Clonage vocal gratuit (1h/mois), ultra réaliste"
        case .qwen: return "Clonage vocal, gratuit 500k tokens/mois"
        case .elevenLabs: return "Clonage vocal, très réaliste"
        case .openai: return "Voix haute qualité, pas de clone"
        case .system: return "Gratuit, hors-ligne, basique"
        }
    }
}

struct VoiceConfig: Codable {
    var provider: TTSProvider
    var fishKey: String
    var fishVoiceId: String
    var qwenKey: String
    var qwenVoiceId: String
    var elevenLabsKey: String
    var elevenLabsVoiceId: String
    var openaiKey: String
    var openaiVoice: String
    var systemVoice: String
    var localModelSize: String  // "auto", "0.6b", "1.7b"

    init() {
        self.provider = .local
        self.fishKey = ""
        self.fishVoiceId = ""
        self.qwenKey = ""
        self.qwenVoiceId = ""
        self.elevenLabsKey = ""
        self.elevenLabsVoiceId = ""
        self.openaiKey = ""
        self.openaiVoice = "alloy"
        self.systemVoice = "Thomas"
        self.localModelSize = "auto"
    }
}

enum LocalModelStatus {
    case notInstalled
    case installing
    case ready
}

class VoiceManager: ObservableObject {
    @Published var config: VoiceConfig
    @Published var voiceProfiles: [VoiceProfile] = []
    @Published var isGenerating = false
    @Published var isCloning = false
    @Published var lastGeneratedURL: URL?
    @Published var statusMessage: String = ""
    @Published var lastError: String?
    @Published var localModelStatus: LocalModelStatus = .notInstalled
    @Published var localServerRunning = false
    @Published var installProgress: Double = 0
    @Published var installStep: String = ""

    let recorder = AudioRecorder()
    private let configFile: URL
    private let profilesFile: URL
    let outputDir: URL
    private var cancellables = Set<AnyCancellable>()

    var localModelStatusText: String {
        switch localModelStatus {
        case .notInstalled: return "Qwen3-TTS non installé"
        case .installing: return "Installation en cours..."
        case .ready: return "Qwen3-TTS prêt"
        }
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("VoiceCloneMemo")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        configFile = appDir.appendingPathComponent("config.json")
        profilesFile = appDir.appendingPathComponent("profiles.json")
        outputDir = appDir.appendingPathComponent("memos")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: configFile),
           let saved = try? JSONDecoder().decode(VoiceConfig.self, from: data) {
            config = saved
        } else {
            config = VoiceConfig()
        }

        if let data = try? Data(contentsOf: profilesFile),
           let saved = try? JSONDecoder().decode([VoiceProfile].self, from: data) {
            voiceProfiles = saved
        }

        // Forward recorder changes to trigger SwiftUI view updates
        // (nested ObservableObjects don't propagate automatically)
        recorder.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }.store(in: &cancellables)

        // Check local model status on launch
        checkLocalModelStatus()
    }

    // MARK: - Local Model Status

    func checkLocalModelStatus() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let serverScript = home.appendingPathComponent(".voiceclonememo/server.py")
        let startScript = home.appendingPathComponent(".voiceclonememo/start.sh")

        // Model downloads automatically on first run via from_pretrained()
        // Just check if server script and start script exist
        if FileManager.default.fileExists(atPath: serverScript.path) &&
           FileManager.default.fileExists(atPath: startScript.path) {
            localModelStatus = .ready
            checkLocalServerStatus()
        } else {
            localModelStatus = .notInstalled
        }
    }

    func checkLocalServerStatus() {
        guard let url = URL(string: "http://localhost:5123/health") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                self?.localServerRunning = data != nil
            }
        }.resume()
    }

    func installLocalModel() {
        localModelStatus = .installing
        installProgress = 0
        installStep = "Préparation..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runLocalInstall()
        }
    }

    private func updateInstallUI(step: String, progress: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.installStep = step
            self?.installProgress = progress
        }
    }

    private func runLocalInstall() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let installDir = home.appendingPathComponent(".voiceclonememo")
        try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        // Step 1: Find or install conda
        updateInstallUI(step: "Recherche de Python/Conda...", progress: 0.05)
        let condaPaths = [
            home.appendingPathComponent("miniconda3/bin/conda").path,
            home.appendingPathComponent("anaconda3/bin/conda").path,
            home.appendingPathComponent("miniforge3/bin/conda").path,
            "/usr/local/bin/conda",
            "/opt/homebrew/bin/conda"
        ]

        var condaPath = condaPaths.first { FileManager.default.fileExists(atPath: $0) }

        if condaPath == nil {
            // Check PATH
            let which = shellRun("/usr/bin/which conda")
            if which.status == 0 {
                let path = which.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                    condaPath = path
                }
            }
        }

        if condaPath == nil {
            // Install miniconda
            updateInstallUI(step: "Téléchargement de Miniconda...", progress: 0.08)
            let arch = shellRun("/usr/bin/uname -m").output.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = arch == "arm64"
                ? "https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh"
                : "https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"

            let dl = shellRun("/usr/bin/curl -sL \(url) -o /tmp/miniconda.sh")
            guard dl.status == 0 else {
                updateInstallUI(step: "Erreur : impossible de télécharger Miniconda", progress: 0)
                DispatchQueue.main.async { self.localModelStatus = .notInstalled }
                return
            }

            updateInstallUI(step: "Installation de Miniconda...", progress: 0.12)
            let install = shellRun("/bin/bash /tmp/miniconda.sh -b -p \(home.path)/miniconda3")
            guard install.status == 0 else {
                updateInstallUI(step: "Erreur : installation Miniconda échouée", progress: 0)
                DispatchQueue.main.async { self.localModelStatus = .notInstalled }
                return
            }
            condaPath = home.appendingPathComponent("miniconda3/bin/conda").path
            _ = shellRun("\(condaPath!) init bash zsh 2>/dev/null")
        }

        guard let conda = condaPath else {
            updateInstallUI(step: "Erreur : conda introuvable", progress: 0)
            DispatchQueue.main.async { self.localModelStatus = .notInstalled }
            return
        }

        // Step 2: Create env
        updateInstallUI(step: "Création de l'environnement Python...", progress: 0.15)
        let envCheck = shellRun("\(conda) env list 2>/dev/null")
        if !envCheck.output.contains("vcm") {
            _ = shellRun("\(conda) tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>&1")
            let create = shellRun("\(conda) create -n vcm python=3.11 -y 2>&1")
            guard create.status == 0 else {
                updateInstallUI(step: "Erreur : création environnement échouée", progress: 0)
                DispatchQueue.main.async { self.localModelStatus = .notInstalled }
                return
            }
        }

        // Step 3: Install deps (qwen-tts installs transformers automatically)
        updateInstallUI(step: "Installation de PyTorch et qwen-tts (quelques minutes)...", progress: 0.25)
        let deps = shellRun("\(conda) run -n vcm pip install --quiet torch torchaudio flask soundfile psutil qwen-tts 2>&1")
        guard deps.status == 0 else {
            updateInstallUI(step: "Erreur : installation dépendances échouée", progress: 0)
            DispatchQueue.main.async { self.localModelStatus = .notInstalled }
            return
        }

        // Step 4: Copy server.py (model downloads automatically on first server run)
        updateInstallUI(step: "Configuration du serveur...", progress: 0.92)
        let serverPy = installDir.appendingPathComponent("server.py")
        try? SetupManager.embeddedServerPy.write(to: serverPy, atomically: true, encoding: .utf8)

        // Step 5: Create start script
        updateInstallUI(step: "Finalisation...", progress: 0.96)
        let condaDir = URL(fileURLWithPath: conda).deletingLastPathComponent().deletingLastPathComponent()
        let startScript = installDir.appendingPathComponent("start.sh")
        let bashScript = """
        #!/bin/bash
        export PATH="\(condaDir.path)/bin:$PATH"
        eval "$(\(condaDir.path)/bin/conda shell.bash hook)"
        conda activate vcm
        python3 ~/.voiceclonememo/server.py
        """
        try? bashScript.write(to: startScript, atomically: true, encoding: .utf8)
        _ = shellRun("/bin/chmod +x \(startScript.path)")

        // Done!
        DispatchQueue.main.async { [weak self] in
            self?.installProgress = 1.0
            self?.installStep = "Installation terminée !"
            self?.localModelStatus = .ready
        }
    }

    private func shellRun(_ command: String) -> (status: Int32, output: String) {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = pipe
        task.environment = ProcessInfo.processInfo.environment
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, "")
        }
    }

    // MARK: - Ensure Local Server

    private var serverProcess: Process?

    var systemRAMGB: Double {
        return Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }

    func stopLocalServer() {
        if let proc = serverProcess, proc.isRunning {
            proc.terminate()
            serverProcess = nil
        }
        // Also kill any lingering server on port 5123
        let killTask = Process()
        killTask.launchPath = "/bin/bash"
        killTask.arguments = ["-c", "lsof -ti:5123 | xargs kill -9 2>/dev/null"]
        killTask.standardOutput = FileHandle.nullDevice
        killTask.standardError = FileHandle.nullDevice
        try? killTask.run()
        killTask.waitUntilExit()
        DispatchQueue.main.async { [weak self] in
            self?.localServerRunning = false
        }
    }

    func restartLocalServer() {
        stopLocalServer()
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Redémarrage du serveur..."
        }
        // Small delay to let port free up
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.ensureLocalServerRunning { success in
                DispatchQueue.main.async {
                    self?.statusMessage = success ? "Serveur redémarré !" : "Erreur au redémarrage du serveur"
                }
            }
        }
    }

    func ensureLocalServerRunning(completion: @escaping (Bool) -> Void) {
        // First check if server is already running
        guard let healthURL = URL(string: "http://localhost:5123/health") else {
            completion(false)
            return
        }

        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 2

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            if data != nil {
                // Server is already running
                DispatchQueue.main.async { self?.localServerRunning = true }
                completion(true)
                return
            }

            // Server not running, try to start it
            guard let self = self else { completion(false); return }

            let startScript = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".voiceclonememo/start.sh")

            guard FileManager.default.fileExists(atPath: startScript.path) else {
                DispatchQueue.main.async {
                    self.statusMessage = "Script de démarrage introuvable. Réinstalle Qwen3 dans les settings."
                }
                completion(false)
                return
            }

            DispatchQueue.main.async {
                self.statusMessage = "Démarrage du serveur Qwen3..."
            }

            // Launch server in background with MODEL_SIZE env var
            DispatchQueue.global().async {
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = [startScript.path]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice

                // Pass MODEL_SIZE environment variable
                var env = ProcessInfo.processInfo.environment
                env["MODEL_SIZE"] = self.config.localModelSize
                task.environment = env

                do {
                    try task.run()
                    self.serverProcess = task
                } catch {
                    completion(false)
                    return
                }

                // Wait for server to be ready (poll every 2 sec, max 90 sec for model loading)
                var attempts = 0
                let maxAttempts = 45  // 45 * 2 = 90 seconds

                while attempts < maxAttempts {
                    sleep(2)
                    attempts += 1

                    DispatchQueue.main.async {
                        self.statusMessage = "Chargement du modèle Qwen3 (\(attempts * 2)s)..."
                    }

                    var serverReady = false
                    let semaphore = DispatchSemaphore(value: 0)

                    var checkReq = URLRequest(url: healthURL)
                    checkReq.timeoutInterval = 2
                    URLSession.shared.dataTask(with: checkReq) { data, _, _ in
                        serverReady = data != nil
                        semaphore.signal()
                    }.resume()
                    semaphore.wait()

                    if serverReady {
                        DispatchQueue.main.async {
                            self.localServerRunning = true
                            self.statusMessage = "Serveur Qwen3 prêt !"
                        }
                        completion(true)
                        return
                    }
                }

                // Timeout
                DispatchQueue.main.async {
                    self.statusMessage = "Le serveur met trop de temps à démarrer. Vérifie l'installation."
                }
                completion(false)
            }
        }.resume()
    }

    private func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configFile)
        }
    }

    func saveProfiles() {
        if let data = try? JSONEncoder().encode(voiceProfiles) {
            try? data.write(to: profilesFile)
        }
    }

    // MARK: - Voice Profiles

    func addVoiceFromRecording(name: String, transcript: String? = nil) {
        guard let url = recorder.lastRecordingURL else { return }
        addVoiceFromFile(name: name, sourceURL: url, transcript: transcript)
    }

    func addVoiceFromFile(name: String, sourceURL: URL, transcript: String? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let voicesDir = appSupport.appendingPathComponent("VoiceCloneMemo/voices")
        try? FileManager.default.createDirectory(at: voicesDir, withIntermediateDirectories: true)

        let destURL = voicesDir.appendingPathComponent("\(UUID().uuidString).wav")
        try? FileManager.default.copyItem(at: sourceURL, to: destURL)

        isCloning = true
        statusMessage = "Clonage en cours..."

        switch config.provider {
        case .local:
            // Ensure local server is running before cloning
            ensureLocalServerRunning { [weak self] serverReady in
                guard let self = self else { return }
                if serverReady {
                    self.cloneVoiceLocal(name: name, audioURL: destURL, transcript: transcript) { [weak self] voiceId in
                        DispatchQueue.main.async {
                            let profile = VoiceProfile(name: name, audioFile: destURL.path, providerVoiceId: voiceId, provider: .local)
                            self?.voiceProfiles.append(profile)
                            self?.saveProfiles()
                            self?.isCloning = false
                            self?.statusMessage = voiceId != nil ? "Voix clonée !" : "Voix sauvegardée (clonage échoué)"
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        let profile = VoiceProfile(name: name, audioFile: destURL.path, providerVoiceId: nil, provider: .local)
                        self.voiceProfiles.append(profile)
                        self.saveProfiles()
                        self.isCloning = false
                        self.statusMessage = "Voix sauvegardée. Le serveur Qwen démarre, réessaie dans 1 min."
                    }
                }
            }
        case .fish:
            cloneVoiceFish(name: name, audioURL: destURL) { [weak self] voiceId in
                DispatchQueue.main.async {
                    let profile = VoiceProfile(name: name, audioFile: destURL.path, providerVoiceId: voiceId, provider: .fish)
                    self?.voiceProfiles.append(profile)
                    self?.saveProfiles()
                    self?.isCloning = false
                    self?.statusMessage = voiceId != nil ? "Voix clonée !" : "Voix sauvegardée (clonage échoué)"
                }
            }
        case .qwen:
            cloneVoiceQwen(name: name, audioURL: destURL) { [weak self] voiceId in
                DispatchQueue.main.async {
                    let profile = VoiceProfile(name: name, audioFile: destURL.path, providerVoiceId: voiceId, provider: .qwen)
                    self?.voiceProfiles.append(profile)
                    self?.saveProfiles()
                    self?.isCloning = false
                    self?.statusMessage = voiceId != nil ? "Voix clonée !" : "Voix sauvegardée (clonage échoué)"
                }
            }
        case .elevenLabs:
            cloneVoiceElevenLabs(name: name, audioURL: destURL) { [weak self] voiceId in
                DispatchQueue.main.async {
                    let profile = VoiceProfile(name: name, audioFile: destURL.path, providerVoiceId: voiceId, provider: .elevenLabs)
                    self?.voiceProfiles.append(profile)
                    self?.saveProfiles()
                    self?.isCloning = false
                    self?.statusMessage = voiceId != nil ? "Voix clonée !" : "Voix sauvegardée (clonage échoué)"
                }
            }
        default:
            let profile = VoiceProfile(name: name, audioFile: destURL.path, providerVoiceId: nil, provider: config.provider)
            voiceProfiles.append(profile)
            saveProfiles()
            isCloning = false
            statusMessage = "Voix sauvegardée"
        }
    }

    func removeProfile(_ id: UUID) {
        voiceProfiles.removeAll { $0.id == id }
        saveProfiles()
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav, .mp3, .mpeg4Audio, .movie, .mpeg4Movie, .quickTimeMovie, .avi, .video]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Sélectionne un fichier audio ou vidéo"

        if panel.runModal() == .OK, let url = panel.url {
            let videoExtensions = ["mp4", "mov", "avi", "mkv", "m4v", "webm"]
            if videoExtensions.contains(url.pathExtension.lowercased()) {
                statusMessage = "Extraction audio..."
                extractAudioFromVideo(url: url) { [weak self] audioURL in
                    DispatchQueue.main.async {
                        if let audioURL = audioURL {
                            self?.addVoiceFromFile(name: url.deletingPathExtension().lastPathComponent, sourceURL: audioURL)
                        } else {
                            self?.statusMessage = "Erreur extraction audio"
                        }
                    }
                }
            } else {
                addVoiceFromFile(name: url.deletingPathExtension().lastPathComponent, sourceURL: url)
            }
        }
    }

    private func extractAudioFromVideo(url: URL, completion: @escaping (URL?) -> Void) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let tempAudio = appSupport.appendingPathComponent("VoiceCloneMemo/temp_extracted.wav")

        // Try ffmpeg first (better quality)
        DispatchQueue.global().async {
            let homeBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/ffmpeg").path
            let ffmpegPaths = [homeBin, "/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
            let ffmpegPath = ffmpegPaths.first { FileManager.default.fileExists(atPath: $0) }

            if let ffmpegPath = ffmpegPath {
                try? FileManager.default.removeItem(at: tempAudio)
                let task = Process()
                task.launchPath = ffmpegPath
                task.arguments = ["-i", url.path, "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1", "-y", tempAudio.path]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
                task.waitUntilExit()

                if task.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempAudio.path) {
                    completion(tempAudio)
                    return
                }
            }

            // Fallback: AVFoundation
            self.extractWithAVFoundation(url: url, output: tempAudio, completion: completion)
        }
    }

    // MARK: - YouTube Import

    func importFromYouTube(urlString: String, startTime: String, endTime: String, name: String, transcript: String? = nil) {
        isCloning = true
        statusMessage = "Téléchargement YouTube..."

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let tempDir = appSupport.appendingPathComponent("VoiceCloneMemo")
            let tempFull = tempDir.appendingPathComponent("yt_full.wav")
            let tempClip = tempDir.appendingPathComponent("yt_clip.wav")

            // Find yt-dlp
            let homeBinYt = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/yt-dlp").path
            let ytdlpPaths = [homeBinYt, "/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp"]
            guard let ytdlpPath = ytdlpPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                DispatchQueue.main.async {
                    self.isCloning = false
                    self.statusMessage = "yt-dlp non trouvé. Installe avec : brew install yt-dlp"
                }
                return
            }

            // Find ffmpeg
            let homeBin2 = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin/ffmpeg").path
            let ffmpegPaths = [homeBin2, "/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
            guard let ffmpegPath = ffmpegPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                DispatchQueue.main.async {
                    self.isCloning = false
                    self.statusMessage = "ffmpeg non trouvé. Installe avec : brew install ffmpeg"
                }
                return
            }

            // Step 1: Download audio from YouTube
            try? FileManager.default.removeItem(at: tempFull)
            let dlTask = Process()
            dlTask.launchPath = ytdlpPath
            dlTask.arguments = ["-x", "--audio-format", "wav", "-o", tempFull.path, urlString]
            dlTask.standardOutput = FileHandle.nullDevice
            dlTask.standardError = FileHandle.nullDevice
            try? dlTask.run()
            dlTask.waitUntilExit()

            // yt-dlp might add extension, find the file
            var actualFile = tempFull
            if !FileManager.default.fileExists(atPath: tempFull.path) {
                // Check for yt_full.wav.wav or similar
                let contents = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
                if let found = contents.first(where: { $0.lastPathComponent.hasPrefix("yt_full") }) {
                    actualFile = found
                } else {
                    DispatchQueue.main.async {
                        self.isCloning = false
                        self.statusMessage = "Erreur téléchargement YouTube"
                    }
                    return
                }
            }

            DispatchQueue.main.async { self.statusMessage = "Extraction segment..." }

            // Step 2: Cut the segment with ffmpeg
            let startSec = self.parseTimestamp(startTime)
            let endSec = self.parseTimestamp(endTime)
            let duration = endSec - startSec

            guard duration > 0 else {
                // No timestamps, use full file
                DispatchQueue.main.async {
                    self.addVoiceFromFile(name: name.isEmpty ? "YouTube Voice" : name, sourceURL: actualFile, transcript: transcript)
                    self.isCloning = false
                }
                return
            }

            try? FileManager.default.removeItem(at: tempClip)
            let cutTask = Process()
            cutTask.launchPath = ffmpegPath
            cutTask.arguments = [
                "-i", actualFile.path,
                "-ss", String(startSec),
                "-t", String(duration),
                "-acodec", "pcm_s16le",
                "-ar", "16000",
                "-ac", "1",
                "-y", tempClip.path
            ]
            cutTask.standardOutput = FileHandle.nullDevice
            cutTask.standardError = FileHandle.nullDevice
            try? cutTask.run()
            cutTask.waitUntilExit()

            if cutTask.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempClip.path) {
                DispatchQueue.main.async {
                    self.addVoiceFromFile(name: name.isEmpty ? "YouTube Voice" : name, sourceURL: tempClip, transcript: transcript)
                }
            } else {
                DispatchQueue.main.async {
                    self.isCloning = false
                    self.statusMessage = "Erreur extraction segment"
                }
            }
        }
    }

    func parseTimestamp(_ ts: String) -> Double {
        let trimmed = ts.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }

        let parts = trimmed.components(separatedBy: ":")
        switch parts.count {
        case 1:
            return Double(parts[0]) ?? 0
        case 2:
            let min = Double(parts[0]) ?? 0
            let sec = Double(parts[1]) ?? 0
            return min * 60 + sec
        case 3:
            let hr = Double(parts[0]) ?? 0
            let min = Double(parts[1]) ?? 0
            let sec = Double(parts[2]) ?? 0
            return hr * 3600 + min * 60 + sec
        default:
            return 0
        }
    }

    private func extractWithAVFoundation(url: URL, output: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVURLAsset(url: url)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(nil)
            return
        }

        let m4aOutput = output.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: m4aOutput)

        exportSession.outputURL = m4aOutput
        exportSession.outputFileType = .m4a

        exportSession.exportAsynchronously {
            if exportSession.status == .completed {
                completion(m4aOutput)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - Generate Speech

    func generateSpeech(text: String, profile: VoiceProfile?, tone: TTSTone = .normal, completion: @escaping (URL?) -> Void) {
        isGenerating = true
        lastError = nil
        statusMessage = "Génération..."

        switch config.provider {
        case .local:
            ensureLocalServerRunning { [weak self] serverReady in
                guard let self = self else { return }
                if serverReady {
                    self.generateLocal(text: text, voiceId: profile?.providerVoiceId ?? "", tone: tone, completion: completion)
                } else {
                    DispatchQueue.main.async {
                        self.isGenerating = false
                        self.lastError = "Serveur Qwen en cours de démarrage... Réessaie dans 30 sec."
                        self.statusMessage = ""
                    }
                    completion(nil)
                }
            }
            return
        case .fish:
            generateFish(text: text, voiceId: profile?.providerVoiceId ?? config.fishVoiceId, completion: completion)
        case .qwen:
            generateQwen(text: text, voiceId: profile?.providerVoiceId ?? config.qwenVoiceId, completion: completion)
        case .elevenLabs:
            generateElevenLabs(text: text, voiceId: profile?.providerVoiceId ?? config.elevenLabsVoiceId, completion: completion)
        case .openai:
            generateOpenAI(text: text, completion: completion)
        case .system:
            generateSystem(text: text, voice: config.systemVoice, completion: completion)
        }
    }

    // MARK: - Local Qwen3-TTS

    private func cloneVoiceLocal(name: String, audioURL: URL, transcript: String? = nil, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "http://localhost:5123/v1/clone") else {
            completion(nil)
            return
        }

        guard let audioData = try? Data(contentsOf: audioURL) else {
            completion(nil)
            return
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(name)\r\n".data(using: .utf8)!)

        if let transcript = transcript {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"transcript\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(transcript)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"voice.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let voiceId = json["voice_id"] as? String else {
                completion(nil)
                return
            }
            completion(voiceId)
        }.resume()
    }

    private func generateLocal(text: String, voiceId: String, tone: TTSTone = .normal, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: "http://localhost:5123/v1/tts") else {
            DispatchQueue.main.async { self.isGenerating = false }
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        var bodyDict: [String: Any] = ["text": text]
        if !voiceId.isEmpty {
            bodyDict["voice_id"] = voiceId
        }
        if let instruction = tone.instruction {
            bodyDict["instruction"] = instruction
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.isGenerating = false }
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "Erreur réseau : \(error.localizedDescription)"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let errorMsg: String
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errStr = json["error"] as? String {
                    errorMsg = errStr
                } else {
                    errorMsg = "Erreur serveur local (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                }
                DispatchQueue.main.async {
                    self?.lastError = errorMsg
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).wav")
            if let outputURL = outputURL {
                try? data.write(to: outputURL)
                DispatchQueue.main.async {
                    self?.lastGeneratedURL = outputURL
                    self?.lastError = nil
                    self?.statusMessage = "Mémo généré !"
                }
                completion(outputURL)
            }
        }.resume()
    }

    // MARK: - Fish Audio

    private func cloneVoiceFish(name: String, audioURL: URL, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.fish.audio/model") else {
            completion(nil)
            return
        }

        guard let audioData = try? Data(contentsOf: audioURL) else {
            completion(nil)
            return
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.fishKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        // Title
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"title\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(name)\r\n".data(using: .utf8)!)

        // Visibility
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"visibility\"\r\n\r\n".data(using: .utf8)!)
        body.append("private\r\n".data(using: .utf8)!)

        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"voices\"; filename=\"voice.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelId = json["_id"] as? String else {
                completion(nil)
                return
            }
            completion(modelId)
        }.resume()
    }

    private func generateFish(text: String, voiceId: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: "https://api.fish.audio/v1/tts") else {
            DispatchQueue.main.async { self.isGenerating = false }
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.fishKey)", forHTTPHeaderField: "Authorization")

        var bodyDict: [String: Any] = [
            "text": text,
            "format": "mp3"
        ]
        if !voiceId.isEmpty {
            bodyDict["reference_id"] = voiceId
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.isGenerating = false }
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "Erreur réseau : \(error.localizedDescription)"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    self?.lastError = "Erreur Fish Audio (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).mp3")
            if let outputURL = outputURL {
                try? data.write(to: outputURL)
                DispatchQueue.main.async {
                    self?.lastGeneratedURL = outputURL
                    self?.lastError = nil
                    self?.statusMessage = "Mémo généré !"
                }
                completion(outputURL)
            }
        }.resume()
    }

    // MARK: - Qwen3-TTS-VC

    private func cloneVoiceQwen(name: String, audioURL: URL, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://dashscope-intl.aliyuncs.com/api/v1/services/audio/tts/customization") else {
            completion(nil)
            return
        }

        guard let audioData = try? Data(contentsOf: audioURL) else {
            completion(nil)
            return
        }

        let base64Audio = audioData.base64EncodedString()
        let dataURI = "data:audio/wav;base64,\(base64Audio)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.qwenKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "qwen-voice-enrollment",
            "input": [
                "action": "create",
                "target_model": "qwen3-tts-vc-2026-01-22",
                "preferred_name": name,
                "audio": [
                    "data": dataURI
                ]
            ] as [String: Any]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [String: Any],
                  let voiceId = output["voice_id"] as? String else {
                completion(nil)
                return
            }
            completion(voiceId)
        }.resume()
    }

    private func generateQwen(text: String, voiceId: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: "https://dashscope-intl.aliyuncs.com/api/v1/services/aigc/text2audio/generation") else {
            DispatchQueue.main.async { self.isGenerating = false }
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.qwenKey)", forHTTPHeaderField: "Authorization")

        var inputDict: [String: Any] = ["text": text]
        if !voiceId.isEmpty {
            inputDict["voice"] = voiceId
        }

        let body: [String: Any] = [
            "model": "qwen3-tts-vc-2026-01-22",
            "input": inputDict
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.isGenerating = false }

            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "Erreur réseau : \(error.localizedDescription)"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.lastError = "Pas de données reçues"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }

            // Check if response is audio directly
            if let httpResponse = response as? HTTPURLResponse,
               let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               contentType.contains("audio") {
                let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).mp3")
                if let outputURL = outputURL {
                    try? data.write(to: outputURL)
                    DispatchQueue.main.async {
                        self?.lastGeneratedURL = outputURL
                        self?.statusMessage = "Mémo généré !"
                    }
                    completion(outputURL)
                    return
                }
            }

            // Check if response is JSON with audio URL
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let output = json["output"] as? [String: Any],
               let audioURL = output["audio"] as? String,
               let downloadURL = URL(string: audioURL) {
                // Download the audio
                URLSession.shared.dataTask(with: downloadURL) { audioData, _, _ in
                    guard let audioData = audioData else {
                        completion(nil)
                        return
                    }
                    let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).mp3")
                    if let outputURL = outputURL {
                        try? audioData.write(to: outputURL)
                        DispatchQueue.main.async {
                            self?.lastGeneratedURL = outputURL
                            self?.statusMessage = "Mémo généré !"
                        }
                        completion(outputURL)
                    }
                }.resume()
                return
            }

            DispatchQueue.main.async {
                self?.lastError = "Erreur API Qwen : réponse inattendue"
                self?.statusMessage = ""
            }
            completion(nil)
        }.resume()
    }

    // MARK: - ElevenLabs

    private func cloneVoiceElevenLabs(name: String, audioURL: URL, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices/add") else {
            completion(nil)
            return
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(config.elevenLabsKey, forHTTPHeaderField: "xi-api-key")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(name)\r\n".data(using: .utf8)!)

        if let audioData = try? Data(contentsOf: audioURL) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"voice.wav\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let voiceId = json["voice_id"] as? String else {
                completion(nil)
                return
            }
            completion(voiceId)
        }.resume()
    }

    private func generateElevenLabs(text: String, voiceId: String, completion: @escaping (URL?) -> Void) {
        guard !voiceId.isEmpty,
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)") else {
            DispatchQueue.main.async { self.isGenerating = false }
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.elevenLabsKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.isGenerating = false }
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "Erreur réseau : \(error.localizedDescription)"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    self?.lastError = "Erreur ElevenLabs (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).mp3")
            if let outputURL = outputURL {
                try? data.write(to: outputURL)
                DispatchQueue.main.async {
                    self?.lastGeneratedURL = outputURL
                    self?.lastError = nil
                    self?.statusMessage = "Mémo généré !"
                }
                completion(outputURL)
            }
        }.resume()
    }

    // MARK: - OpenAI TTS

    private func generateOpenAI(text: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            DispatchQueue.main.async { self.isGenerating = false }
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.openaiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "tts-1-hd",
            "input": text,
            "voice": config.openaiVoice
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.isGenerating = false }
            if let error = error {
                DispatchQueue.main.async {
                    self?.lastError = "Erreur réseau : \(error.localizedDescription)"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    self?.lastError = "Erreur OpenAI (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))"
                    self?.statusMessage = ""
                }
                completion(nil)
                return
            }
            let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).mp3")
            if let outputURL = outputURL {
                try? data.write(to: outputURL)
                DispatchQueue.main.async {
                    self?.lastGeneratedURL = outputURL
                    self?.lastError = nil
                    self?.statusMessage = "Mémo généré !"
                }
                completion(outputURL)
            }
        }.resume()
    }

    // MARK: - System Voice

    private func generateSystem(text: String, voice: String, completion: @escaping (URL?) -> Void) {
        let outputURL = outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).aiff")

        DispatchQueue.global().async { [weak self] in
            let task = Process()
            task.launchPath = "/usr/bin/say"
            task.arguments = ["-v", voice, "-o", outputURL.path, text]
            try? task.run()
            task.waitUntilExit()

            DispatchQueue.main.async {
                self?.isGenerating = false
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    self?.lastGeneratedURL = outputURL
                    self?.lastError = nil
                    self?.statusMessage = "Mémo généré !"
                    completion(outputURL)
                } else {
                    self?.lastError = "Erreur voix système macOS"
                    self?.statusMessage = ""
                    completion(nil)
                }
            }
        }
    }

    var isConfigured: Bool {
        switch config.provider {
        case .local: return localModelStatus == .ready
        case .fish: return !config.fishKey.isEmpty
        case .qwen: return !config.qwenKey.isEmpty
        case .elevenLabs: return !config.elevenLabsKey.isEmpty
        case .openai: return !config.openaiKey.isEmpty
        case .system: return true
        }
    }
}

struct VoiceProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var audioFile: String
    var providerVoiceId: String?
    var provider: TTSProvider

    init(name: String, audioFile: String, providerVoiceId: String?, provider: TTSProvider) {
        self.id = UUID()
        self.name = name
        self.audioFile = audioFile
        self.providerVoiceId = providerVoiceId
        self.provider = provider
    }
}
