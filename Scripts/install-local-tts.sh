#!/bin/bash
set -e

echo "🎙️ VoiceCloneMemo - Installation locale Qwen3-TTS"
echo "==================================================="
echo ""

INSTALL_DIR="$HOME/.voiceclonememo"
mkdir -p "$INSTALL_DIR"

# 1. Miniconda
if ! command -v conda &> /dev/null && [ ! -f "$HOME/miniconda3/bin/conda" ]; then
    echo "[1/5] Installation Miniconda..."
    curl -sL https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh -o /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
    eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
    "$HOME/miniconda3/bin/conda" init bash zsh 2>/dev/null || true
else
    echo "[1/5] Miniconda OK"
    eval "$($HOME/miniconda3/bin/conda shell.bash hook 2>/dev/null)" 2>/dev/null || eval "$(conda shell.bash hook)"
fi

export PATH="$HOME/miniconda3/bin:$PATH"

# 2. Accept TOS + Conda env
echo "[2/5] Environnement Python..."
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true
conda create -n vcm python=3.11 -y 2>/dev/null || true
conda activate vcm

# 3. Python deps
echo "[3/5] Dépendances Python..."
pip install --quiet torch torchvision torchaudio
pip install --quiet flask soundfile scipy transformers accelerate huggingface_hub

# 4. Download model
echo "[4/5] Téléchargement modèle Qwen3-TTS 1.7B (~4 Go)..."
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('Qwen/Qwen3-TTS-12Hz-1.7B-Base', local_dir='$INSTALL_DIR/model')
print('OK')
"

# 5. Copy server script
echo "[5/5] Configuration serveur local..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/server.py" "$INSTALL_DIR/server.py" 2>/dev/null || \
curl -sL "https://raw.githubusercontent.com/Real-Pixeldrop/voice-clone-memo/main/Scripts/server.py" -o "$INSTALL_DIR/server.py"

# Create start script
cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash
eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
conda activate vcm
python3 ~/.voiceclonememo/server.py
EOF
chmod +x "$INSTALL_DIR/start.sh"

echo ""
echo "✅ Installation terminée !"
echo ""
echo "L'app VoiceCloneMemo lancera le serveur automatiquement."
echo "Tout est dans ~/.voiceclonememo/"
