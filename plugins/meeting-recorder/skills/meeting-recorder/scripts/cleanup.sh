#!/usr/bin/env bash
# cleanup.sh — delete OLD recordings (and optionally transcripts) from the recordings folder.
#   cleanup.sh [--older-than DAYS] [--also-transcripts] [--apply]
# Default: 30 days, audio only, DRY RUN (lists what would go and the space it frees).
# Summaries (X.md) are never deleted: they hold the doc links and the CRM/share state.
# Only PROCESSED recordings (those with X.md) are eligible; a pending one is kept whatever its age.
set -u
HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
cfg() { [ -x "$HERE/mrconfig" ] && "$HERE/mrconfig" "$@" 2>/dev/null || true; }
DIR="${RECORDINGS_DIR:-$(cfg get recordings_dir "$HOME/Recordings")}"; DIR="${DIR/#\~/$HOME}"
DAYS=30; TXT=0; APPLY=0
while [ $# -gt 0 ]; do case "$1" in
  --older-than) [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]] || { echo "--older-than needs a number of days" >&2; exit 1; }; DAYS="$2"; shift 2 ;;
  --also-transcripts) TXT=1; shift ;; --apply) APPLY=1; shift ;;
  *) echo "usage: cleanup.sh [--older-than DAYS] [--also-transcripts] [--apply]" >&2; exit 1 ;; esac; done
[ -d "$DIR" ] || { echo "no recordings folder: $DIR" >&2; exit 0; }
mb() { awk -v b="$1" 'BEGIN{printf "%.1f", b/1048576}'; }
shopt -s nullglob nocaseglob; total=0; n=0
for f in "$DIR"/*.{ogg,opus,m4a,mp3,wav,mp4,webm,aac,flac}; do
  [ -f "${f%.*}.md" ] || continue                      # unprocessed: keep
  [ $(( ($(date +%s) - $(stat -c %Y "$f")) / 86400 )) -ge "$DAYS" ] || continue
  sz=$(stat -c %s "$f"); total=$((total+sz)); n=$((n+1))
  printf '%s  %6s MB  %s\n' "$([ $APPLY = 1 ] && echo DELETE || echo would-delete)" "$(mb "$sz")" "$(basename "$f")"
  [ $APPLY = 1 ] && rm -f -- "$f"
  if [ $TXT = 1 ] && [ -f "${f%.*}.txt" ]; then
    printf '%s          %s\n' "$([ $APPLY = 1 ] && echo DELETE || echo would-delete)" "$(basename "${f%.*}.txt")"
    [ $APPLY = 1 ] && rm -f -- "${f%.*}.txt"
  fi
done
printf '%s: %d recording(s), %s MB, older than %d days%s\n' "$([ $APPLY = 1 ] && echo Deleted || echo 'Dry run')" "$n" "$(mb "$total")" "$DAYS" "$([ $APPLY = 1 ] || echo ' — add --apply to delete')"
