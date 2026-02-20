# Local TTS - Voice Generation for Agents

Generate voice audio locally using Qwen3-TTS. No API key, no cost, runs on your Mac.

## When to use
- When you need to send a voice message instead of text
- When you want to speak with a cloned voice
- When the user asks for audio/vocal output
- Replaces ElevenLabs (sag) for free local TTS

## Prerequisites
- VoiceCloneMemo local server running on localhost:5123
- Install: `git clone https://github.com/Real-Pixeldrop/voice-clone-memo.git && cd voice-clone-memo/Scripts && bash install-local-tts.sh`

## Usage

### Generate speech (default voice)
```bash
python3 ~/.clawdbot/skills/local-tts/speak.py "Bonjour Akli, comment ça va ?"
```

### Generate speech with cloned voice
```bash
python3 ~/.clawdbot/skills/local-tts/speak.py "Bonjour" --voice VOICE_ID
```

### List available voices
```bash
python3 ~/.clawdbot/skills/local-tts/speak.py --list
```

### Check server status
```bash
curl -s http://localhost:5123/health
```

## Output
The script outputs the path to the generated audio file. Use this path with the `message` tool to send as a voice message:

```
message send --media /path/to/audio.wav --target USER
```

## Integration with Clawdbot
After generating audio, send it via iMessage:
```bash
AUDIO=$(python3 ~/.clawdbot/skills/local-tts/speak.py "Message vocal")
# Then use message tool with media=$AUDIO
```
