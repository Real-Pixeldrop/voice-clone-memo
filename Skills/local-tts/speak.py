#!/usr/bin/env python3
"""Local TTS CLI - Generate speech using Qwen3-TTS local server."""

import sys
import os
import json
import argparse
import time
import urllib.request
import urllib.error

SERVER = "http://localhost:5123"
OUTPUT_DIR = os.path.expanduser("~/.clawdbot/media/tts")
os.makedirs(OUTPUT_DIR, exist_ok=True)


def check_server():
    """Check if local TTS server is running."""
    try:
        req = urllib.request.urlopen(f"{SERVER}/health", timeout=2)
        return req.status == 200
    except Exception:
        return False


def list_voices():
    """List available cloned voices."""
    try:
        req = urllib.request.urlopen(f"{SERVER}/v1/voices", timeout=5)
        data = json.loads(req.read())
        voices = data.get("voices", [])
        if not voices:
            print("Aucune voix clonée. Utilise VoiceCloneMemo pour en créer.")
            return
        for v in voices:
            print(f"  {v.get('voice_id', '?')} - {v.get('name', 'Sans nom')}")
    except Exception as e:
        print(f"Erreur: {e}", file=sys.stderr)
        sys.exit(1)


def generate(text, voice_id=None):
    """Generate speech and return the file path."""
    if not check_server():
        print("Erreur: serveur local non démarré. Lance VoiceCloneMemo ou:", file=sys.stderr)
        print("  bash ~/.voiceclonememo/start.sh", file=sys.stderr)
        sys.exit(1)

    payload = {"text": text}
    if voice_id:
        payload["voice_id"] = voice_id

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{SERVER}/v1/tts",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        resp = urllib.request.urlopen(req, timeout=120)
        audio_data = resp.read()

        output_path = os.path.join(OUTPUT_DIR, f"tts_{int(time.time())}.wav")
        with open(output_path, "wb") as f:
            f.write(audio_data)

        # Print path for Clawdbot to pick up
        print(output_path)
        return output_path

    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="ignore")
        print(f"Erreur API: {e.code} - {error_body}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Erreur: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Local TTS - Qwen3 voice generation")
    parser.add_argument("text", nargs="?", help="Text to speak")
    parser.add_argument("--voice", "-v", help="Voice ID for cloned voice")
    parser.add_argument("--list", "-l", action="store_true", help="List available voices")
    parser.add_argument("--status", "-s", action="store_true", help="Check server status")

    args = parser.parse_args()

    if args.status:
        if check_server():
            print("✅ Serveur local Qwen3-TTS en ligne")
        else:
            print("❌ Serveur local non démarré")
        sys.exit(0)

    if args.list:
        list_voices()
        sys.exit(0)

    if not args.text:
        parser.print_help()
        sys.exit(1)

    generate(args.text, args.voice)


if __name__ == "__main__":
    main()
