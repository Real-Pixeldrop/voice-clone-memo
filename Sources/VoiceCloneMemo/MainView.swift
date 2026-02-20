import SwiftUI
import AppKit
import NaturalLanguage

enum TTSTone: String, CaseIterable {
    case normal = "Normal"
    case joyful = "Joyeux"
    case serious = "Sérieux"
    case whispered = "Chuchoté"

    var instruction: String? {
        switch self {
        case .normal: return nil
        case .joyful: return "Speak with a joyful, happy and enthusiastic tone."
        case .serious: return "Speak with a serious, formal and composed tone."
        case .whispered: return "Speak in a soft whisper, very quiet and intimate."
        }
    }

    var icon: String {
        switch self {
        case .normal: return "waveform"
        case .joyful: return "face.smiling"
        case .serious: return "briefcase"
        case .whispered: return "ear"
        }
    }
}

struct MainView: View {
    @ObservedObject var voiceManager: VoiceManager
    @ObservedObject var autoUpdater: AutoUpdater
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var currentTab = 0
    @State private var text = ""
    @State private var selectedProfile: VoiceProfile?
    @State private var selectedTone: TTSTone = .normal
    @State private var showSettings = false
    @State private var newVoiceName = ""
    @State private var newVoiceTranscript = ""
    @State private var showNameInput = false
    @State private var showYouTube = false
    @State private var youtubeURL = ""
    @State private var ytStartTime = ""
    @State private var ytEndTime = ""
    @State private var ytVoiceName = ""
    @State private var pendingModelSize: String = ""
    @State private var modelSizeChanged = false

    // MARK: - Text Stats (computed)

    private var charCount: Int { text.count }

    private var wordCount: Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    private var estimatedAudioSeconds: Int {
        guard wordCount > 0 else { return 0 }
        return max(1, Int(round(Double(wordCount) / 150.0 * 60.0)))
    }

