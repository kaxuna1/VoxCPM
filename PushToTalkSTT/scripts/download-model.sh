#!/usr/bin/env bash
# download-model.sh — Download the WhisperKit CoreML model (openai_whisper-small, multilingual)
# from HuggingFace into PushToTalkSTT/Resources/ for bundling with the app.
#
# Usage: ./scripts/download-model.sh
# Idempotent: skips download if model directory already contains .mlmodelc files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="$PROJECT_ROOT/PushToTalkSTT/Resources"
MODEL_DIR="$DEST_DIR/openai_whisper-small"

# Skip if model already downloaded
if [ -d "$MODEL_DIR" ] && ls "$MODEL_DIR"/*.mlmodelc &>/dev/null; then
    echo "Model already exists at $MODEL_DIR — skipping download."
    exit 0
fi

# Ensure hf CLI is available (huggingface_hub >= 1.0 ships 'hf' instead of 'huggingface-cli')
if ! command -v hf &>/dev/null; then
    # Try the user-local Python bin path on macOS (pip3 install --user)
    export PATH="$HOME/Library/Python/3.9/bin:$PATH"
fi

if ! command -v hf &>/dev/null; then
    echo "ERROR: hf CLI not found. Install with: pip3 install huggingface_hub" >&2
    exit 1
fi

echo "Downloading openai_whisper-small model to $DEST_DIR ..."
mkdir -p "$DEST_DIR"

hf download argmaxinc/whisperkit-coreml \
    --include "openai_whisper-small/*" \
    --local-dir "$DEST_DIR"

# The download puts files under DEST_DIR/openai_whisper-small/
if [ -d "$MODEL_DIR" ]; then
    echo "Download complete. Model files:"
    ls -la "$MODEL_DIR/"
else
    echo "ERROR: Expected model directory not found at $MODEL_DIR" >&2
    exit 1
fi
