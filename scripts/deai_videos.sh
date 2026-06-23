#!/usr/bin/env bash
# De-AI + color-harmonize les segments vidéo d'une session UGC Butt Butter.
#
# Mode d'invocation (un seul) :
#   --in <session_dir>  dossier contenant `videos/segment_<N>_final.mp4`.
#
# Pipeline (par segment) :
#   - Segment 1 = référence colorimétrique (jamais déplacé en couleur).
#     Filtre : unsharp=5:5:-0.5:5:5:0.0 + noise=alls=8:allf=t+u
#     (micro-blur sur la luma + film grain → casse le "pixel-perfect AI".)
#
#   - Segment N>1 : sample mean RGB de N, calcule gamma_r = R_ref / R_N et
#     gamma_g = G_ref / G_N (heuristique ratio mid-gray, clampée à [0.8, 1.2]).
#     Filtre : eq=saturation=0.88:gamma=1.0:gamma_r=<g_r>:gamma_g=<g_g>
#              + unsharp=5:5:-0.5:5:5:0.0
#              + noise=alls=8:allf=t+u
#     (saturation -12% pour casser la vibrance AI, gamma per-channel pour
#     matcher la mean RGB du segment 1, plus la même texture que seg 1.)
#
# Layout fichiers :
#   videos/raw/segment_<N>_final.mp4   ← original préservé (créé au 1er run)
#   videos/segment_<N>_final.mp4        ← de-AI'd, prêt pour ugc-concat
#
# Idempotent : sur un re-run, la source du filtrage est `videos/raw/...` si
# elle existe (les originaux sont déjà sauvegardés). Sinon, `videos/...` est
# déplacé vers `videos/raw/` AVANT le ré-encodage.
#
# Encodage : libx264 crf 18 + audio copy. La taille gonfle (grain
# incompressible) — c'est normal et attendu.
#
# Dépendances : ffmpeg.
#
# Codes de sortie :
#   0 succès
#   1 usage / dépendance manquante / dossier introuvable

set -euo pipefail
export LC_ALL=C

SESSION=""
SEGMENTS=""
FORCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in)        SESSION="$2"; shift 2;;
    --segments)  SEGMENTS="$2"; shift 2;;
    --force)     FORCE=1; shift;;
    -h|--help)   sed -n '2,40p' "$0"; exit 0;;
    *) echo "unknown flag: $1" >&2; exit 1;;
  esac
done

if [[ -z "$SESSION" ]]; then
  echo "error: --in <session_dir> is required" >&2
  exit 1
fi
if [[ ! -d "$SESSION/videos" ]]; then
  echo "error: $SESSION/videos not found (expected segment_<N>_final.mp4 inside)" >&2
  exit 1
fi
command -v ffmpeg  >/dev/null || { echo "error: ffmpeg not installed (brew install ffmpeg)"  >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "error: ffprobe not installed (brew install ffmpeg)" >&2; exit 1; }

SESSION="${SESSION%/}"
RAW_DIR="$SESSION/videos/raw"
mkdir -p "$RAW_DIR"

# ----- Helpers -----------------------------------------------------------

# Source path for a given N. If videos/raw/segment_<N>_final.mp4 exists, that
# is the original (already preserved on a previous run). Otherwise, the file
# at videos/segment_<N>_final.mp4 is still the original, and we'll move it
# into raw/ before encoding.
src_for() {
  local n="$1"
  if [[ -f "$RAW_DIR/segment_${n}_final.mp4" ]]; then
    echo "$RAW_DIR/segment_${n}_final.mp4"
  elif [[ -f "$SESSION/videos/segment_${n}_final.mp4" ]]; then
    echo "$SESSION/videos/segment_${n}_final.mp4"
  else
    return 1
  fi
}

# Sample mean R,G,B of an mp4 by downscaling one mid-duration frame to 1x1.
# Echoes "R G B".
sample_rgb() {
  local mp4="$1"
  local dur t rgb
  dur="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$mp4")"
  # midpoint, fall back to 1s if duration unparseable
  t="$(awk -v d="$dur" 'BEGIN { if (d+0>0) printf "%.2f", d/2; else print "1" }')"
  rgb="$(ffmpeg -nostats -loglevel quiet -ss "$t" -i "$mp4" -frames:v 1 \
           -vf "scale=1:1" -f rawvideo -pix_fmt rgb24 - 2>/dev/null \
         | od -An -vtu1 -N3 | awk '{print $1, $2, $3}')"
  if [[ -z "$rgb" ]]; then
    echo "error: failed to sample RGB from $mp4" >&2
    return 1
  fi
  echo "$rgb"
}

# Clamp a float to [lo, hi].
clamp() {
  awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN {
    if (v < lo) v = lo
    if (v > hi) v = hi
    printf "%.3f", v
  }'
}

# ----- 1. Discover segments ---------------------------------------------

shopt -s nullglob
ALL_N=()
for f in "$SESSION/videos"/segment_*_final.mp4 "$RAW_DIR"/segment_*_final.mp4; do
  [[ -f "$f" ]] || continue
  n="$(basename "$f" | sed -E 's/^segment_([0-9]+)_final\.mp4$/\1/')"
  [[ "$n" =~ ^[0-9]+$ ]] || continue
  ALL_N+=("$n")
