# Voice Clone Memo

Clone ta voix, tape du texte, obtiens un audio avec TA voix. Pour les notes vocales sans parler.

## Download

[Télécharger VoiceCloneMemo.zip](https://github.com/Real-Pixeldrop/voice-clone-memo/releases/latest/download/VoiceCloneMemo.zip)

1. Télécharge le zip
2. Dézipe
3. Double-clic sur VoiceCloneMemo
4. Au premier lancement, l'app installe Qwen3-TTS automatiquement (~4 Go, 10-15 min)
5. C'est prêt. Pour toujours. Gratuit. 100% local.

## Comment ça marche

1. **Clone ta voix** : enregistre 10-20 secondes de ta voix (ou importe un audio/vidéo/YouTube)
2. **Tape du texte** : écris ce que tu veux dire
3. **Génère** : l'app crée un audio avec ta voix clonée
4. **Partage** : écoute, copie ou partage le mémo vocal

## Providers

| Provider | Prix | Clone vocal | Offline |
|----------|------|-------------|---------|
| **Qwen3 Local** | Gratuit | Oui | Oui |
| Fish Audio | Gratuit (1h/mois) | Oui | Non |
| Qwen3 Cloud | Gratuit (500k tokens/mois) | Oui | Non |
| ElevenLabs | Payant | Oui | Non |
| OpenAI TTS | Payant | Non | Non |
| Voix système | Gratuit | Non | Oui |

Qwen3 Local est le défaut. Tout tourne sur ton Mac, rien ne passe par le cloud.

## From source

```bash
git clone https://github.com/Real-Pixeldrop/voice-clone-memo.git
cd voice-clone-memo/VoiceCloneMemo
swift build -c release
cp -r .build/release/VoiceCloneMemo.app /Applications/ 2>/dev/null || \
  cp .build/release/VoiceCloneMemo /Applications/
```

## One-liner install

```bash
curl -sL https://github.com/Real-Pixeldrop/voice-clone-memo/releases/latest/download/VoiceCloneMemo.zip -o /tmp/vcm.zip && unzip -o /tmp/vcm.zip -d /Applications/ && xattr -cr /Applications/VoiceCloneMemo.app && open /Applications/VoiceCloneMemo.app
```

## macOS bloque l'app ?

Si macOS dit "endommagé" ou refuse d'ouvrir, lance dans le terminal :
```bash
xattr -cr /Applications/VoiceCloneMemo.app
```
Puis double-clic. C'est normal pour les apps hors App Store.

## Requis

- macOS 13+
- 8 Go RAM minimum (pour Qwen3 local)
- ~5 Go d'espace disque (modèle + dépendances)
