#!/usr/bin/env bash
# install-remote.sh — put this machine's whisper.cpp build and models on your own transcription
# server, so `transcribe` can hand meetings to it (config `transcribe.remote`).
#
#   install-remote.sh [user@host]      default: first reachable of transcribe.remote.{user,hosts}
#
# Copies the build as-is (same OS and CPU architecture on both ends — e.g. Ubuntu 26.04 x86_64),
# plus libvulkan.so.1 when the server lacks it. No sudo needed. For the server's GPU to be used,
# its user must be able to open the GPU and see a Vulkan driver; that one-time admin step is
# printed at the end when it is missing.
set -euo pipefail

HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
cfg() { "$HERE/mrconfig" "$@" 2>/dev/null || true; }
WHISPER_DIR="${WHISPER_DIR:-$HOME/.local/share/whisper.cpp}"
BIN=$(dirname "$(readlink -f "$(command -v whisper-cli)")") || { echo "whisper-cli not installed here (run install.sh)" >&2; exit 1; }
MODELS="$WHISPER_DIR/models"
R_DIR=$(cfg get transcribe.remote.dir "whisper")

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  R_USER=$(cfg get transcribe.remote.user "")
  for h in $(cfg get transcribe.remote.hosts "" | tr -d '[],"'); do
    t="${R_USER:+$R_USER@}$h"
    if ssh -o BatchMode=yes -o ConnectTimeout=3 "$t" true 2>/dev/null; then TARGET="$t"; break; fi
  done
fi
[ -n "$TARGET" ] || { echo "no server given and none of transcribe.remote.hosts answers" >&2; exit 1; }

echo "1/3 build ($BIN) -> $TARGET:$R_DIR/bin"
ssh -o BatchMode=yes "$TARGET" "mkdir -p $R_DIR/bin $R_DIR/models $R_DIR/jobs"
rsync -a "$BIN"/whisper-cli "$BIN"/*.so* "$TARGET:$R_DIR/bin/"
if ldd "$BIN/whisper-cli" | grep -q libvulkan \
   && ! ssh -o BatchMode=yes "$TARGET" "ldconfig -p | grep -q libvulkan.so.1"; then
  echo "    server has no libvulkan.so.1: shipping this machine's copy"
  rsync -aL "$(ldconfig -p | awk '/libvulkan.so.1 /{print $NF; exit}')" "$TARGET:$R_DIR/bin/libvulkan.so.1"
fi

echo "2/3 models -> $TARGET:$R_DIR/models"
for m in ggml-large-v3-turbo.bin ggml-silero-v5.1.2.bin; do
  [ -f "$MODELS/$m" ] && rsync -a "$MODELS/$m" "$TARGET:$R_DIR/models/"
done

echo "3/3 GPU check"
ssh -o BatchMode=yes "$TARGET" "LD_LIBRARY_PATH=$R_DIR/bin $R_DIR/bin/whisper-cli --help >/dev/null 2>&1" \
  || { echo "    the build does not start on the server (different OS/libraries?)" >&2; exit 1; }
if ssh -o BatchMode=yes "$TARGET" 'ls /usr/share/vulkan/icd.d/*.json >/dev/null 2>&1 && for n in /dev/dri/renderD*; do [ -r "$n" ] && exit 0; done; exit 1'; then
  echo "    Vulkan driver present and a GPU is readable: transcribe will use it."
else
  user=${TARGET%@*}; [ "$user" = "$TARGET" ] && user=$(ssh "$TARGET" whoami)
  cat <<EOF
    No usable GPU for $user yet. One-time admin step on the server (needs its sudo password):
      sudo apt install -y mesa-vulkan-drivers libvulkan1 && sudo usermod -aG render,video $user
    (NVIDIA cards: the open NVK driver in mesa-vulkan-drivers is enough; the proprietary driver works too.)
    Until then transcribe runs on this machine; \`transcribe --remote\` uses the server's CPU.
EOF
fi
