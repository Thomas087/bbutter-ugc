#!/usr/bin/env bash
# combine_segment.sh — mux the silent Kling video for a segment with its
# accelerated voice-over track.
#
# Usage:
#   combine_segment.sh SESSION_DIR SEGMENT_NUM
#
# Reads:
#   <session>/videos/segment_<N>.mp4
#   <session>/voice_sections_1.2x/section-<NN>.mp3
#
# Writes:
#   <session>/segments/segment_<N>.mp4   (video + audio, length = min(both))
#
# Uses -shortest so the output runs for the audio length when audio < video
# (Kling pads to 5 or 10 s; the accelerated voice-over is the source of truth
# for segment timing).

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 SESSION_DIR SEGMENT_NUM" >&2
  exit 1
fi

session="$1"
n="$2"

if ! [[ "$n" =~ ^[0-9]+$ ]]; then
  echo "combine_segment.sh: SEGMENT_NUM must be an integer, got '$n'" >&2
  exit 1
fi

video="$session/videos/segment_${n}.mp4"
audio="$(printf "%s/voice_sections_1.2x/section-%02d.mp3" "$session" "$n")"
out_dir="$session/segments"
out="$out_dir/segment_${n}.mp4"

for f in "$video" "$audio"; do
  if [[ ! -f "$f" ]]; then
    echo "combine_segment.sh: missing input: $f" >&2
    exit 1
  fi
done

mkdir -p "$out_dir"

ffmpeg -y -hide_banner -loglevel error \
  -i "$video" -i "$audio" \
  -c:v copy -c:a aac -b:a 192k -shortest \
  -movflags +faststart \
  "$out"

echo "$out"