    private var detectedLanguage: (code: String, label: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let lang = recognizer.dominantLanguage else { return nil }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let confidence = hypotheses[lang], confidence > 0.5 else { return nil }
        let labels: [NLLanguage: String] = [
            .french: "FR", .english: "EN", .spanish: "ES", .german: "DE",
            .italian: "IT", .portuguese: "PT", .dutch: "NL", .russian: "RU",
            .japanese: "JA", .simplifiedChinese: "ZH", .traditionalChinese: "ZH", .korean: "KO", .arabic: "AR",
            .turkish: "TR", .polish: "PL", .swedish: "SV", .danish: "DA",
            .norwegian: "NO", .finnish: "FI", .czech: "CS", .romanian: "RO",
            .hungarian: "HU", .thai: "TH", .vietnamese: "VI", .indonesian: "ID",
            .hindi: "HI",
        ]
        let label = labels[lang] ?? lang.rawValue.uppercased().prefix(2).description
        return (lang.rawValue, label)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "mic.badge.plus")
                    .font(.title2)
                Text("Voice Clone Memo")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "gear")
                            .font(.title3)
                        if autoUpdater.updateAvailable {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if showSettings {
                settingsView
            } else {
                // Tabs
                Picker("", selection: $currentTab) {
                    Text("Générer").tag(0)
                    Text("Voix").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if currentTab == 0 {
                    generateTab
                } else {
                    voicesTab
                }
            }
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - Generate Tab

    var generateTab: some View {
        VStack(spacing: 12) {
            // Voice selector
            if !voiceManager.voiceProfiles.isEmpty {
                HStack {
                    Text("Voix :")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $selectedProfile) {
                        Text("Par défaut").tag(nil as VoiceProfile?)
                        ForEach(voiceManager.voiceProfiles) { profile in
                            Text(profile.name).tag(profile as VoiceProfile?)
                        }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal)
            }

            // Tone selector
            HStack(spacing: 6) {
                Text("Ton :")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedTone) {
                    ForEach(TTSTone.allCases, id: \.self) { tone in
                        Label(tone.rawValue, systemImage: tone.icon).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal)

            // Text input
            TextEditor(text: $text)
                .font(.body)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                .padding(.horizontal)

            // Text stats
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 6) {
                    Text("\(charCount) caractères · \(wordCount) mots")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("~\(estimatedAudioSeconds) sec d'audio")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let lang = detectedLanguage {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("\(lang.label) détecté")
                            .font(.caption)
                            .foregroundColor(.accentColor.opacity(0.8))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
            }

            if !voiceManager.isConfigured {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Configure ton provider — clique ⚙️")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if voiceManager.config.provider == .local && voiceManager.localModelStatus == .notInstalled {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Qwen3 pas installé. Va dans ⚙️ pour l'installer.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Generate button
            Button(action: generate) {
                HStack {
                    if voiceManager.isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(voiceManager.isGenerating ? "Génération..." : "Générer le mémo vocal")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.isEmpty || !voiceManager.isConfigured || voiceManager.isGenerating)
            .padding(.horizontal)

            // Error banner
            if let error = voiceManager.lastError {
                errorBanner(message: error)
            }

            // Mini audio player
            if let lastURL = voiceManager.lastGeneratedURL {
                VStack(spacing: 8) {
                    // Compact player bar
                    miniPlayerView(url: lastURL)

                    // Action buttons
                    HStack(spacing: 8) {
                        Button(action: { saveAudioAs(lastURL) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.to.line")
                                Text("Enregistrer")
                            }
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { shareAudio(lastURL) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Partager")
                            }
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { copyFileToClipboard(lastURL) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copier")
                            }
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { revealInFinder(lastURL) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text("Finder")
                            }
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Mini Player

    func miniPlayerView(url: URL) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // Play/Pause button
                Button(action: {
                    if audioPlayer.duration == 0 {
                        audioPlayer.load(url: url)
                    }
                    audioPlayer.playPause()
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                VStack(spacing: 4) {
                    // Progress bar (clickable for seek)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Capsule()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)

                            // Progress fill
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(0, geometry.size.width * CGFloat(audioPlayer.progress)), height: 6)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let fraction = max(0, min(1, Double(value.location.x / geometry.size.width)))
                                    if audioPlayer.duration == 0 {
                                        audioPlayer.load(url: url)
                                    }
                                    audioPlayer.seek(to: fraction)
                                }
                        )
                    }
                    .frame(height: 6)

                    // Time labels
                    HStack {
                        Text(AudioPlayerManager.formatTime(audioPlayer.currentTime))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(AudioPlayerManager.formatTime(audioPlayer.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.15), lineWidth: 1))
        .onAppear {
            // Load duration info
            if audioPlayer.duration == 0 {
                audioPlayer.load(url: url)
            }
        }
        .onChange(of: voiceManager.lastGeneratedURL) { newURL in
            // When a new file is generated, load and auto-play
            if let newURL = newURL {
                audioPlayer.load(url: newURL)
                audioPlayer.play()
            }
        }
    }

    // MARK: - Error Banner

    func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.body)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: NSColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1)))
                .lineLimit(3)

            Spacer()

            Button(action: generate) {
                Text("Réessayer")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(text.isEmpty || !voiceManager.isConfigured || voiceManager.isGenerating)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - Voices Tab

    var voicesTab: some View {
        VStack(spacing: 12) {
            // Record new voice
            VStack(spacing: 8) {
                if showNameInput {
                    VStack(spacing: 6) {
                        TextField("Nom de la voix", text: $newVoiceName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Qu'as-tu dit ? (optionnel, améliore le clonage)", text: $newVoiceTranscript)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        HStack {
                            Button("Annuler") {
                                newVoiceName = ""
                                newVoiceTranscript = ""
                                showNameInput = false
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            Spacer()
                            Button("Cloner cette voix") {
                                if !newVoiceName.isEmpty {
                                    voiceManager.addVoiceFromRecording(name: newVoiceName, transcript: newVoiceTranscript.isEmpty ? nil : newVoiceTranscript)
                                    newVoiceName = ""
                                    newVoiceTranscript = ""
                                    showNameInput = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                            .disabled(newVoiceName.isEmpty)
                        }
                    }
                    .padding(.horizontal)
                }

                // Recording state: full-width red bar
                if voiceManager.recorder.isRecording {
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .opacity(voiceManager.recorder.isPulsing ? 1.0 : 0.3)
                                .animation(.easeInOut(duration: 0.4), value: voiceManager.recorder.isPulsing)
                            Text("Enregistrement en cours")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.red)
                            Spacer()
                            Text(String(format: "%.0fs", voiceManager.recorder.recordingTime))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.red)
                                .monospacedDigit()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.3), lineWidth: 1))

                        Button(action: {
                            voiceManager.recorder.stopRecording()
                            showNameInput = true
                        }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                Text("Arrêter l'enregistrement")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.horizontal)
                } else {
                    // Normal state: record + import buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            showNameInput = false
                            newVoiceName = ""
                            newVoiceTranscript = ""
                            voiceManager.recorder.startRecording()
                        }) {
                            HStack {
                                Image(systemName: "mic.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text("Enregistrer ma voix")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("10-20 sec recommandé")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Import button (audio or video)
                        Button(action: { voiceManager.importFile() }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Fichier")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        // YouTube button
                        Button(action: { showYouTube.toggle() }) {
                            HStack {
                                Image(systemName: "play.rectangle")
                                Text("YouTube")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 8)

            // YouTube import
            if showYouTube {
                VStack(spacing: 6) {
                    TextField("Lien YouTube", text: $youtubeURL)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        TextField("Début (1:10)", text: $ytStartTime)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        TextField("Fin (1:40)", text: $ytEndTime)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        TextField("Nom voix", text: $ytVoiceName)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: {
                        voiceManager.importFromYouTube(
                            urlString: youtubeURL,
                            startTime: ytStartTime,
                            endTime: ytEndTime,
                            name: ytVoiceName
                        )
                        showYouTube = false
                        youtubeURL = ""
                        ytStartTime = ""
                        ytEndTime = ""
                        ytVoiceName = ""
                    }) {
                        Text("Cloner depuis YouTube")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(youtubeURL.isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            // Mic permission warning
            if voiceManager.recorder.permissionDenied {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Accès micro refusé. Autorise dans Réglages > Confidentialité > Micro.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal)
            }

            // Status
            if !voiceManager.statusMessage.isEmpty {
                Text(voiceManager.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            Divider()

            // Voice profiles list
            if voiceManager.voiceProfiles.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "person.wave.2")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Aucune voix enregistrée")
                        .foregroundColor(.secondary)
                    Text("Enregistre ta voix ou importe un audio/vidéo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(voiceManager.voiceProfiles.enumerated()), id: \.element.id) { _, profile in
                            HStack {
                                Image(systemName: "person.circle")
                                    .font(.title3)
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .font(.system(size: 13, weight: .medium))
                                    if profile.providerVoiceId != nil {
                                        Text("Clonée (\(profile.provider.rawValue))")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Audio de référence")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button(action: { voiceManager.removeProfile(profile.id) }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Settings

    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Provider vocal")
                    .font(.headline)

                ForEach(TTSProvider.allCases, id: \.self) { provider in
                    Button(action: { voiceManager.config.provider = provider }) {
                        HStack {
                            Image(systemName: provider.icon)
                                .font(.title3)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(provider.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                Text(provider.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if voiceManager.config.provider == provider {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(voiceManager.config.provider == provider ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(voiceManager.config.provider == provider ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                switch voiceManager.config.provider {
                case .local:
                    VStack(alignment: .leading, spacing: 8) {
                        // Status indicator
                        HStack(spacing: 8) {
                            Circle()
                                .fill(voiceManager.localModelStatus == .ready ? Color.green :
                                      voiceManager.localModelStatus == .installing ? Color.orange : Color.red)
                                .frame(width: 10, height: 10)
                            Text(voiceManager.localModelStatusText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(voiceManager.localModelStatus == .ready ? .green :
                                                 voiceManager.localModelStatus == .installing ? .orange : .secondary)
                        }

                        // Model size picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Modèle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: Binding(
                                get: { pendingModelSize.isEmpty ? voiceManager.config.localModelSize : pendingModelSize },
                                set: { newValue in
                                    pendingModelSize = newValue
                                    modelSizeChanged = (newValue != voiceManager.config.localModelSize)
                                }
                            )) {
                                Text("Auto (recommandé)").tag("auto")
                                Text("0.6B (léger)").tag("0.6b")
                                Text("1.7B (qualité)").tag("1.7b")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            // Info text based on selection
                            Group {
                                switch (pendingModelSize.isEmpty ? voiceManager.config.localModelSize : pendingModelSize) {
                                case "0.6b":
                                    Text("Plus rapide, moins de RAM. Qualité correcte.")
                                case "1.7b":
                                    Text("Meilleure qualité. Nécessite 16 Go+ de RAM.")
                                default:
                                    Text("Choix automatique selon votre RAM (\(String(format: "%.0f", voiceManager.systemRAMGB)) Go détectés)")
                                }
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        }

                        // Restart server button (when model changed)
                        if modelSizeChanged {
                            Button(action: {
                                voiceManager.config.localModelSize = pendingModelSize
                                voiceManager.saveConfig()
                                modelSizeChanged = false
                                voiceManager.restartLocalServer()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Redémarrer le serveur")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }

                        if voiceManager.localModelStatus == .notInstalled {
                            Text("Qwen3-TTS tourne 100% sur ton Mac. Gratuit, privé, illimité.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: { voiceManager.installLocalModel() }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Installer Qwen3-TTS")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                        } else if voiceManager.localModelStatus == .installing {
                            ProgressView(value: voiceManager.installProgress)
                                .progressViewStyle(.linear)
                            Text(voiceManager.installStep)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if voiceManager.localModelStatus == .ready {
                            Text("Qwen3-TTS est installé et prêt. Aucune clé nécessaire.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Server status
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(voiceManager.localServerRunning ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(voiceManager.localServerRunning ? "Serveur actif, prêt à générer" : "Serveur en veille (se lance automatiquement)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onAppear {
                        pendingModelSize = voiceManager.config.localModelSize
                        modelSizeChanged = false
                    }

                case .fish:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clé API Fish Audio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("fm-...", text: $voiceManager.config.fishKey)
                            .textFieldStyle(.roundedBorder)
                        Link("Créer un compte (gratuit) →", destination: URL(string: "https://fish.audio")!)
                            .font(.caption)
                        Text("1h de génération gratuite par mois. Clonage vocal inclus.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .qwen:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clé API DashScope (Alibaba)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $voiceManager.config.qwenKey)
                            .textFieldStyle(.roundedBorder)
                        Link("Obtenir une clé (gratuit) →", destination: URL(string: "https://dashscope.console.aliyun.com/")!)
                            .font(.caption)
                        Text("500k tokens/mois gratuits. Clone en 10-20 sec d'audio.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                case .elevenLabs:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clé API ElevenLabs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("xi-...", text: $voiceManager.config.elevenLabsKey)
                            .textFieldStyle(.roundedBorder)
                        Link("Obtenir une clé →", destination: URL(string: "https://elevenlabs.io")!)
                            .font(.caption)
                    }

                case .openai:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clé API OpenAI")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $voiceManager.config.openaiKey)
                            .textFieldStyle(.roundedBorder)
                        Text("Voix")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $voiceManager.config.openaiVoice) {
                            Text("Alloy").tag("alloy")
                            Text("Echo").tag("echo")
                            Text("Fable").tag("fable")
                            Text("Onyx").tag("onyx")
                            Text("Nova").tag("nova")
                            Text("Shimmer").tag("shimmer")
                        }
                        .labelsHidden()
                    }

                case .system:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voix système")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Thomas", text: $voiceManager.config.systemVoice)
                            .textFieldStyle(.roundedBorder)
                        Text("Utilise `say -v ?` dans le terminal pour voir les voix disponibles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Auto-update section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mise à jour")
                        .font(.headline)

                    if autoUpdater.updateAvailable {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            VStack(alignment: .leading) {
                                Text("v\(autoUpdater.latestVersion) disponible")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Nouvelle version prête à installer")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if autoUpdater.isUpdating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(autoUpdater.updateStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Button(action: { autoUpdater.performUpdate() }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Mettre à jour")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let error = autoUpdater.updateError {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }

                            Button(action: { autoUpdater.performUpdate() }) {
                                Text("Réessayer")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("À jour (v\(autoUpdater.currentVersion))")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                autoUpdater.isChecking = true
                                autoUpdater.checkForUpdates()
                            }) {
                                if autoUpdater.isChecking {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(autoUpdater.isChecking)
                        }
                    }
                }

                Divider()

                HStack {
                    Button("Annuler") { showSettings = false }
                    Spacer()
                    Button("Sauvegarder") {
                        voiceManager.saveConfig()
                        showSettings = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    func generate() {
        voiceManager.generateSpeech(text: text, profile: selectedProfile, tone: selectedTone) { url in
            // Notification is sent from AppDelegate via observation
            // Audio auto-play is handled by onChange(of: voiceManager.lastGeneratedURL)
        }
    }

    func saveAudioAs(_ url: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.audio]
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }

    func copyFileToClipboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    func shareAudio(_ url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        if let button = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: button, preferredEdge: .minY)
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
