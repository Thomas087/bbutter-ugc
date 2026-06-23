#!/usr/bin/env bash
# Applique un effet lo-fi + reverb "salle de bain" à des MP3 voix off.
#
# Modes d'invocation :
#   1. Session dir : --in <session> où <session> contient un ou plusieurs
#      sous-dossiers parmi `voice_sections/` et `voice_sections_1.2x/`.
#      Chaque sous-dossier détecté est traité et produit son propre
#      `<sub>_lofi/` à côté de lui.
#   2. Dossier plat : --in <dir> contenant directement des *.mp3.
#      Sortie : `<dir>_lofi/` à côté de l'input.
#
# Pipeline (par fichier) :
#   1. ffmpeg : bandpass 200–5000 Hz + compression légère (cheap iPhone mic)
#   2. sox    : reverb algorithmique (Schroeder/Moorer) — petite pièce carrelée
#
# Entrée :
#   --in DIR        dossier source (session ou flat) — requis
#   --out DIR       force la destination (uniquement en mode flat)
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
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
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

IN_DIR="${IN_DIR%/}"

tmp_dir="$(mktemp -d -t apply_lofi.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT

shopt -s nullglob

process_dir() {
  local src_dir="$1"
  local dst_dir="$2"
  local files=("$src_dir"/*.mp3)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "error: no .mp3 files in $src_dir" >&2
    return 1
  fi
  mkdir -p "$dst_dir"
  for src in "${files[@]}"; do
    local base tmp_wav dst
    base="$(basename "$src")"
    tmp_wav="$tmp_dir/${base%.mp3}.wav"
    dst="$dst_dir/$base"

    ffmpeg -y -loglevel error -i "$src" \
      -af "highpass=f=200,lowpass=f=5000,acompressor=threshold=-20dB:ratio=2.5:attack=5:release=50,volume=1.1" \
      -codec:a pcm_s16le "$tmp_wav"

    sox "$tmp_wav" -C "${BITRATE%k}" "$dst" reverb 45 50 40 100 5 -3

    printf "  %s -> %s\n" "$base" "$dst"
  done
  echo "done: ${#files[@]} file(s) -> $dst_dir"
}

# Detect session-mode subdirs (voice_sections / voice_sections_1.2x).
sub_targets=()
for sub in voice_sections voice_sections_1.2x; do
  [[ -d "$IN_DIR/$sub" ]] && sub_targets+=("$sub")
done

if [[ ${#sub_targets[@]} -gt 0 ]]; then
  if [[ -n "$OUT_DIR" ]]; then
    echo "error: --out is not supported in session mode (multiple targets)" >&2
    exit 1
  fi
  for sub in "${sub_targets[@]}"; do
    process_dir "$IN_DIR/$sub" "$IN_DIR/${sub}_lofi"
  done
else
  if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="${IN_DIR}_lofi"
  fi
  process_dir "$IN_DIR" "$OUT_DIR"
fi
