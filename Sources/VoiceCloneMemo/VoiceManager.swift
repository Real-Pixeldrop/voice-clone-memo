import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum TTSProvider: String, Codable, CaseIterable {
    case fish = "Fish Audio"
    case qwen = "Qwen3 (Alibaba)"
    case elevenLabs = "ElevenLabs"
    case openai = "OpenAI TTS"
    case system = "Voix système (macOS)"

    var needsApiKey: Bool {
        switch self {
        case .fish, .qwen, .elevenLabs, .openai: return true
        case .system: return false
        }
    }

    var icon: String {
        switch self {
        case .fish: return "fish"
        case .qwen: return "brain"
        case .elevenLabs: return "waveform"
        case .openai: return "sparkles"
        case .system: return "desktopcomputer"
        }
    }

    var description: String {
        switch self {
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

    init() {
        self.provider = .qwen
        self.fishKey = ""
        self.fishVoiceId = ""
        self.qwenKey = ""
        self.qwenVoiceId = ""
        self.elevenLabsKey = ""
        self.elevenLabsVoiceId = ""
        self.openaiKey = ""
        self.openaiVoice = "alloy"
        self.systemVoice = "Thomas"
    }
}

class VoiceManager: ObservableObject {
    @Published var config: VoiceConfig
    @Published var voiceProfiles: [VoiceProfile] = []
    @Published var isGenerating = false
    @Published var isCloning = false
    @Published var lastGeneratedURL: URL?
    @Published var statusMessage: String = ""

    let recorder = AudioRecorder()
    private let configFile: URL
    private let profilesFile: URL
    let outputDir: URL

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

    func addVoiceFromRecording(name: String) {
        guard let url = recorder.stopRecording() else { return }
        addVoiceFromFile(name: name, sourceURL: url)
    }

    func addVoiceFromFile(name: String, sourceURL: URL) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let voicesDir = appSupport.appendingPathComponent("VoiceCloneMemo/voices")
        try? FileManager.default.createDirectory(at: voicesDir, withIntermediateDirectories: true)

        let destURL = voicesDir.appendingPathComponent("\(UUID().uuidString).wav")
        try? FileManager.default.copyItem(at: sourceURL, to: destURL)

        isCloning = true
        statusMessage = "Clonage en cours..."

        switch config.provider {
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
            let ffmpegPaths = ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
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

    func importFromYouTube(urlString: String, startTime: String, endTime: String, name: String) {
        isCloning = true
        statusMessage = "Téléchargement YouTube..."

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let tempDir = appSupport.appendingPathComponent("VoiceCloneMemo")
            let tempFull = tempDir.appendingPathComponent("yt_full.wav")
            let tempClip = tempDir.appendingPathComponent("yt_clip.wav")

            // Find yt-dlp
            let ytdlpPaths = ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp"]
            guard let ytdlpPath = ytdlpPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                DispatchQueue.main.async {
                    self.isCloning = false
                    self.statusMessage = "yt-dlp non trouvé. Installe avec : brew install yt-dlp"
                }
                return
            }

            // Find ffmpeg
            let ffmpegPaths = ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg"]
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
                    self.addVoiceFromFile(name: name.isEmpty ? "YouTube Voice" : name, sourceURL: actualFile)
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
                    self.addVoiceFromFile(name: name.isEmpty ? "YouTube Voice" : name, sourceURL: tempClip)
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

    func generateSpeech(text: String, profile: VoiceProfile?, completion: @escaping (URL?) -> Void) {
        isGenerating = true
        statusMessage = "Génération..."

        switch config.provider {
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
            guard let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async { self?.statusMessage = "Erreur Fish Audio" }
                completion(nil)
                return
            }
            let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).mp3")
            if let outputURL = outputURL {
                try? data.write(to: outputURL)
                DispatchQueue.main.async {
                    self?.lastGeneratedURL = outputURL
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

            guard let data = data, error == nil else {
                DispatchQueue.main.async { self?.statusMessage = "Erreur réseau" }
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

            DispatchQueue.main.async { self?.statusMessage = "Erreur API Qwen" }
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
            guard let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async { self?.statusMessage = "Erreur ElevenLabs" }
                completion(nil)
                return
            }
            let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).mp3")
            if let outputURL = outputURL {
                try? data.write(to: outputURL)
                DispatchQueue.main.async {
                    self?.lastGeneratedURL = outputURL
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
            guard let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async { self?.statusMessage = "Erreur OpenAI" }
                completion(nil)
                return
            }
            let outputURL = self?.outputDir.appendingPathComponent("memo_\(Int(Date().timeIntervalSince1970)).mp3")
            if let outputURL = outputURL {
                try? data.write(to: outputURL)
                DispatchQueue.main.async {
                    self?.lastGeneratedURL = outputURL
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
                    self?.statusMessage = "Mémo généré !"
                    completion(outputURL)
                } else {
                    self?.statusMessage = "Erreur système"
                    completion(nil)
                }
            }
        }
    }

    var isConfigured: Bool {
        switch config.provider {
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
