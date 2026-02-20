import Foundation
import AppKit

class SetupManager: ObservableObject {
    @Published var isSetupNeeded = true
    @Published var isSettingUp = false
    @Published var progress: Double = 0
    @Published var currentStep: String = ""
    @Published var error: String?
    @Published var isComplete = false
    @Published var isFirstLaunch = false

    private let installDir: URL
    private let serverScript: URL
    private let startScript: URL
    private let condaDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        installDir = home.appendingPathComponent(".voiceclonememo")
        serverScript = installDir.appendingPathComponent("server.py")
        startScript = installDir.appendingPathComponent("start.sh")
        condaDir = installDir.appendingPathComponent("miniconda3")

        checkSetup()
    }

    func checkSetup() {
        let serverExists = FileManager.default.fileExists(atPath: serverScript.path)
        let startExists = FileManager.default.fileExists(atPath: startScript.path)

        // Check if model has been downloaded before (cache exists)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hfCache = home.appendingPathComponent(".cache/huggingface/hub")
        let cacheExists = FileManager.default.fileExists(atPath: hfCache.path)
        if cacheExists {
            // Check if any qwen-tts model dir exists
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: hfCache.path)) ?? []
            let hasModel = contents.contains { $0.lowercased().contains("qwen") && $0.lowercased().contains("tts") }
            isFirstLaunch = !hasModel
        } else {
            isFirstLaunch = true
        }

        isSetupNeeded = !(serverExists && startExists)
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

        // Step 4: Copy server script (model downloads automatically on first run)
        updateUI(step: "Configuration du serveur local...", progress: 0.90)
        if !copyServerFiles() {
            failWith("Erreur lors de la copie des fichiers serveur.")
            return
        }

        // Step 5: Create start script
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

        // Check our dedicated install location first
        let dedicatedConda = condaDir.appendingPathComponent("bin/conda").path
        if FileManager.default.fileExists(atPath: dedicatedConda) {
            return dedicatedConda
        }

        // Check common conda locations (user may already have conda)
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
            if !path.isEmpty && FileManager.default.fileExists(atPath: path) { return path }
        }

        // Download and install Miniconda into our dedicated directory
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
        let installResult = shell("/bin/bash /tmp/miniconda.sh -b -p \(condaDir.path)")
        guard installResult.status == 0 else { return nil }

        // Clean up installer
        try? FileManager.default.removeItem(atPath: "/tmp/miniconda.sh")

        return dedicatedConda
    }

    private func createCondaEnv(conda: String) -> Bool {
        let resolvedCondaDir = URL(fileURLWithPath: conda).deletingLastPathComponent().deletingLastPathComponent()
        let envDir = resolvedCondaDir.appendingPathComponent("envs/vcm")

        // Check if env already exists by looking at the directory
        if FileManager.default.fileExists(atPath: envDir.appendingPathComponent("bin/python3").path) {
            return true
        }

        // Also check via conda env list
        let result = shell("\(conda) env list 2>/dev/null")
        if result.output.contains("vcm") {
            return true
        }

        // Accept TOS first (required since conda 24.x)
        _ = shell("\(conda) tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>&1")
        _ = shell("\(conda) tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>&1")

        let create = shell("\(conda) create -n vcm python=3.11 -y 2>&1")
        return create.status == 0
    }

    private func installDeps(conda: String) -> Bool {
        // Use conda run to ensure correct env
        updateUI(step: "Installation de PyTorch et qwen-tts (peut prendre quelques minutes)...", progress: 0.30)
        let deps = shell("\(conda) run -n vcm pip install --quiet torch torchaudio flask soundfile numpy psutil qwen-tts 2>&1")
        guard deps.status == 0 else {
            // Fallback: try with full pip path
            let resolvedCondaDir = URL(fileURLWithPath: conda).deletingLastPathComponent().deletingLastPathComponent()
            let pip = resolvedCondaDir.appendingPathComponent("envs/vcm/bin/pip").path
            if FileManager.default.fileExists(atPath: pip) {
                let r = shell("\(pip) install --quiet torch torchaudio flask soundfile numpy psutil qwen-tts 2>&1")
                guard r.status == 0 else { return false }
            } else {
                return false
            }
            return true
        }
        return true
    }

    private func copyServerFiles() -> Bool {
        let serverContent = Self.embeddedServerPy
        do {
            try serverContent.write(to: serverScript, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private func createStartScript(conda: String) {
        let resolvedCondaDir = URL(fileURLWithPath: conda).deletingLastPathComponent().deletingLastPathComponent()

        let script = """
        #!/bin/bash
        export PATH="\(resolvedCondaDir.path)/bin:$PATH"
        eval "$(\(resolvedCondaDir.path)/bin/conda shell.bash hook)"
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

    // MARK: - Embedded server.py

    static let embeddedServerPy = """
#!/usr/bin/env python3
\"\"\"Local Qwen3-TTS REST API server for VoiceCloneMemo.
Uses the official qwen-tts package with auto hardware detection.\"\"\"

import os
import json
import uuid
import time
import numpy as np

from flask import Flask, request, jsonify, send_file

app = Flask(__name__)

model = None
VOICES_DIR = os.path.expanduser("~/.voiceclonememo/voices")
OUTPUT_DIR = os.path.expanduser("~/.voiceclonememo/output")
os.makedirs(VOICES_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

def load_model():
    global model
    import torch
    import psutil
    from qwen_tts import Qwen3TTSModel

    total_ram_gb = psutil.virtual_memory().total / (1024**3)
    print(f"RAM: {total_ram_gb:.1f} Go")

    model_override = os.environ.get("MODEL_SIZE", "auto")
    if model_override == "0.6b":
        model_name = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
    elif model_override == "1.7b":
        model_name = "Qwen/Qwen3-TTS-12Hz-1.7B-Base"
    else:  # auto
        if total_ram_gb <= 12:
            model_name = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
        else:
            model_name = "Qwen/Qwen3-TTS-12Hz-1.7B-Base"

    if total_ram_gb <= 12:
        device = "cpu"
        dtype = torch.float32
    elif torch.backends.mps.is_available():
        device = "mps"
        dtype = torch.float32
    elif torch.cuda.is_available():
        device = "cuda:0"
        dtype = torch.bfloat16
    else:
        device = "cpu"
        dtype = torch.float32

    print(f"Modele: {model_name} | Device: {device}")
    model = Qwen3TTSModel.from_pretrained(model_name, device_map=device, dtype=dtype)
    print("Modele charge !")

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "model": "qwen3-tts"})

@app.route("/v1/clone", methods=["POST"])
def clone_voice():
    if "audio" not in request.files:
        return jsonify({"error": "No audio file"}), 400
    name = request.form.get("name", f"voice_{int(time.time())}")
    transcript = request.form.get("transcript", "")
    audio_file = request.files["audio"]
    voice_id = str(uuid.uuid4())[:8]
    voice_dir = os.path.join(VOICES_DIR, voice_id)
    os.makedirs(voice_dir, exist_ok=True)
    audio_path = os.path.join(voice_dir, "reference.wav")
    audio_file.save(audio_path)
    meta = {"name": name, "voice_id": voice_id, "audio": audio_path, "transcript": transcript}
    with open(os.path.join(voice_dir, "meta.json"), "w") as f:
        json.dump(meta, f)
    return jsonify({"voice_id": voice_id, "name": name})

@app.route("/v1/tts", methods=["POST"])
def text_to_speech():
    import soundfile as sf
    data = request.get_json()
    text = data.get("text", "")
    voice_id = data.get("voice_id", "")
    instruction = data.get("instruction", "")
    # audio_path allows the Swift app to pass a direct path to a reference audio
    audio_path_direct = data.get("audio_path", "")

    if not text:
        return jsonify({"error": "No text provided"}), 400

    try:
        ref_audio_path = None
        ref_text = None

        # Priority 1: direct audio path from the app
        if audio_path_direct and os.path.exists(audio_path_direct):
            ref_audio_path = audio_path_direct

        # Priority 2: voice_id lookup
        if not ref_audio_path and voice_id:
            voice_dir = os.path.join(VOICES_DIR, voice_id)
            ref_path = os.path.join(voice_dir, "reference.wav")
            meta_path = os.path.join(voice_dir, "meta.json")
            if os.path.exists(ref_path):
                ref_audio_path = ref_path
                if os.path.exists(meta_path):
                    with open(meta_path) as f:
                        meta = json.load(f)
                        ref_text = meta.get("transcript") or None

        prompt = text
        # Note: instruction/tone control only works with VoiceDesign models
        # Base models (0.6B, 1.7B) read instruction as text, so we skip it

        if ref_audio_path and os.path.exists(ref_audio_path):
            # Voice clone mode with reference audio
            print(f"TTS with voice clone: {ref_audio_path}, ref_text: {ref_text}")
            if ref_text:
                # ICL mode: best quality, needs transcript
                wavs, sr = model.generate_voice_clone(
                    text=prompt,
                    language="Auto",
                    ref_audio=ref_audio_path,
                    ref_text=ref_text,
                )
            else:
                # x-vector mode: clone by voice embedding only (no transcript)
                wavs, sr = model.generate_voice_clone(
                    text=prompt,
                    language="Auto",
                    ref_audio=ref_audio_path,
                    ref_text=None,
                    x_vector_only_mode=True,
                )
        else:
            # No reference audio - generate with default voice
            print("TTS without voice reference (default voice)")

            # Create a short silence file as dummy reference
            dummy_path = os.path.join(OUTPUT_DIR, "dummy_ref.wav")
            if not os.path.exists(dummy_path):
                silence = np.zeros(24000, dtype=np.float32)
                sf.write(dummy_path, silence, 24000)

            try:
                wavs, sr = model.generate_voice_clone(
                    text=prompt,
                    language="Auto",
                    ref_audio=dummy_path,
                    ref_text="silence",
                    x_vector_only_mode=True,
                )
            except Exception as e:
                print(f"x_vector_only_mode failed: {e}, trying direct generation...")
                wavs, sr = model.generate_voice_clone(
                    text=prompt,
                    language="Auto",
                    ref_audio=dummy_path,
                    ref_text="Hello, this is a test of the voice.",
                )

        output_path = os.path.join(OUTPUT_DIR, f"memo_{int(time.time())}.wav")
        sf.write(output_path, wavs[0], sr)
        return send_file(output_path, mimetype="audio/wav")

    except Exception as e:
        import traceback
        traceback.print_exc()
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
    print("Serveur Qwen3-TTS sur http://localhost:5123")
    app.run(host="127.0.0.1", port=5123, debug=False)
"""
}
