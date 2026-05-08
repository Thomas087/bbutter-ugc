#!/usr/bin/env bash
# Applique un effet lo-fi + reverb "salle de bain" à un dossier de MP3.
#
# Pipeline (par fichier) :
#   1. ffmpeg : bandpass 200–5000 Hz + compression légère (cheap iPhone mic)
#   2. sox    : reverb algorithmique (Schroeder/Moorer) — petite pièce carrelée
#
# Entrée :
#   --in DIR        dossier contenant les MP3 source — requis
#   --out DIR       dossier de sortie — défaut : <in>_lofi (à côté de l'input)
#   --bitrate N     bitrate MP3 de sortie (défaut 128k)
#
# Paramètres figés (issus du tuning UGC Butt Butter) :
#   ffmpeg : highpass=200, lowpass=5000, acompressor 2.5:1 @ -20dB, volume +1.1
#   sox reverb 45 50 40 100 5 -3
#     reverberance=45 / HF-damping=50 / room-scale=40 / stereo-depth=100 /
#     pre-delay=5ms / wet-gain=-3dB
#
# Dépendances : ffmpeg, sox (brew install ffmpeg sox)
#
# Codes de sortie :
#   0 succès
#   1 usage / dépendance manquante / dossier introuvable

set -euo pipefail
export LC_ALL=C

IN_DIR=""
OUT_DIR=""
BITRATE="128k"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in)      IN_DIR="$2"; shift 2;;
    --out)     OUT_DIR="$2"; shift 2;;
    --bitrate) BITRATE="$2"; shift 2;;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    *) echo "unknown flag: $1" >&2; exit 1;;
  esac
done

if [[ -z "$IN_DIR" ]]; then
  echo "error: --in DIR is required" >&2
  exit 1
fi
if [[ ! -d "$IN_DIR" ]]; then
  echo "error: input directory not found: $IN_DIR" >&2
  exit 1
fi
command -v ffmpeg >/dev/null || { echo "error: ffmpeg not installed (brew install ffmpeg)" >&2; exit 1; }
command -v sox    >/dev/null || { echo "error: sox not installed (brew install sox)"      >&2; exit 1; }

# Strip trailing slash, then default OUT_DIR to "<in>_lofi"
IN_DIR="${IN_DIR%/}"
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="${IN_DIR}_lofi"
fi
mkdir -p "$OUT_DIR"

shopt -s nullglob
files=("$IN_DIR"/*.mp3)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "error: no .mp3 files in $IN_DIR" >&2
  exit 1
fi

tmp_dir="$(mktemp -d -t apply_lofi.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

for src in "${files[@]}"; do
  base="$(basename "$src")"
  tmp_wav="$tmp_dir/${base%.mp3}.wav"
  dst="$OUT_DIR/$base"

  ffmpeg -y -loglevel error -i "$src" \
    -af "highpass=f=200,lowpass=f=5000,acompressor=threshold=-20dB:ratio=2.5:attack=5:release=50,volume=1.1" \
    -codec:a pcm_s16le "$tmp_wav"

  sox "$tmp_wav" -C "${BITRATE%k}" "$dst" reverb 45 50 40 100 5 -3

  printf "  %s -> %s\n" "$base" "$dst"
done

echo "done: ${#files[@]} file(s) -> $OUT_DIR"
