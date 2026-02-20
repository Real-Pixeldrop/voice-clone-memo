import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var voiceManager: VoiceManager
    @State private var currentTab = 0
    @State private var text = ""
    @State private var selectedProfile: VoiceProfile?
    @State private var showSettings = false
    @State private var newVoiceName = ""
    @State private var showNameInput = false

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
                    Image(systemName: "gear")
                        .font(.title3)
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
                    HStack {
                        TextField("Nom de la voix", text: $newVoiceName)
                            .textFieldStyle(.roundedBorder)
                        Button("OK") {
                            if !newVoiceName.isEmpty {
                                voiceManager.addVoiceFromRecording(name: newVoiceName)
                                newVoiceName = ""
                                showNameInput = false
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    // Record button
                    Button(action: {
                        if voiceManager.recorder.isRecording {
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

                    // Import button
                    Button(action: { voiceManager.importAudioFile() }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Importer")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)

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
                    Text("Enregistre ta voix ou importe un audio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(voiceManager.voiceProfiles) { profile in
                            HStack {
                                Image(systemName: "person.circle")
                                    .font(.title3)
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .font(.system(size: 13, weight: .medium))
                                    if profile.elevenLabsId != nil {
                                        Text("Clonée (ElevenLabs)")
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