done
# dedup + numeric sort (portable; macOS bash 3.2 has no mapfile)
SORTED=()
while IFS= read -r line; do SORTED+=("$line"); done < <(printf '%s\n' "${ALL_N[@]}" | sort -nu)
ALL_N=("${SORTED[@]}")

if [[ ${#ALL_N[@]} -eq 0 ]]; then
  echo "error: no segment_<N>_final.mp4 found under $SESSION/videos/ or $RAW_DIR/" >&2
  exit 1
fi

# Filter via --segments if provided.
if [[ -n "$SEGMENTS" ]]; then
  IFS=',' read -ra REQ <<< "$SEGMENTS"
  WANT=()
  for n in "${REQ[@]}"; do
    n_trim="${n// /}"
    [[ "$n_trim" =~ ^[0-9]+$ ]] || { echo "error: invalid --segments value '$n'" >&2; exit 1; }
    WANT+=("$n_trim")
  done
  TARGETS=()
  while IFS= read -r line; do TARGETS+=("$line"); done < <(printf '%s\n' "${WANT[@]}" | sort -nu)
else
  TARGETS=("${ALL_N[@]}")
fi

# ----- 2. Reference RGB from segment 1 ----------------------------------

REF_SRC="$(src_for 1 || true)"
if [[ -z "$REF_SRC" ]]; then
  echo "error: segment_1_final.mp4 not found — needed as colorimetric reference" >&2
  exit 1
fi
read -r REF_R REF_G REF_B < <(sample_rgb "$REF_SRC")
printf "Reference (segment 1): R=%d G=%d B=%d\n" "$REF_R" "$REF_G" "$REF_B"

# ----- 3. Process each target segment -----------------------------------

TEX_FILTER="unsharp=5:5:-0.5:5:5:0.0,noise=alls=8:allf=t+u"

for N in "${TARGETS[@]}"; do
  SRC="$(src_for "$N" || true)"
  if [[ -z "$SRC" ]]; then
    echo "[segment $N] SKIP (no source mp4)" >&2
    continue
  fi

  CANONICAL="$SESSION/videos/segment_${N}_final.mp4"
  RAW="$RAW_DIR/segment_${N}_final.mp4"

  # If canonical exists and raw doesn't, this is the first run for this N:
  # move the original into raw/ so the encoder reads from there.
  if [[ ! -f "$RAW" ]]; then
    mv "$CANONICAL" "$RAW"
    SRC="$RAW"
  fi

  # Skip if canonical already exists AND --force not set AND raw exists
  # (i.e. canonical is already a de-AI'd version from a prior run).
  if [[ -f "$CANONICAL" && -z "${FORCE:-}" ]]; then
    printf "[segment %s] skipped (already de-AI'd, pass --force to regenerate)\n" "$N"
    continue
  fi

  if [[ "$N" == "1" ]]; then
    FILTER="$TEX_FILTER"
    printf "[segment %s] reference — texture only\n" "$N"
  else
    # Per-channel ratio gamma: at mid-gray, gamma g produces a mean shift
    # of roughly factor g, so g = target_mean / observed_mean is a decent
    # first-order approximation. Clamp to [0.8, 1.2] to avoid pathological
    # shifts on edge cases (very dark/bright scenes).
    read -r R_N G_N B_N < <(sample_rgb "$SRC")
    G_R="$(awk -v t="$REF_R" -v n="$R_N" 'BEGIN { if (n+0==0) print "1.000"; else printf "%.3f", t/n }')"
    G_G="$(awk -v t="$REF_G" -v n="$G_N" 'BEGIN { if (n+0==0) print "1.000"; else printf "%.3f", t/n }')"
    G_R="$(clamp "$G_R" 0.80 1.20)"
    G_G="$(clamp "$G_G" 0.80 1.20)"
    FILTER="eq=saturation=0.88:gamma=1.0:gamma_r=${G_R}:gamma_g=${G_G},${TEX_FILTER}"
    printf "[segment %s] raw RGB=%d/%d/%d → gamma_r=%s gamma_g=%s\n" \
      "$N" "$R_N" "$G_N" "$B_N" "$G_R" "$G_G"
  fi

  ffmpeg -y -hide_banner -loglevel error \
    -i "$SRC" \
    -vf "$FILTER" \
    -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p \
    -c:a copy -movflags +faststart \
    "$CANONICAL"

  # Quick verify: sample post-encode RGB and report.
  read -r OR OG OB < <(sample_rgb "$CANONICAL")
  printf "[segment %s] → %s  (post RGB=%d/%d/%d, target=%d/%d/%d)\n" \
    "$N" "$CANONICAL" "$OR" "$OG" "$OB" "$REF_R" "$REF_G" "$REF_B"
done

printf "done: %d segment(s) de-AI'd. Originals preserved in %s/\n" \
  "${#TARGETS[@]}" "$RAW_DIR"
