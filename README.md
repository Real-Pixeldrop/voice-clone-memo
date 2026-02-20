# VoiceCloneMemo 🎙️

Clone your voice, type text, get audio memos in your voice. All from the menu bar.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- 🎙️ Record your voice (10-20 sec) to create a voice profile
- 📁 Or drop an existing audio file to clone any voice
- ⌨️ Type text → get audio in your cloned voice
- ▶️ Listen, copy, share, or reveal in Finder
- 🔄 Multiple voice profiles
- 🪶 Native Swift — 150 Ko

## Install

### Download (recommended)

1. Download [VoiceCloneMemo-macOS.zip](https://github.com/Real-Pixeldrop/voice-clone-memo/releases/latest/download/VoiceCloneMemo-macOS.zip)
2. Unzip
3. Double-click `VoiceCloneMemo`
4. Done — the 🎙️ icon appears in your menu bar

### Terminal one-liner

```bash
curl -sL https://github.com/Real-Pixeldrop/voice-clone-memo/releases/latest/download/VoiceCloneMemo-macOS.zip -o /tmp/vcm.zip && sudo unzip -o /tmp/vcm.zip -d /usr/local/bin && VoiceCloneMemo &
```

### From source

```bash
git clone https://github.com/Real-Pixeldrop/voice-clone-memo.git
cd voice-clone-memo
swift build -c release
.build/release/VoiceCloneMemo
```

## Setup

1. Launch VoiceCloneMemo
2. Click ⚙️ → choose your voice provider:
   - **ElevenLabs** — voice cloning, ultra realistic (needs API key)
   - **OpenAI TTS** — high quality voices, no cloning (needs API key)
   - **System voice (macOS)** — free, offline, basic

## Usage

1. Go to **Voix** tab → record 10-20 sec of your voice (or import an audio file)
2. Go to **Générer** tab → select your voice profile
3. Type your text
4. Click **Générer le mémo vocal**
5. Listen, copy, or share

## Voice Cloning Tips

- **10-20 seconds** of clean audio for best results
- Quiet environment, no background noise
- Speak naturally, varied sentences
- WAV format preferred for imports

## Providers

| Provider | Clone | Quality | Cost |
|----------|-------|---------|------|
| ElevenLabs | Yes | Excellent | Pay per use |
| OpenAI TTS | No | Very good | Pay per use |
| System (macOS) | No | Basic | Free |

## Privacy

All config and voice data stored locally in `~/Library/Application Support/VoiceCloneMemo/`. Audio files never leave your machine unless you share them.

## License

MIT
