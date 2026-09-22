#!/usr/bin/env bash
# install.sh — set up the meeting-recorder toolchain on a Linux box (Debian/Ubuntu tested).
#
#   bash install.sh            # everything below, idempotent
#   bash install.sh --cpu      # skip the Vulkan (GPU) build attempt
#   bash install.sh --no-model # skip model downloads (~2.2 GB)
#
# What it does
#   1. Checks/installs apt packages: ffmpeg, cmake, build tools, Vulkan headers + glslc (for the GPU build).
#      Uses sudo only for apt; everything else stays in $HOME.
#   2. Clones and builds whisper.cpp (pinned tag) into ~/.local/share/whisper.cpp:
#      Vulkan build (any Vulkan GPU: Intel/AMD/NVIDIA via Mesa or vendor drivers) with a CPU fallback.
#   3. Downloads the large-v3-turbo model (1.6 GB) and the silero VAD model (1 MB).
#   4. Symlinks record / transcribe / whisper-cli into ~/.local/bin.
#   5. Creates ~/.config/meeting-recorder/config.json from config.example.json if missing.
#   6. Tells you the two manual steps: `rclone config` (Google Drive, scope drive) and editing the config.
#
# Notes: the model download scripts are the ones shipped inside the pinned whisper.cpp checkout
# (they fetch from Hugging Face over https). Everything else is apt or a pinned git tag.
set -euo pipefail

HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SKILL_DIR=$(dirname "$HERE")
WHISPER_TAG="${WHISPER_TAG:-v1.9.4}"
WHISPER_DIR="${WHISPER_DIR:-$HOME/.local/share/whisper.cpp}"
JOBS="${JOBS:-$(( $(nproc) > 8 ? 8 : $(nproc) ))}"
CPU_ONLY=0; NO_MODEL=0
for a in "$@"; do case "$a" in --cpu) CPU_ONLY=1 ;; --no-model) NO_MODEL=1 ;; -h|--help) sed -n '2,18p' "$0"; exit 0 ;; *) echo "unknown flag: $a" >&2; exit 1 ;; esac; done

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

say "1/6 system packages"
GPU_PKGS=(libvulkan-dev glslc vulkan-tools)
missing=()
for p in ffmpeg cmake g++ git curl python3 rclone setsid; do have "$p" || missing+=("$p"); done
if [ "$CPU_ONLY" = 0 ]; then
  { have glslc && [ -f /usr/include/vulkan/vulkan.h ]; } || missing+=("vulkan-toolchain")
