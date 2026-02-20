#!/usr/bin/env python3
"""Local Qwen3-TTS REST API server for VoiceCloneMemo."""

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
MODEL_PATH = os.path.expanduser("~/qwen3-tts/model-1.7b")
VOICES_DIR = os.path.expanduser("~/qwen3-tts/voices")
OUTPUT_DIR = os.path.expanduser("~/qwen3-tts/output")
os.makedirs(VOICES_DIR, exist_ok=True)
os.makedirs(OUTPUT_DIR, exist_ok=True)

def load_model():
    global model, processor
    import torch
    from transformers import AutoModelForCausalLM, AutoProcessor

    print("Chargement du modèle Qwen3-TTS 1.7B...")
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
    print("✅ Modèle chargé !")

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "model": "qwen3-tts-1.7b"})

@app.route("/v1/clone", methods=["POST"])
def clone_voice():
    """Save a voice reference audio for cloning."""
    if "audio" not in request.files:
        return jsonify({"error": "No audio file"}), 400

    name = request.form.get("name", f"voice_{int(time.time())}")
    audio_file = request.files["audio"]

    voice_id = str(uuid.uuid4())[:8]
    voice_dir = os.path.join(VOICES_DIR, voice_id)
    os.makedirs(voice_dir, exist_ok=True)

    audio_path = os.path.join(voice_dir, "reference.wav")
    audio_file.save(audio_path)

    # Save metadata
    meta = {"name": name, "voice_id": voice_id, "audio": audio_path}
    with open(os.path.join(voice_dir, "meta.json"), "w") as f:
        json.dump(meta, f)

    return jsonify({"voice_id": voice_id, "name": name})

@app.route("/v1/tts", methods=["POST"])
def text_to_speech():
    """Generate speech from text, optionally with a cloned voice."""
    import torch
    import soundfile as sf

    data = request.get_json()
    text = data.get("text", "")
    voice_id = data.get("voice_id", "")

    if not text:
        return jsonify({"error": "No text provided"}), 400

    try:
        # Prepare inputs
        if voice_id and os.path.exists(os.path.join(VOICES_DIR, voice_id, "reference.wav")):
            ref_audio = os.path.join(VOICES_DIR, voice_id, "reference.wav")
            # Voice cloning with reference
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

        # Decode audio
        audio_array = processor.decode(output[0], return_tensors=False)

        # Save to file
        output_path = os.path.join(OUTPUT_DIR, f"memo_{int(time.time())}.wav")
        sf.write(output_path, audio_array, 24000)

        return send_file(output_path, mimetype="audio/wav")

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/v1/voices", methods=["GET"])
def list_voices():
    """List saved voice profiles."""
    voices = []
    for d in os.listdir(VOICES_DIR):
        meta_path = os.path.join(VOICES_DIR, d, "meta.json")
        if os.path.exists(meta_path):
            with open(meta_path) as f:
                voices.append(json.load(f))
    return jsonify({"voices": voices})

if __name__ == "__main__":
    load_model()
    print("🎙️ Qwen3-TTS serveur local sur http://localhost:5123")
    app.run(host="0.0.0.0", port=5123, debug=False)
