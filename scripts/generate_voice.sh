#!/usr/bin/env bash
# Génère un MP3 voix off ElevenLabs à partir d'un script UGC.
#
# Entrée :
#   --script PATH     script UGC (.md produit par ugc-script-writer, ou .txt) — requis
#   --voice ID        voice id ElevenLabs (défaut zlP1wgh6FsmMZswaDa2M, voix masculine FR)
#   --out PATH        chemin MP3 de sortie (défaut : même nom que le script, extension .mp3)
#   --model ID        modèle ElevenLabs (défaut eleven_v3)
#   --stability N     stabilité de la voix 0-1 (défaut 0.5)
#   --per-section     écrit aussi un MP3 par segment "**Voix :** "..."" sous <out_dir>/<basename>_sections/
#
# Comportement :
#   - .md  → extrait chaque segment "**Voix :** "..."" dans l'ordre, joint par un espace.
#   - .txt → utilise le contenu tel quel.
#   - Idempotent : ne régénère pas si le MP3 est plus récent que le script.
#
# Lit ELEVENLABS_API_KEY depuis .env à la racine du repo (un niveau au-dessus de scripts/).
#
# Codes de sortie :
#   0 succès
#   1 usage / fichier manquant
#   2 erreur API ElevenLabs
#
# Catalogue des voix disponibles : scripts/voices.json
# (lister : `jq -r '.voices[] | "\(.id)\t\(.gender)\t\(.age)\t\(.description)"' scripts/voices.json`)

set -euo pipefail
export LC_ALL=C

SCRIPT_PATH=""
VOICE_ID="zlP1wgh6FsmMZswaDa2M"
OUT=""
MODEL="eleven_v3"
STABILITY="0.5"
PER_SECTION="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --script)      SCRIPT_PATH="$2"; shift 2;;
    --voice)       VOICE_ID="$2"; shift 2;;
    --out)         OUT="$2"; shift 2;;
    --model)       MODEL="$2"; shift 2;;
    --stability)   STABILITY="$2"; shift 2;;
    --per-section) PER_SECTION="1"; shift;;
    -h|--help)
      sed -n '2,25p' "$0"; exit 0;;
    *) echo "unknown flag: $1" >&2; exit 1;;
  esac
done

[[ -z "$SCRIPT_PATH" ]] && { echo "missing --script" >&2; exit 1; }
[[ -f "$SCRIPT_PATH" ]] || { echo "script not found: $SCRIPT_PATH" >&2; exit 1; }

# ── prérequis ──────────────────────────────────────────────────────────────
command -v jq   >/dev/null || { echo "jq not installed (try: brew install jq)" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl not installed" >&2; exit 1; }

# Racine du projet : un niveau au-dessus de scripts/
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[[ -f "$ROOT/.env" ]] || { echo ".env not found at $ROOT/.env" >&2; exit 1; }
set -a; source "$ROOT/.env"; set +a
[[ -n "${ELEVENLABS_API_KEY:-}" ]] || { echo "ELEVENLABS_API_KEY missing in .env" >&2; exit 1; }

# Sortie par défaut : même nom, extension .mp3, à côté du script
if [[ -z "$OUT" ]]; then
  OUT="${SCRIPT_PATH%.*}.mp3"
fi
mkdir -p "$(dirname "$OUT")"

# ── Extraction du texte voix off ───────────────────────────────────────────
ext="${SCRIPT_PATH##*.}"
SECTIONS=()
if [[ "$ext" == "md" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && SECTIONS+=("$line")
  done < <(grep -oE '\*\*Voix *:\*\* *"[^"]+"' "$SCRIPT_PATH" \
            | sed -E 's/^\*\*Voix *:\*\* *"([^"]+)"$/\1/')
  if [[ ${#SECTIONS[@]} -eq 0 ]]; then
    echo "no '**Voix :** \"...\"' lines found in $SCRIPT_PATH — fournir un .txt ou corriger le markdown" >&2
    exit 1
  fi
  TEXT=$(printf '%s ' "${SECTIONS[@]}")
  TEXT="${TEXT% }"
else
  TEXT=$(cat "$SCRIPT_PATH")
  SECTIONS=("$TEXT")
fi

CHARS=${#TEXT}
echo "voice: $VOICE_ID  model: $MODEL  chars: $CHARS  segments: ${#SECTIONS[@]}"

# ── Helper : appel ElevenLabs ──────────────────────────────────────────────
tts_call() {
  local text="$1"
  local out="$2"
  local payload
  payload=$(jq -n --arg t "$text" --arg m "$MODEL" --argjson s "$STABILITY" \
    '{text:$t, model_id:$m, voice_settings:{stability:$s}}')
  local code
  code=$(curl -sS -o "$out" -w "%{http_code}" \
    -X POST "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}" \
    -H 'accept: audio/mpeg' \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$payload")
  if [[ "$code" != "200" ]]; then
    echo "ElevenLabs error HTTP $code on $out" >&2
    cat "$out" >&2 || true
    rm -f "$out"
    return 2
  fi
}

# ── MP3 combiné (idempotent) ───────────────────────────────────────────────
if [[ -f "$OUT" && "$OUT" -nt "$SCRIPT_PATH" ]]; then
  echo "$OUT (cached, plus récent que la source)"
else
  echo "==> génération du MP3 combiné"
  tts_call "$TEXT" "$OUT" || exit 2
  echo "wrote $OUT"
fi

# ── MP3 par section (optionnel) ────────────────────────────────────────────
if [[ "$PER_SECTION" == "1" ]]; then
  base="$(basename "${OUT%.*}")"
  sec_dir="$(dirname "$OUT")/${base}_sections"
  mkdir -p "$sec_dir"
  echo "==> sections → $sec_dir"
  i=0
  for seg in "${SECTIONS[@]}"; do
    i=$((i+1))
    pad=$(printf "%02d" "$i")
    sec_out="$sec_dir/section-${pad}.mp3"
    if [[ -f "$sec_out" && "$sec_out" -nt "$SCRIPT_PATH" ]]; then
      echo "    section-${pad}.mp3 (cached)"
      continue
    fi
    tts_call "$seg" "$sec_out" || exit 2
    echo "    section-${pad}.mp3"
  done
fi

ls -lh "$OUT"
