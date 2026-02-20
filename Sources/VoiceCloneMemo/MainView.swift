import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var voiceManager: VoiceManager
    @ObservedObject var autoUpdater: AutoUpdater
    @State private var currentTab = 0
    @State private var text = ""
    @State private var selectedProfile: VoiceProfile?
    @State private var showSettings = false
    @State private var newVoiceName = ""
    @State private var newVoiceTranscript = ""
    @State private var showNameInput = false
    @State private var showYouTube = false
    @State private var youtubeURL = ""
    @State private var ytStartTime = ""
    @State private var ytEndTime = ""
    @State private var ytVoiceName = ""

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

            // Text input
            TextEditor(text: $text)
                .font(.body)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                .padding(.horizontal)

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

            // Last generated
            if let lastURL = voiceManager.lastGeneratedURL {
                HStack {
                    Button(action: { playAudio(lastURL) }) {
                        HStack {
                            Image(systemName: "play.circle")
                            Text("Écouter")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)

                    Button(action: { copyToClipboard(lastURL) }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copier")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)

                    Button(action: { shareAudio(lastURL) }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Partager")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)

                    Button(action: { revealInFinder(lastURL) }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Finder")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 8)
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

                HStack(spacing: 12) {
                    // Record button
                    Button(action: {
                        if voiceManager.recorder.isRecording {
                            voiceManager.recorder.stopRecording()
                            showNameInput = true
                        } else {
                            voiceManager.recorder.startRecording()
                        }
                    }) {
                        HStack {
                            Image(systemName: voiceManager.recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title2)
                                .foregroundColor(voiceManager.recorder.isRecording ? .red : .accentColor)
                            VStack(alignment: .leading) {
                                Text(voiceManager.recorder.isRecording ? "Arrêter" : "Enregistrer ma voix")
                                    .font(.system(size: 13, weight: .medium))
                                if voiceManager.recorder.isRecording {
                                    Text(String(format: "%.1fs", voiceManager.recorder.recordingTime))
                                        .font(.caption)
                                        .foregroundColor(.red)
                                } else {
                                    Text("10-20 sec recommandé")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
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

                        if voiceManager.localModelStatus == .notInstalled {
                            Text("Qwen3-TTS tourne 100% sur ton Mac. Gratuit, privé, illimité.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: { voiceManager.installLocalModel() }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Installer Qwen3-TTS (~4 Go)")
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
        voiceManager.generateSpeech(text: text, profile: selectedProfile) { url in
            if let url = url {
                playAudio(url)
            }
        }
    }

    func playAudio(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copyToClipboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
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
