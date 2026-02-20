import Foundation
import AppKit

class SetupManager: ObservableObject {
    @Published var isSetupNeeded = true
    @Published var isSettingUp = false
    @Published var progress: Double = 0
    @Published var currentStep: String = ""
    @Published var error: String?
    @Published var isComplete = false

    private let installDir: URL
    private let modelDir: URL
    private let serverScript: URL
    private let startScript: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        installDir = home.appendingPathComponent(".voiceclonememo")
        modelDir = installDir.appendingPathComponent("model")
        serverScript = installDir.appendingPathComponent("server.py")
        startScript = installDir.appendingPathComponent("start.sh")

        checkSetup()
    }

    func checkSetup() {
        // Check if model is downloaded and server script exists
        let modelExists = FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("config.json").path)
        let serverExists = FileManager.default.fileExists(atPath: serverScript.path)
        let startExists = FileManager.default.fileExists(atPath: startScript.path)

        isSetupNeeded = !(modelExists && serverExists && startExists)
        isComplete = !isSetupNeeded
    }

    func startSetup() {
        isSettingUp = true
        error = nil
        progress = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runSetup()
        }
    }

    func skipSetup() {
        // User can skip if they want to use cloud providers only
        isSetupNeeded = false
        isComplete = true
    }

    private func updateUI(step: String, progress: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.currentStep = step
            self?.progress = progress
        }
    }

    private func failWith(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.error = message
            self?.isSettingUp = false
        }
    }

    private func runSetup() {
        // Create install directory
        try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        // Step 1: Check/Install Miniconda
        updateUI(step: "Vérification de Python...", progress: 0.05)
        let condaPath = installConda()
        guard let conda = condaPath else {
            failWith("Impossible d'installer Miniconda. Vérifie ta connexion internet.")
            return
        }

        // Step 2: Create conda env
        updateUI(step: "Création de l'environnement Python...", progress: 0.15)
        if !createCondaEnv(conda: conda) {
            failWith("Erreur lors de la création de l'environnement Python.")
            return
        }

        // Step 3: Install Python deps
        updateUI(step: "Installation de PyTorch (peut prendre quelques minutes)...", progress: 0.25)
        if !installDeps(conda: conda) {
            failWith("Erreur lors de l'installation des dépendances Python.")
            return
        }

        // Step 4: Download model
        updateUI(step: "Téléchargement du modèle Qwen3-TTS (~4 Go)...", progress: 0.40)
        if !downloadModel(conda: conda) {
            failWith("Erreur lors du téléchargement du modèle. Vérifie ta connexion internet.")
            return
        }

        // Step 5: Copy server script
        updateUI(step: "Configuration du serveur local...", progress: 0.90)
        if !copyServerFiles() {
            failWith("Erreur lors de la copie des fichiers serveur.")
            return
        }

        // Step 6: Create start script
        updateUI(step: "Finalisation...", progress: 0.95)
        createStartScript(conda: conda)

        // Done
        DispatchQueue.main.async { [weak self] in
            self?.progress = 1.0
            self?.currentStep = "Installation terminée !"
            self?.isSettingUp = false
            self?.isSetupNeeded = false
            self?.isComplete = true
        }
    }

    // MARK: - Steps

    private func installConda() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Check common conda locations
        let condaPaths = [
            home.appendingPathComponent("miniconda3/bin/conda").path,
            home.appendingPathComponent("anaconda3/bin/conda").path,
            home.appendingPathComponent("miniforge3/bin/conda").path,
            "/usr/local/bin/conda",
            "/opt/homebrew/bin/conda"
        ]

        for path in condaPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Check system PATH
        let whichResult = shell("/usr/bin/which conda")
        if whichResult.status == 0 {
            let path = whichResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }

        // Download and install Miniconda
        updateUI(step: "Téléchargement de Miniconda...", progress: 0.08)

        let arch = shell("/usr/bin/uname -m").output.trimmingCharacters(in: .whitespacesAndNewlines)
        let condaURL: String
        if arch == "arm64" {
            condaURL = "https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh"
        } else {
            condaURL = "https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"
        }

        let dlResult = shell("/usr/bin/curl -sL \(condaURL) -o /tmp/miniconda.sh")
        guard dlResult.status == 0 else { return nil }

        updateUI(step: "Installation de Miniconda...", progress: 0.12)
        let condaBin = home.appendingPathComponent("miniconda3/bin/conda").path
        let installResult = shell("/bin/bash /tmp/miniconda.sh -b -p \(home.path)/miniconda3")
        guard installResult.status == 0 else { return nil }

        // Init conda for shells
        _ = shell("\(condaBin) init bash zsh 2>/dev/null")

        return condaBin
    }

    private func createCondaEnv(conda: String) -> Bool {
        let condaDir = URL(fileURLWithPath: conda).deletingLastPathComponent().deletingLastPathComponent()
        let envDir = condaDir.appendingPathComponent("envs/vcm")

        // Check if env already exists by looking at the directory
        if FileManager.default.fileExists(atPath: envDir.appendingPathComponent("bin/python3").path) {
            return true
        }

        // Also check via conda env list
        let result = shell("\(conda) env list 2>/dev/null")
        if result.output.contains("vcm") {
            return true
        }

        let create = shell("\(conda) create -n vcm python=3.11 -y 2>&1")
        return create.status == 0
    }

    private func installDeps(conda: String) -> Bool {
        // Use conda run to ensure correct env
        updateUI(step: "Installation de PyTorch (peut prendre quelques minutes)...", progress: 0.30)
        let torch = shell("\(conda) run -n vcm pip install --quiet torch torchaudio 2>&1")
        guard torch.status == 0 else {
            // Fallback: try with full pip path
            let condaDir = URL(fileURLWithPath: conda).deletingLastPathComponent().deletingLastPathComponent()
            let pip = condaDir.appendingPathComponent("envs/vcm/bin/pip").path
            if FileManager.default.fileExists(atPath: pip) {
                let r = shell("\(pip) install --quiet torch torchaudio 2>&1")
                guard r.status == 0 else { return false }
            } else {
                return false
            }
            return true
        }

        updateUI(step: "Installation des dépendances audio...", progress: 0.35)
        let deps = shell("\(conda) run -n vcm pip install --quiet flask soundfile scipy transformers accelerate huggingface_hub 2>&1")
        return deps.status == 0
    }

    private func downloadModel(conda: String) -> Bool {
        // Check if model already downloaded
        if FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("config.json").path) {
            return true
        }

        let script = """
        from huggingface_hub import snapshot_download
        snapshot_download('Qwen/Qwen3-TTS-12Hz-1.7B-Base', local_dir='\(modelDir.path)')
        print('OK')
        """

        let tempScript = installDir.appendingPathComponent("download_model.py")
        try? script.write(to: tempScript, atomically: true, encoding: .utf8)

        // Start download with progress monitoring
        let task = Process()
        let outputPipe = Pipe()

        // Always use conda run for reliable env activation
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "\(conda) run -n vcm python3 \(tempScript.path) 2>&1"]

        task.standardOutput = outputPipe
        task.standardError = outputPipe

        // Monitor progress in background
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            // Estimate progress based on model directory size
            let size = self?.directorySize(self?.modelDir ?? URL(fileURLWithPath: "/")) ?? 0
            let expectedSize: UInt64 = 4_000_000_000 // ~4 GB
            let downloadProgress = min(Double(size) / Double(expectedSize), 0.99)
            let overallProgress = 0.40 + (downloadProgress * 0.48) // 40% to 88%
            self?.updateUI(
                step: "Téléchargement du modèle (\(self?.formatBytes(size) ?? "0 MB") / ~4 Go)...",
                progress: overallProgress
            )
        }

        do {
            try task.run()
            task.waitUntilExit()
            progressTimer.invalidate()
        } catch {
            progressTimer.invalidate()
            return false
        }

        try? FileManager.default.removeItem(at: tempScript)
        return task.terminationStatus == 0
    }

    private func copyServerFiles() -> Bool {
        // Get the server.py from the app bundle or embedded resource
        let serverContent = Self.embeddedServerPy
        do {
            try serverContent.write(to: serverScript, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private func createStartScript(conda: String) {
        let condaDir = URL(fileURLWithPath: conda).deletingLastPathComponent().deletingLastPathComponent()

        let script = """
        #!/bin/bash
        export PATH="\(condaDir.path)/bin:$PATH"
        eval "$(\(condaDir.path)/bin/conda shell.bash hook)"
        conda activate vcm
        python3 ~/.voiceclonememo/server.py
        """

        try? script.write(to: startScript, atomically: true, encoding: .utf8)

        // chmod +x
        _ = shell("/bin/chmod +x \(startScript.path)")
    }

    // MARK: - Helpers

    private func shell(_ command: String) -> (status: Int32, output: String) {
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
            let output = String(data: data, encoding: .utf8) ?? ""
            return (task.terminationStatus, output)
        } catch {
            return (-1, "")
        }
    }

    private func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb > 1000 {
            return String(format: "%.1f Go", mb / 1000)
        }
        return String(format: "%.0f Mo", mb)
    }

    // MARK: - Embedded server.py

    static let embeddedServerPy = """
#!/usr/bin/env python3
\"\"\"Local Qwen3-TTS REST API server for VoiceCloneMemo.\"\"\"

import os
import sys
import json
import base64
import tempfile
import uuid
import time
from pathlib import Path

from flask import Flask, request, jsonify, send_file

app = Flask(__name__)

# Globals
model = None
processor = None
MODEL_PATH = os.path.expanduser("~/.voiceclonememo/model")
VOICES_DIR = os.path.expanduser("~/.voiceclonememo/voices")
OUTPUT_DIR = os.path.expanduser("~/.voiceclonememo/output")
os.makedirs(VOICES_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

def load_model():
    global model, processor
    import torch
    from transformers import AutoModelForCausalLM, AutoProcessor

    print("Chargement du modele Qwen3-TTS 1.7B...")
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"Device: {device}")

    processor = AutoProcessor.from_pretrained(MODEL_PATH, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        trust_remote_code=True,
        torch_dtype=torch.float32,
        device_map=device,
        attn_implementation="sdpa"
    )
    print("Modele charge !")

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "model": "qwen3-tts-1.7b"})

@app.route("/v1/clone", methods=["POST"])
def clone_voice():
    if "audio" not in request.files:
        return jsonify({"error": "No audio file"}), 400

    name = request.form.get("name", f"voice_{int(time.time())}")
    audio_file = request.files["audio"]

    voice_id = str(uuid.uuid4())[:8]
    voice_dir = os.path.join(VOICES_DIR, voice_id)
    os.makedirs(voice_dir, exist_ok=True)

    audio_path = os.path.join(voice_dir, "reference.wav")
    audio_file.save(audio_path)

    meta = {"name": name, "voice_id": voice_id, "audio": audio_path}
    with open(os.path.join(voice_dir, "meta.json"), "w") as f:
        json.dump(meta, f)

    return jsonify({"voice_id": voice_id, "name": name})

@app.route("/v1/tts", methods=["POST"])
def text_to_speech():
    import torch
    import soundfile as sf

    data = request.get_json()
    text = data.get("text", "")
    voice_id = data.get("voice_id", "")

    if not text:
        return jsonify({"error": "No text provided"}), 400

    try:
        if voice_id and os.path.exists(os.path.join(VOICES_DIR, voice_id, "reference.wav")):
            ref_audio = os.path.join(VOICES_DIR, voice_id, "reference.wav")
            inputs = processor(
                text=text,
                audio=ref_audio,
                return_tensors="pt",
                trust_remote_code=True
            )
        else:
            inputs = processor(
                text=text,
                return_tensors="pt",
                trust_remote_code=True
            )

        device = "mps" if torch.backends.mps.is_available() else "cpu"
        inputs = {k: v.to(device) if hasattr(v, 'to') else v for k, v in inputs.items()}

        with torch.no_grad():
            output = model.generate(**inputs, max_new_tokens=2048)

        audio_array = processor.decode(output[0], return_tensors=False)

        output_path = os.path.join(OUTPUT_DIR, f"memo_{int(time.time())}.wav")
        sf.write(output_path, audio_array, 24000)

        return send_file(output_path, mimetype="audio/wav")

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/v1/voices", methods=["GET"])
def list_voices():
    voices = []
    for d in os.listdir(VOICES_DIR):
        meta_path = os.path.join(VOICES_DIR, d, "meta.json")
        if os.path.exists(meta_path):
            with open(meta_path) as f:
                voices.append(json.load(f))
    return jsonify({"voices": voices})

if __name__ == "__main__":
    load_model()
    print("Qwen3-TTS serveur local sur http://localhost:5123")
    app.run(host="0.0.0.0", port=5123, debug=False)
"""
}
