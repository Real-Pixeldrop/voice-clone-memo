import Foundation
import AppKit

enum TTSProvider: String, Codable, CaseIterable {
    case qwen = "Qwen3 (Alibaba)"
    case elevenLabs = "ElevenLabs"
    case openai = "OpenAI TTS"
    case system = "Voix système (macOS)"

    var needsApiKey: Bool {
        switch self {
        case .qwen, .elevenLabs, .openai: return true
        case .system: return false
        }
    }

    var icon: String {
        switch self {
        case .qwen: return "brain"
        case .elevenLabs: return "waveform"
        case .openai: return "sparkles"
        case .system: return "desktopcomputer"
        }
    }

    var description: String {
        switch self {
        case .qwen: return "Clonage vocal en 3 sec, gratuit 500k tokens/mois"
        case .elevenLabs: return "Clonage vocal, très réaliste"
        case .openai: return "Voix haute qualité, pas de clone"
        case .system: return "Gratuit, hors-ligne, basique"
        }
    }
}

struct VoiceConfig: Codable {
    var provider: TTSProvider
    var qwenKey: String
    var qwenVoiceId: String
    var elevenLabsKey: String
    var elevenLabsVoiceId: String
    var openaiKey: String
    var openaiVoice: String
    var systemVoice: String

    init() {
        self.provider = .qwen
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

    func importAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav, .mp3, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            addVoiceFromFile(name: url.deletingPathExtension().lastPathComponent, sourceURL: url)
        }
    }

    // MARK: - Generate Speech

    func generateSpeech(text: String, profile: VoiceProfile?, completion: @escaping (URL?) -> Void) {
        isGenerating = true
        statusMessage = "Génération..."

        switch config.provider {
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
