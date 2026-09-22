#!/usr/bin/env bash
# pending.sh — list recordings that still need processing.
#   pending.sh          unprocessed only (no <basename>.md yet)
#   pending.sh --all    every recording, with its state
# One line per file, tab-separated, newest first:
#   file  date  time  title  duration  lang  profile  transcript(yes/no)  summary(yes/no)  state
# state: pending | recording (skipped: being written right now) | done
set -u
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
cfg() { [ -x "$HERE/mrconfig" ] && "$HERE/mrconfig" "$@" 2>/dev/null || true; }
DIR="${RECORDINGS_DIR:-$(cfg get recordings_dir "$HOME/Recordings")}"; DIR="${DIR/#\~/$HOME}"
ALL=0; [ "${1:-}" = "--all" ] && ALL=1
[ -d "$DIR" ] || { echo "no recordings folder: $DIR" >&2; exit 0; }
LOCKED=$(cat "$DIR/.recording" 2>/dev/null || true)
NOW=$(date +%s)
printf 'file\tdate\ttime\ttitle\tduration\tlang\tprofile\ttranscript\tsummary\tstate\n'
# newest first, safe with spaces in names
mapfile -d '' -t FILES < <(find "$DIR" -maxdepth 1 -type f \( -iname '*.ogg' -o -iname '*.opus' -o -iname '*.m4a' -o -iname '*.mp3' -o -iname '*.wav' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.aac' -o -iname '*.flac' \) -printf '%T@\t%p\0' | sort -z -rn | cut -z -f2-)
tag() { ffprobe -v error -show_entries "stream_tags=$2:format_tags=$2" -of default=nw=1:nk=1 "$1" 2>/dev/null | head -1; }
for f in "${FILES[@]}"; do
  base="${f%.*}"; name=$(basename "$f")
  has_md=no; [ -f "$base.md" ] && has_md=yes
  has_txt=no; [ -f "$base.txt" ] && has_txt=yes
  state=pending
  if [ "$f" = "$LOCKED" ] || [ $((NOW - $(stat -c %Y "$f"))) -lt 60 ] || pgrep -f "^ffmpeg .*$(printf '%s' "$name" | sed 's/[][\.*^$]/\\&/g')" >/dev/null 2>&1; then
    state=recording
  elif [ "$has_md" = yes ]; then
    state=done
  fi
  [ "$ALL" = 1 ] || [ "$state" = pending ] || continue
  if [[ "$name" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})([0-9]{2})_ ]]; then
    d="${BASH_REMATCH[1]}"; t="${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
  else
    d=$(date -r "$f" +%Y-%m-%d); t=$(date -r "$f" +%H:%M)
  fi
  title=$(tag "$f" title); [ -n "$title" ] || title=$(printf '%s' "$name" | sed -E 's/^[0-9-]+_[0-9]{4}_//; s/\.[^.]+$//; s/-/ /g')
  lang=$(tag "$f" language); profile=$(tag "$f" profile)
  secs=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$f" 2>/dev/null | cut -d. -f1)
  dur=$(printf '%02d:%02d:%02d' $((${secs:-0}/3600)) $((${secs:-0}%3600/60)) $((${secs:-0}%60)))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$d" "$t" "$title" "$dur" "${lang:-?}" "${profile:-default}" "$has_txt" "$has_md" "$state"
done