fi
if [ ${#missing[@]} -gt 0 ]; then
  echo "missing: ${missing[*]}"
  if have apt-get; then
    APT=(ffmpeg cmake build-essential git curl python3 rclone util-linux); [ "$CPU_ONLY" = 0 ] && APT+=("${GPU_PKGS[@]}")
    echo "running: sudo apt-get install -y ${APT[*]}"
    sudo apt-get install -y "${APT[@]}"
  else
    echo "install the equivalents of: ffmpeg cmake build-essential git curl python3 rclone util-linux ${GPU_PKGS[*]}"; exit 1
  fi
else
  echo "all present"
fi
if ! (have wpctl || have pactl); then
  echo "WARNING: neither wpctl (pipewire) nor pactl (pulseaudio-utils) found; record needs one of them."
fi

say "2/6 whisper.cpp $WHISPER_TAG in $WHISPER_DIR"
mkdir -p "$(dirname "$WHISPER_DIR")"
if [ ! -d "$WHISPER_DIR/.git" ]; then
  git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp "$WHISPER_DIR"
else
  echo "already cloned"
fi
cd "$WHISPER_DIR"
BIN=""
if [ "$CPU_ONLY" = 0 ]; then
  # ggml-vulkan needs the SPIRV-Headers package; distro packages often lack the CMake config, so we
  # install it into a user prefix and point both CMAKE_PREFIX_PATH and the include path at it.
  SPV="$HOME/.local/share/spirv-headers"
  if [ ! -f "$SPV/include/spirv/unified1/spirv.hpp" ]; then
    [ -d "$HOME/.local/share/SPIRV-Headers" ] || git clone --depth 1 https://github.com/KhronosGroup/SPIRV-Headers "$HOME/.local/share/SPIRV-Headers"
    cmake -S "$HOME/.local/share/SPIRV-Headers" -B "$HOME/.local/share/SPIRV-Headers/build" -DCMAKE_INSTALL_PREFIX="$SPV" >/dev/null
    cmake --install "$HOME/.local/share/SPIRV-Headers/build" >/dev/null
  fi
  if [ ! -x build-vulkan/bin/whisper-cli ]; then
    echo "building with Vulkan (GPU)…"
    if cmake -B build-vulkan -DGGML_VULKAN=1 -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$SPV" \
         -DCMAKE_CXX_FLAGS="-I$SPV/include" -DCMAKE_C_FLAGS="-I$SPV/include" > build-vulkan.log 2>&1 \
       && cmake --build build-vulkan -j "$JOBS" --config Release >> build-vulkan.log 2>&1; then
      echo "Vulkan build OK"
    else
      echo "Vulkan build FAILED (see $WHISPER_DIR/build-vulkan.log); falling back to CPU"; rm -rf build-vulkan
    fi
  else
    echo "Vulkan build present"
  fi
  [ -x build-vulkan/bin/whisper-cli ] && BIN="$WHISPER_DIR/build-vulkan/bin/whisper-cli"
fi
if [ -z "$BIN" ]; then
  if [ ! -x build/bin/whisper-cli ]; then
    echo "building CPU-only…"
    cmake -B build -DCMAKE_BUILD_TYPE=Release > build.log 2>&1 && cmake --build build -j "$JOBS" --config Release >> build.log 2>&1
  fi
  BIN="$WHISPER_DIR/build/bin/whisper-cli"
fi
echo "whisper-cli -> $BIN"

say "3/6 models"
if [ "$NO_MODEL" = 1 ]; then echo "skipped (--no-model)"; else
  [ -f models/ggml-large-v3-turbo.bin ] && echo "large-v3-turbo present" || sh models/download-ggml-model.sh large-v3-turbo
  [ -f models/ggml-silero-v5.1.2.bin ] && echo "silero VAD present" || sh models/download-vad-model.sh silero-v5.1.2
fi

say "4/6 commands in ~/.local/bin"
mkdir -p "$HOME/.local/bin"
ln -sfn "$BIN" "$HOME/.local/bin/whisper-cli"
ln -sfn "$HERE/record" "$HOME/.local/bin/record"
ln -sfn "$HERE/transcribe" "$HOME/.local/bin/transcribe"
chmod +x "$HERE"/record "$HERE"/transcribe "$HERE"/*.sh "$HERE"/*.py "$HERE"/mrconfig
case ":$PATH:" in *":$HOME/.local/bin:"*) echo "~/.local/bin is on PATH" ;; *) echo "ADD to your shell rc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac

say "5/6 config"
CFG="${MEETING_RECORDER_CONFIG:-$HOME/.config/meeting-recorder/config.json}"
if [ -f "$CFG" ]; then echo "present: $CFG"; else
  mkdir -p "$(dirname "$CFG")"; cp "$SKILL_DIR/config.example.json" "$CFG"; echo "created from example: $CFG  <- EDIT IT"
fi

say "6/6 manual steps"
cat <<EOF
* Google Drive (only needed for the doc + share step):
    rclone config   -> new remote, type "drive", scope "drive", name it as in the config (drive.remote)
  The scripts borrow rclone's OAuth token; no other credential is stored anywhere.
  Limits: rclone.conf must be unencrypted (no RCLONE_CONFIG_PASS), OAuth remotes only (no service
  accounts), folders are resolved from "My Drive" (no Shared Drives).
* Edit $CFG: recordings_dir, profiles (identity, language, Drive folders, optional CRM ids).
* Claude Code: this skill is installed from the marketplace or by symlinking the skill folder into
  ~/.claude/skills/. The ~/.local/bin symlinks point at THIS folder: if you installed through the
  plugin marketplace and later update/uninstall the plugin, re-run install.sh (or copy the scripts).
  Calendar lookup uses the Gmail connector if one is attached in Claude Code;
  CRM writes use the Airtable connector. Both optional.
* Quick test:  record --help ; record Test ; Ctrl+C ; transcribe <file>.ogg
EOF
