# UGC Full Video Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a new pure-markdown skill `ugc-full-video-pipeline` that orchestrates segment-by-segment Seedance video generation (with character asset, lo-fi audio, face mask, packshot, size reference) for an existing Butt Butter UGC script + lo-fi voice.

**Architecture:** Pure-markdown skill at `.claude/skills/ugc-full-video-pipeline/SKILL.md`. No new helper scripts — the skill instructs Claude to call existing scripts (`scripts/generate_video_seedance.py`, `scripts/generate_image.sh`, `ffmpeg`) and existing helpers (`scripts/storage.sh` invoked transitively). Sequential pipeline: parse script → persona match → segment 1 → face mask → segments 2..N. Each segment gets its own per-call `video_prompt.txt`. Anchor segments (`Plan ancre` in stage direction) attach the face mask from segment 2 onwards. Detected products (alias substring match on segment text) attach packshot + size reference URLs.

**Tech Stack:** Markdown (skill body), bash/zsh (procedure invocations), Python 3 helpers in `scripts/` (already shipped), ffmpeg, ElevenLabs lo-fi MP3s already produced upstream, BytePlus Ark Seedance API, OpenAI gpt-image-2/-1 via `scripts/generate_image.sh`.

**Spec:** `docs/superpowers/specs/2026-05-08-ugc-full-video-pipeline-design.md`

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `.claude/skills/ugc-full-video-pipeline/SKILL.md` | **create** | Whole skill body. Single markdown file, ~250-350 lines. |
| `docs/superpowers/plans/2026-05-08-ugc-full-video-pipeline.md` | this file (create) | The plan itself. |
| `docs/superpowers/specs/2026-05-08-ugc-full-video-pipeline-design.md` | already on master (commit `ca1fba1`) | Reference spec. |
| `scripts/generate_video_seedance.py` | **read-only** | Already shipped. Auto-attaches lo-fi audio when `--audio` omitted. |
| `scripts/generate_image.sh` | **read-only** | Already shipped. `--ref` mode for face-mask edit. |
| `scripts/storage.sh` | **read-only** | Already shipped. Invoked transitively to upload local PNGs. |
| `scripts/characters.json` | **read-only** | Persona → character asset catalog. |
| `brand/products/catalog.yaml` | **read-only** | Product slug → name + hero_image. |
| `brand/products/<slug>.md` | **read-only** | Product copy + `**Référence taille du produit :** <url>` lines. |
| `output/2026-05-08-le-3eme/` | **read-only** (test fixture) | Existing smoke-test session: has `script.md` (5 segments), `voice_sections_1.2x_lofi/`, `videos/segment_1_final.mp4` and `videos/segment_2_final.mp4` already produced. |

There are no Python modules to add. This is a documentation/skill change — "tests" are end-to-end smoke runs that exercise the skill against `output/2026-05-08-le-3eme/`.

---

## Background notes the engineer needs

- **Skills in this repo are pure markdown.** No code is loaded — the model reads the SKILL.md and follows the procedure. So "implementing" the skill = writing prose + commands + templates that Claude can execute step by step.
- **Skill discovery is via the `description` field in YAML frontmatter.** Claude picks a skill when the user message matches the trigger phrases listed there. Look at `.claude/skills/ugc-video-seedance/SKILL.md` lines 2-4 for the format and tone.
- **`scripts/generate_video_seedance.py` already auto-attaches the lo-fi audio** at `voice_sections_1.2x_lofi/section-NN.mp3` when `--audio` is omitted. Don't pass `--audio` from the skill — let the script handle it. (See lines 271-276 of that script.)
- **`scripts/generate_video_seedance.py` accepts `--image` multiple times.** Each `--image` is either an HTTPS URL (passed through) or a local path (uploaded via `storage.sh`). The face mask is a local PNG; packshot + size ref are HTTPS URLs from Shopify.
- **`scripts/generate_image.sh --ref`** is the face-mask edit endpoint. Already documented at `.claude/skills/ugc-face-mask-extractor/SKILL.md` lines 81-95.
- **`OPENAI_IMAGE_QUALITY=high`** is mandatory per project memory. Default of `low` makes the face mask look pixelated and unusable as a continuity reference.
- **Anchor detection rule (final, do not deviate):** stage direction (italics line directly under `**[t1 – t2] — TITLE**`) contains the substring `plan ancre`, case-insensitive. The sample script `output/2026-05-08-le-3eme/script.md` shows every segment as anchor — that's the common case but not the only one (future scripts will have insert/B-roll segments).
- **Product alias map (final, do not deviate):**
  - `creme-apaisante` ← `crème`, `tube`, `noisette`, `apaise`
  - `complement-circulation-transit` ← `complément`, `gélule`, `circulation`, `transit`
  - `probiotique` ← `probiotique`
  - `soin-lavant-hygiene-intime` ← `soin lavant`, `savon`, `lavant`
- **Size reference URL** lives in each `brand/products/<slug>.md` as a line `**Référence taille du produit :** https://...`. Currently present for `creme-apaisante` and `complement-circulation-transit`; absent for `probiotique` and `soin-lavant-hygiene-intime`. Treat absence as "skip silently".
- **Persona match rule:** identical to `ugc-voice-generator`/`ugc-video-seedance` — gender strict, age closest. If no match, **stop hard** and ask the user to register a new character asset. Do not fall back to a near-match.
- **The example session `output/2026-05-08-le-3eme/`** already has segments 1 & 2 generated (`videos/segment_1_final.mp4`, `videos/segment_2_final.mp4`) and segment_1 has its `frames/segment_1/first_frame.png`. The face mask `first_frame_face_mask.png` may or may not exist — check before relying on it.

---

## Task 1: Scaffold the skill folder and write the frontmatter + intro

**Files:**
- Create: `.claude/skills/ugc-full-video-pipeline/SKILL.md`

**Why this task is one chunk:** The frontmatter `description` field is what makes the skill discoverable. Getting it right (matching the trigger phrases the user will use, in French, with enough variants) deserves its own commit before any procedure work.

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p .claude/skills/ugc-full-video-pipeline
```

- [ ] **Step 2: Write the SKILL.md frontmatter and "Goal" section**

Create `.claude/skills/ugc-full-video-pipeline/SKILL.md` with this exact content:

````markdown
---
name: ugc-full-video-pipeline
description: >-
  Pipeline complet de génération vidéo UGC Butt Butter à partir d'un script déjà voicé en lo-fi (sortie de `ugc-voice-lofi`). Orchestration séquentielle, segment par segment, via `scripts/generate_video_seedance.py` : génère segment 1 (le plan ancre seed) avec character asset + audio lo-fi (auto-attaché) + packshot/size-ref des produits détectés, extrait le face-mask depuis sa première frame via ffmpeg + `scripts/generate_image.sh --ref`, puis génère les segments 2..N en attachant le face-mask aux plans ancre et le packshot + référence taille pour chaque produit cité dans le segment. Détection des produits par keyword match sur le catalogue (`brand/products/catalog.yaml` + fichiers `<slug>.md`). Détection du plan ancre par parsing de la directive scène `Plan ancre` dans le `script.md`. Match persona → character asset via `scripts/characters.json` (genre strict, âge le plus proche). Utilise ce skill dès que l'utilisateur demande "génère toute la vidéo", "pipeline complet vidéo", "vidéo UGC complète", "lance la génération vidéo de bout en bout", "génère tous les segments", "vidéo UGC du script avec face-mask", "génère le clip complet", ou veut produire la vidéo intégrale d'un script Butt Butter une fois la voix lo-fi prête. Utilise-le aussi quand l'utilisateur veut régénérer plusieurs segments à la suite ou enchaîner segment 1 → face mask → segments 2..N sans repasser par les skills atomiques `ugc-video-seedance` et `ugc-face-mask-extractor` un par un.
---

# UGC Full Video Pipeline — Butt Butter

Ce skill orchestre la génération vidéo UGC complète d'un script Butt Butter déjà voicé en lo-fi. Il prend en entrée un dossier de session contenant `script.md` + `voice_sections_1.2x_lofi/section-NN.mp3` (sortie de `ugc-voice-lofi`) et produit `videos/segment_<N>_final.mp4` pour chaque segment du script, dans l'ordre.

Pipeline en 6 étapes, séquentielles, **jamais en parallèle** : parse → persona → alias produits → segment 1 (seed) → face-mask → segments 2..N. Le face-mask extrait du premier frame du segment 1 sert d'image de référence aux segments ancre suivants pour figer la posture corps + décor + téléphone tout en laissant Seedance re-générer le visage proprement depuis le character asset.

Ce skill remplace le loop manuel `ugc-video-seedance` → `ugc-face-mask-extractor` → `ugc-video-seedance` × (N-1). Il consomme en aval de `ugc-script-writer` → `ugc-voice-generator` → `ugc-voice-lofi`.

> **Pré-requis dur** : le dossier session DOIT contenir `script.md` ET `voice_sections_1.2x_lofi/section-NN.mp3` pour chaque N ciblé. Si la lo-fi manque, **stoppe** et pointe vers `ugc-voice-lofi`. Pas d'auto-recovery — c'est un pipeline aval, pas un orchestrateur global.
````

- [ ] **Step 3: Verify the skill is loaded by listing it**

The harness re-scans skills automatically; just verify the file is well-formed:

```bash
head -5 .claude/skills/ugc-full-video-pipeline/SKILL.md
```

Expected: yaml frontmatter with `name: ugc-full-video-pipeline` and a `description: >-` block.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/ugc-full-video-pipeline/SKILL.md
git commit -m "$(cat <<'EOF'
Scaffold ugc-full-video-pipeline skill

Frontmatter + intro only. Pipeline body in follow-up commits.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Inputs, pre-checks, and Step 0 (parse script.md)

**Files:**
- Modify: `.claude/skills/ugc-full-video-pipeline/SKILL.md` (append)

- [ ] **Step 1: Append the "Entrées" and "Pré-vérifications" sections**

Append to `.claude/skills/ugc-full-video-pipeline/SKILL.md`:

````markdown

## Entrées

| Paramètre | Défaut | Notes |
|---|---|---|
| `session_dir` | dernier dossier sous `output/` (le plus récent par date ISO) | Doit contenir `script.md` et `voice_sections_1.2x_lofi/`. |
| `--segments` | tous les segments du script | Liste 1-based séparée par virgules, ex : `--segments 2,4`. Utile pour régénérer un seul plan. |
| `--force` | off | Régénère même si `videos/segment_<N>_final.mp4` existe déjà. |

## Pré-vérifications (silencieuses sauf erreur)

À l'ouverture du skill, vérifie en parallèle (un message d'erreur ferme le pipeline) :

1. `<session_dir>/script.md` existe et parse au moins un segment.
2. `<session_dir>/voice_sections_1.2x_lofi/section-<NN>.mp3` existe pour chaque N ciblé.
3. `<session_dir>/voice_sections_1.2x/section-<NN>.mp3` existe pour chaque N ciblé (utilisé par `generate_video_seedance.py` pour calculer la durée Seedance).
4. `scripts/characters.json` existe et a au moins une entrée match avec la persona du script (voir Étape 1).
5. `scripts/generate_video_seedance.py`, `scripts/generate_image.sh`, `scripts/storage.sh` existent.
6. `command -v ffmpeg` retourne un chemin.
7. `.env` à la racine du repo contient `ARK_API_KEY`, `OPENAI_API_KEY`, `CELLAR_*`.

Si une vérif échoue : message d'erreur en une ligne pointant le pré-requis manquant. **Pas d'auto-recovery** — par exemple, ne lance jamais `ugc-voice-lofi` toi-même si la lo-fi manque, demande à l'utilisateur de la produire.

## Étape 0 — Parser `script.md`

Ouvre `<session_dir>/script.md`. Découpe le fichier en segments en utilisant comme séparateur les en-têtes au format `**[h:mm – h:mm] — TITRE**` (ex : `**[0:00 – 0:03] — HOOK**`). L'index 1-based de chaque en-tête correspond directement au numéro de segment N utilisé partout en aval (cohérent avec `voice_sections_1.2x_lofi/section-<NN>.mp3`).

Pour chaque segment, extrais :

- **`stage_direction`** : la première ligne en italique (`*…*`) qui suit l'en-tête. Exemple : `*Plan ancre : selfie face caméra dans la salle de bain, téléphone tenu à hauteur de visage. Lumière naturelle.*`
- **`voice_text`** : la ligne `**Voix :**` (texte entre guillemets droits, contenu uniquement, on garde les tags ElevenLabs `[WHISPER]`, `[SERIOUS]`, etc.).
- **`on_screen_text`** : la ligne `*Texte à l'écran :* `…`` si présente.
- **`insert_annotations`** : toute ligne en italique additionnelle (`*Insert : …*`) après la stage direction.

Ensuite, pour chaque segment, calcule deux flags :

- **`is_anchor`** : `True` ssi `stage_direction.lower()` contient le substring `plan ancre`.
- **`products_detected`** : liste des slugs catalogue dont au moins un alias keyword apparaît dans `(voice_text + on_screen_text + insert_annotations)`.lower(). Voir l'alias map à l'Étape 2.

Récupère également l'en-tête du script pour la persona (ligne `**Persona :**`) et le décor (souvent dans la même ligne, ex : `Tournage dans une salle de bain classique`).

> **Pourquoi ne pas utiliser un parser regex strict** : les en-têtes peuvent varier légèrement (`—` vs `-`, espaces, accents). Utilise un parser tolérant (regex permissif sur `**\[\d+:\d+`) et vérifie en sortie que le nombre de segments parsés correspond au nombre de fichiers `voice_sections_1.2x/section-NN.mp3`. Si mismatch, stoppe et pointe l'incohérence.
````

- [ ] **Step 2: Sanity-read the file**

```bash
wc -l .claude/skills/ugc-full-video-pipeline/SKILL.md
```

Expected: ~80-100 lines (frontmatter + intro + this section).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/ugc-full-video-pipeline/SKILL.md
git commit -m "$(cat <<'EOF'
ugc-full-video-pipeline: inputs, pre-checks, script parse rules

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Step 1 (persona) and Step 2 (product alias map)

**Files:**
- Modify: `.claude/skills/ugc-full-video-pipeline/SKILL.md` (append)

- [ ] **Step 1: Append Step 1 — persona resolution**

Append to `SKILL.md`:

````markdown

## Étape 1 — Résoudre la persona → character asset

Lis `<session_dir>/script.md` et extrais la persona depuis l'en-tête (ligne `**Persona :**`). Charge `scripts/characters.json`. Match en deux passes :

1. **Genre strict** : `gender == "male"` ou `gender == "female"`. Filtre la liste sur ce critère uniquement.
2. **Âge le plus proche** : sur les entrées restantes, prends celle qui minimise `abs(persona_age - candidate.age)`.

Capture du gagnant : `id`, `seedance_asset_id`, `description`. Annonce une seule ligne :

```
Personnage : <id> (asset <seedance_asset_id>) — match avec persona <persona courte>.
```

Si aucun candidat ne match (mauvais genre, ou catalogue vide), **stoppe** avec :

```
Aucun character asset BytePlus ne match la persona du script (<persona>).
Enregistre un nouveau personnage dans la BytePlus Ark Console
(Console → Digital Character) puis ajoute la ligne à scripts/characters.json
avec son seedance_asset_id, son elevenlabs_voice_id, son genre et son âge.
```

Ne défaut jamais sur un personnage approchant — la cohérence visuelle entre plans repose sur ce match strict.

## Étape 2 — Construire la table d'alias produits + map taille

Charge `brand/products/catalog.yaml`. Pour chaque entrée `kind: single`, capture `slug`, `name`, `hero_image`. Ignore les `kind: pack` (les packs sont juste des bundles, pas de packshot dédié).

Pour chaque slug, charge `brand/products/<slug>.md` (s'il existe) et cherche la ligne :

```
**Référence taille du produit :** https://...
```

Capture l'URL si présente. Sinon, marque `size_reference = None` pour ce slug.

**Table d'alias** (à coder en dur dans le skill, tweakable mais cible la robustesse, pas l'exhaustivité) :

| Slug | Keywords (substring match, case-insensitive) |
|---|---|
| `creme-apaisante` | `crème`, `tube`, `noisette`, `apaise` |
| `complement-circulation-transit` | `complément`, `gélule`, `circulation`, `transit` |
| `probiotique` | `probiotique` |
| `soin-lavant-hygiene-intime` | `soin lavant`, `savon`, `lavant` |

Pour chaque segment, le set des produits détectés est l'union de tous les slugs dont au moins un keyword apparaît dans `(voice_text + on_screen_text + insert_annotations)` (toujours en lower-case).

**Faux positifs acceptés** : un keyword "métaphorique" qui matche n'est pas grave — une référence image en plus ralentit Seedance d'~0 ms et n'altère pas la sortie. Un faux négatif (produit cité mais non détecté) casse la fidélité du packaging à l'écran. Donc on biaise vers la sur-détection.

> Si l'utilisateur ajoute un nouveau produit au catalogue, il doit aussi ajouter sa ligne à cette table. C'est volontairement statique pour rester explicite (pas d'embeddings ni d'extraction LLM à chaque run).
````

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/ugc-full-video-pipeline/SKILL.md
git commit -m "$(cat <<'EOF'
ugc-full-video-pipeline: persona match + product alias table

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Step 3 (segment 1) and Step 4 (face mask extraction)

**Files:**
- Modify: `.claude/skills/ugc-full-video-pipeline/SKILL.md` (append)

- [ ] **Step 1: Append Step 3 — segment 1 generation**

Append to `SKILL.md`:

````markdown

## Étape 3 — Générer le segment 1 (le seed du plan ancre)

Le segment 1 est toujours généré **en premier** et **sans face-mask** : c'est lui qui sert de seed pour fabriquer le face-mask utilisé par les segments suivants. Procédure :

### 3.1 — Écrire `frames/segment_1/video_prompt.txt`

```bash
mkdir -p "<session_dir>/frames/segment_1"
```

Le prompt suit le template documenté dans `.claude/skills/ugc-video-seedance/SKILL.md` (section "Écriture du video_prompt.txt"). Récapitule ici les pièces non-négociables :

- **Description du personnage** : recopie tels quels les détails de l'en-tête `**Persona :**` du script (âge, look, tenue, cheveux, décor). Pas de paraphrase.
- **Plan caméra ancre** : `iPhone front-camera selfie clip`, `phone held selfie-style at arm's length`, `front camera lens`, `fixed framing`.
- **Direction tonale** : dérive du ton du segment et des tags ElevenLabs (`[WHISPER]` → `almost whispered, confidential tone` ; `[SERIOUS]` → `calm, articulated`).
- **Cadence labiale `[Audio 1]`** (toujours, segment ancre) :

  ```
  Lip movement, phoneme timing, pauses and breathing are tightly
  synchronised with [Audio 1] — match every syllable, every micro-pause
  and every breath in [Audio 1].
  ```

- **Phrase française exacte** entre guillemets droits, telle qu'elle est dans le script (sans paraphrase, sans traduction). Découpée en sous-phrases avec des `(small pause)` entre les morceaux. Sans cette phrase littérale, Seedance hallucine.
- **Mouvement labial + expression** : `mouth opens and closes softly with each syllable`, `eyes locked on the lens`, `micro head shifts of 1-3 degrees`, `natural breathing between phrases`.
- **Stabilité** : `fixed framing — no camera movement, no zoom, no pan, no tilt, no rotation`, `background completely still`, `lighting stable across the whole clip with no flicker`.
- **Look UGC** : `iPhone front-camera look — soft, slightly compressed, mild barrel distortion, faint chromatic aberration, mild noise in shadows. Realistic, imperfect, honest UGC — not glossy, not cinematic.`
- **Anti-watermark** : `Absolutely no on-screen text, captions, subtitles, or watermarks visible in the image.`

Le prompt est en **anglais** (Seedance est plus stable en anglais), mais la phrase parlée reste en **français pur** entre guillemets droits.

Référence concrète à recopier-adapter : `output/2026-05-08-le-3eme/frames/segment_2/video_prompt.txt` (déjà sur master).

### 3.2 — Construire la liste `--image` pour le segment 1

Le segment 1 ne reçoit **jamais** le face-mask (il n'existe pas encore). Sa liste `--image` est uniquement composée des références produits détectées à l'Étape 2 :

```python
images = []
for slug in products_detected[1]:
    images.append(catalog[slug]["hero_image"])  # https URL Shopify
    if size_reference[slug]:
        images.append(size_reference[slug])     # https URL Shopify
```

Si `products_detected[1]` est vide, la liste est vide et on omet `--image`.

### 3.3 — Lancer Seedance

```bash
set -a; source .env; set +a

./scripts/generate_video_seedance.py "<session_dir>" 1 \
  --character-asset-id "<seedance_asset_id>" \
  $(printf -- '--image %s ' "${images[@]}")
```

Notes :
- L'audio lo-fi est **auto-attaché** par le script à partir de `voice_sections_1.2x_lofi/section-01.mp3`. Ne jamais passer `--audio` manuellement depuis ce skill.
- `generate_audio=True` est le défaut (Seedance synthétise la voix dans le mp4 final, biaisée par l'audio lo-fi pour la cadence + le texte exact du prompt pour le contenu).
- Sortie : `<session_dir>/videos/segment_1_final.mp4`. Si `--force` n'est pas passé et que ce fichier existe déjà, **skip** cette étape (mais continue à l'étape 4 face-mask).

## Étape 4 — Extraire le face-mask depuis le segment 1

### 4.1 — Première frame via ffmpeg

```bash
mkdir -p "<session_dir>/frames/segment_1"

ffmpeg -y -i "<session_dir>/videos/segment_1_final.mp4" \
  -vframes 1 -update 1 -q:v 2 \
  "<session_dir>/frames/segment_1/first_frame.png"
```

`-update 1` silence le warning "filename does not contain an image sequence pattern". `-q:v 2` quasi-lossless. `-vframes 1` strictement la frame 0.

### 4.2 — Construire le prompt face-mask

Réutilise le template documenté dans `.claude/skills/ugc-face-mask-extractor/SKILL.md` (section "Construire le prompt de face-mask"). Récap des blocs non-négociables :

- **Bloc forme opaque** : `paint a single opaque flat oval of solid neutral light grey completely covering the {{persona courte — ex: man's}} face. The shape must be: large enough to cover from forehead to chin and from ear to ear, fully opaque, smooth-edged, no transparency, no gradient, no texture, no features, no eyes, no mouth, no nose, no shadows, no highlights — a clean flat blocking shape sitting on top of the face area like a censorship sticker.`
- **Bloc EVERYTHING else IDENTICAL** (reprend la formulation exacte de `.claude/skills/ugc-face-mask-extractor/SKILL.md` lignes 64-66) — non négociable, sinon le décor dérive.
- **Bloc no transparency, no gradient** — non négociable, sinon le visage transparaît.
- **Bloc Photoreal everywhere except the shape itself + iPhone front-camera look + anti-watermark.**

Récupère les détails persona/décor :

- En priorité depuis `<session_dir>/frames/segment_1/video_prompt.txt` (vient d'être écrit à l'Étape 3.1).
- Sinon depuis l'en-tête `**Persona :**` du `script.md`.

Aspect ratio : déduis-le des dimensions du PNG via `sips -g pixelWidth -g pixelHeight "<session_dir>/frames/segment_1/first_frame.png"`. Si le ratio est ≈9:16, écris `vertical 9:16` dans le prompt.

Sauvegarde le prompt dans `<session_dir>/frames/segment_1/face_mask_prompt.txt` avant l'appel API (permet d'itérer sans re-rédiger).

### 4.3 — Appel `generate_image.sh --ref`

```bash
set -a; source .env; set +a

OPENAI_IMAGE_QUALITY=high \
  ./scripts/generate_image.sh \
    --ref "<session_dir>/frames/segment_1/first_frame.png" \
    "<session_dir>/frames/segment_1/first_frame_face_mask.png" \
    "$(cat "<session_dir>/frames/segment_1/face_mask_prompt.txt")" \
    1024x1536
```

`OPENAI_IMAGE_QUALITY=high` est obligatoire (memory utilisateur). En `low` le bord de la forme est crénelé et le décor est reconstruit flou.

Pour un script vertical 9:16, `1024x1536` est la bonne taille (sortie cropée à 864x1536 par défaut). Pour landscape passe `1536x1024 --no-crop`.

### 4.4 — Vérification visuelle rapide

Après la génération, ouvre/affiche les deux PNGs (`first_frame.png` et `first_frame_face_mask.png`) inline pour que l'utilisateur puisse comparer. Si le masque déborde sur le cou/téléphone, ou si le décor a visiblement bougé, **signale-le** dans le rapport final et propose un re-tirage. Ne re-tire pas automatiquement — la variance API a un coût et l'utilisateur doit valider.

> Cas de fallback **gpt-image-2 → gpt-image-1** : `generate_image.sh` retombe automatiquement sur `gpt-image-1` si le compte OpenAI n'est pas vérifié pour `gpt-image-2`. La précision du masque est plus basse mais utilisable. Mentionne le fallback une fois dans le rapport final si déclenché.
````

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/ugc-full-video-pipeline/SKILL.md
git commit -m "$(cat <<'EOF'
ugc-full-video-pipeline: segment 1 generation + face-mask extraction

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Step 5 (segments 2..N) and Step 6 (final report)

**Files:**
- Modify: `.claude/skills/ugc-full-video-pipeline/SKILL.md` (append)

- [ ] **Step 1: Append Step 5 — segments 2..N**

Append to `SKILL.md`:

````markdown

## Étape 5 — Générer les segments 2..N (séquentiel)

Boucle séquentielle, **jamais en parallèle**. L'utilisateur veut pouvoir inspecter la lipsync de chaque plan avant de payer le suivant.

Pour chaque segment N ≥ 2 (dans l'ordre du script, sauf si `--segments` filtre) :

### 5.1 — Décider du template de prompt selon `is_anchor`

- **Si `is_anchor == True`** : utilise le template "plan ancre" décrit à l'Étape 3.1 (selfie front-camera + cadence `[Audio 1]` + phrase française exacte + tag ElevenLabs).
- **Si `is_anchor == False`** (insert/B-roll, ex : `*Insert : gros plan tube en main.*`) : utilise un template close-up :

  ```
  Macro/close-up shot of {{description du sujet — ex: a hand holding the
  Butt Butter cream tube}}. Photoreal, soft natural daylight, shallow
  depth of field, iPhone rear-camera UGC look. Stable framing — no zoom,
  no pan. The product packaging is clearly readable. No on-screen text,
  no captions, no watermarks.
  ```

  Pas de cadence `[Audio 1]` pour les inserts (pas de lipsync à driver). Pas de phrase française exacte non plus (l'insert est silencieux côté image). L'audio lo-fi est **quand même** attaché — Seedance utilise sa durée pour caler la durée vidéo, et la voix de fond reste cohérente avec le segment.

Écris le prompt dans `<session_dir>/frames/segment_<N>/video_prompt.txt` avant l'appel.

### 5.2 — Construire la liste `--image`

Ordre :

1. **Si `is_anchor == True` ET N ≥ 2** : ajoute le face-mask local

   ```
   <session_dir>/frames/segment_1/first_frame_face_mask.png
   ```

   `generate_video_seedance.py` détecte que c'est un chemin local et le passe à `storage.sh` pour l'uploader sur Cellar avant l'appel API.

2. **Pour chaque slug dans `products_detected[N]`** :
   - `catalog[slug]["hero_image"]` (https Shopify, passthrough)
   - `size_reference[slug]` si non-`None` (https Shopify, passthrough)

Si la liste est vide (segment ancre sans produit + segment 1 omis car face-mask seulement seg2+), c'est valide — on appelle Seedance avec character asset + audio lo-fi seuls.

### 5.3 — Lancer Seedance

```bash
set -a; source .env; set +a

./scripts/generate_video_seedance.py "<session_dir>" "$N" \
  --character-asset-id "<seedance_asset_id>" \
  $(printf -- '--image %s ' "${images[@]}")
```

Mêmes règles qu'à l'Étape 3.3 : pas de `--audio` manuel (auto-attaché), `generate_audio=True` par défaut, sortie `<session_dir>/videos/segment_<N>_final.mp4`.

### 5.4 — Skip si déjà existant

Avant de lancer Seedance pour un N donné, vérifie `<session_dir>/videos/segment_<N>_final.mp4`. S'il existe ET que `--force` n'a pas été passé, log une ligne et skip :

```
[segment <N>] skipped (already exists, pass --force to regenerate)
```

### 5.5 — Si Seedance échoue sur un segment

Si `generate_video_seedance.py` retourne un code de sortie ≠ 0 ou si la tâche Ark passe en `status=failed`, **log l'erreur** (recopie le message Ark) et **continue avec le segment N+1**. Ne stoppe pas le pipeline pour un segment fautif. Le rapport final marquera les segments manquants.

## Étape 6 — Rapport final à l'utilisateur

Après la dernière itération, affiche un bloc compact, **sans commentaire** sur les étapes qui ont marché. Format :

```
Personnage Seedance : <id> (asset <seedance_asset_id>) — persona <résumé>.
Face-mask : <session_dir>/frames/segment_1/first_frame_face_mask.png[, gpt-image-1 fallback]

segment 1 — anchor=Y — products=[]                 — videos/segment_1_final.mp4 (5.0s, 1.3 MB)
segment 2 — anchor=Y — products=[]                 — videos/segment_2_final.mp4 (5.0s, 1.4 MB) [face mask attached]
segment 3 — anchor=Y — products=[]                 — videos/segment_3_final.mp4 (10.0s, 2.5 MB) [face mask attached]
segment 4 — anchor=Y — products=[creme-apaisante]  — videos/segment_4_final.mp4 (10.0s, 2.6 MB) [face mask + packshot + size ref]
segment 5 — anchor=Y — products=[]                 — videos/segment_5_final.mp4 (5.0s, 1.3 MB) [face mask attached]

Suite : concat des segments via ffmpeg concat ou scripts/combine_segment.sh.
```

Récupère durée + taille via `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 <mp4>` et `ls -lh <mp4>`. Si un segment a échoué, remplace la ligne par :

```
segment 4 — FAILED — <message Ark résumé>
```

Pas de commentaire gratuit ("génération réussie", "fichiers écrits"). Seulement ce qui est notable ou cassé.

````

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/ugc-full-video-pipeline/SKILL.md
git commit -m "$(cat <<'EOF'
ugc-full-video-pipeline: segments 2..N loop + final report

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Anti-patterns, Errors, Overrides, end-of-skill

**Files:**
- Modify: `.claude/skills/ugc-full-video-pipeline/SKILL.md` (append)

- [ ] **Step 1: Append the final sections**

Append to `SKILL.md`:

````markdown

## Override courants

- **Régénérer un seul segment** : `--segments 3` + `--force`. Réutilise le face-mask déjà extrait (s'il existe) ou re-tire l'Étape 4 si l'utilisateur le demande explicitement.
- **Re-tirer juste le face-mask** (variance API) : si `frames/segment_1/first_frame.png` existe déjà, saute l'Étape 4.1 (extraction ffmpeg) et passe directement à l'Étape 4.3 (appel API). Le PNG `first_frame_face_mask.png` est écrasé. Coût : ~30s.
- **Forcer un personnage non-catalogue** : si l'utilisateur passe un `seedance_asset_id` explicite (test d'un nouvel asset BytePlus pas encore inscrit dans `characters.json`), saute l'Étape 1 et utilise l'asset fourni.
- **Variante silencieuse** d'un segment (debug A/B) : passer `--no-generate-audio` à `generate_video_seedance.py`. Pas un mode officiel du skill, à invoquer manuellement.
- **Segment-only** sans face-mask (test prompt seul) : invoquer directement `ugc-video-seedance` sur ce segment, ne pas passer par ce skill.

## Anti-patterns à éviter

- **Générer les segments en parallèle.** Le pipeline est séquentiel par design : segment 1 doit finir avant le face-mask, et même les segments 2..N restent séquentiels. Ça permet à l'utilisateur d'inspecter chaque lipsync avant de payer le suivant, et ça garde la queue Ark calme. **Pas de `&` ni de `xargs -P` derrière les appels Seedance.**
- **Réutiliser le face-mask avant qu'il existe.** Segment 1 → face-mask → segments 2..N. Ne tente jamais de lancer le segment 2 en parallèle de l'extraction face-mask.
- **Attacher le face-mask à un segment insert (non-ancre).** Tue le cadrage close-up que l'insert est censé livrer. Le flag `is_anchor` se vérifie segment par segment, pas une fois pour toutes.
- **Sauter le `video_prompt.txt` par segment.** Un prompt générique entre segments produit une dérive visible (cadrage, lumière, ton). Chaque segment a son propre prompt, ancré sur sa stage direction et son texte voix.
- **Défaut sur un personnage approchant.** Si `characters.json` n'a pas de match strict (genre + âge proche), **stoppe**. Ne prends pas le moins pire — la cohérence visuelle entre plans repose sur le match.
- **Auto-lancer les skills amont.** Ce skill suppose script + lo-fi déjà produits. Ne lance jamais `ugc-script-writer`, `ugc-voice-generator` ou `ugc-voice-lofi` toi-même. Stoppe et pointe.
- **Passer `--audio` manuellement** depuis le skill. `generate_video_seedance.py` auto-attache `voice_sections_1.2x_lofi/section-NN.mp3`. Le passer à la main risque de pointer vers le mauvais fichier (ex : `voice_sections/` non-accéléré, ou `voice_sections_1.2x/` non-lo-fi).

## Erreurs possibles

- **`script.md` parse 0 segment** : l'en-tête `**[h:mm – h:mm]**` est absent ou mal formé. Vérifie manuellement le script et corrige le format.
- **Mismatch nombre de segments parsés vs nombre de fichiers `voice_sections_1.2x/section-NN.mp3`** : le script et les voix ne sont pas synchros. Probablement un re-run partiel de `ugc-voice-generator`. Stoppe et demande à l'utilisateur de re-générer les voix.
- **`ARK_API_KEY not set` / `OPENAI_API_KEY not set`** : ajouter dans `.env` à la racine du repo.
- **Aucun match persona dans `characters.json`** : suivre l'instruction de l'Étape 1 — enregistrer un nouveau character asset BytePlus puis ajouter la ligne au catalogue.
- **`storage.sh ... failed (exit 254)`** : version récente d'aws-cli sur HeadObject 404. Le `storage.sh` actuel gère le cas, sinon vérifier que la fonction `remote_size_etag` enveloppe `aws head-object` dans un `if ... fi`.
- **`MissingContentLength`** : Cellar refuse les bodies en streaming/trailer checksum. Vérifier que `storage.sh` exporte `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` et `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required`.
- **HTTP 401/403 Ark** : clé invalide ou pas d'accès au modèle Seedance.
- **Task Ark `failed`** : message d'erreur dans la réponse JSON. Souvent prompt trop long, langue mélangée, ou character asset invalide. Logger, skipper, continuer.
- **gpt-image-2 403 "must be verified"** : `generate_image.sh` retombe sur gpt-image-1. Mentionner le fallback dans le rapport.
- **Face-mask semi-transparent / on devine le visage** : bloc "no transparency, no gradient" raccourci, ou `OPENAI_IMAGE_QUALITY` pas en `high`. Re-tirer.
- **Lipsync clairement décalée sur un segment ancre** : la phrase française exacte n'est pas dans le prompt, ou est paraphrasée en anglais. La remettre telle quelle entre guillemets droits, raffiner les `(small pause)`, ré-générer ce segment seul avec `--segments <N> --force`.
- **Texte halluciné** (le personnage dit autre chose) : même cause/correction que la lipsync décalée.
- **Décor visiblement différent entre segment 1 et segment 2** : le face-mask n'a pas été passé en `--image` au segment 2 (vérifier que `is_anchor` est bien `True`), ou Seedance a interprété le character asset au lieu du face-mask comme cadre de réf. Re-tirer le segment 2 avec face-mask explicitement listé en premier `--image`.
````

- [ ] **Step 2: Verify total file size is reasonable**

```bash
wc -l .claude/skills/ugc-full-video-pipeline/SKILL.md
```

Expected: between 250 and 400 lines.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/ugc-full-video-pipeline/SKILL.md
git commit -m "$(cat <<'EOF'
ugc-full-video-pipeline: overrides, anti-patterns, error catalog

Skill body complete. Smoke test in follow-up.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Smoke test — dry-run parse on the existing session

**Files:**
- Read-only: `.claude/skills/ugc-full-video-pipeline/SKILL.md`, `output/2026-05-08-le-3eme/script.md`, `scripts/characters.json`, `brand/products/catalog.yaml`, `brand/products/*.md`

**Goal:** Verify the skill is discoverable and that, when invoked, Claude correctly executes the parsing/persona/alias steps **without** calling Seedance or OpenAI yet. This is a "did the procedure read the right files and produce the right intermediate state" check.

- [ ] **Step 1: Inspect the existing session manually**

```bash
ls output/2026-05-08-le-3eme/
ls output/2026-05-08-le-3eme/voice_sections_1.2x_lofi/
ls output/2026-05-08-le-3eme/videos/
head -10 output/2026-05-08-le-3eme/script.md
```

Expected:
- `script.md`, `voice_sections_1.2x_lofi/`, `videos/`, `frames/` exist.
- `voice_sections_1.2x_lofi/` has `section-01.mp3` ... `section-05.mp3`.
- `videos/` has at least `segment_1_final.mp4` and `segment_2_final.mp4`.
- `script.md` first line shows `**Hook source :**`, header includes `**Persona :**`, segments delimited by `**[0:XX – 0:YY] —`.

- [ ] **Step 2: Manually run the parse step (mental dry-run)**

Open `script.md` and verify by eye:
- 5 segments (HOOK, RÉVÉLATION, PROBLÈME, PRODUIT, PUNCH FINAL + CTA).
- Every segment has `*Plan ancre*` in its stage direction (so `is_anchor == True` for all 5).
- Segment 4 (PRODUIT) mentions `crème`, `tube`, `noisette`, `apaise` → should detect `creme-apaisante`.
- Segments 1, 2, 3, 5 mention no product keywords → empty product list.

- [ ] **Step 3: Verify persona match**

```bash
cat scripts/characters.json
```

Expected: `french-farmer-60` is `male, 60`. Script persona is `Homme 58-62 ans`. Match: gender male strict ✓, age 60 vs 60 (target midpoint) → distance 0 ✓.

- [ ] **Step 4: Verify the alias map covers the script's product mentions**

Re-read segment 4 from `script.md`:

```
"[SERIOUS]J'ai essayé plein de choses. Celui-là c'est une crème. T'en
mets une noisette, ça apaise rapidement. Sans piquer, sans odeur de
pharmacie."

Insert [0:19 – 0:22] : gros plan tube de Crème Apaisante en main, packaging
Butt Butter visible.
```

Keywords matched against `creme-apaisante` aliases (`crème`, `tube`, `noisette`, `apaise`): `crème` ✓, `tube` ✓, `noisette` ✓, `apaise` ✓. All four hit. Detection robust.

- [ ] **Step 5: Verify size reference present for `creme-apaisante`**

```bash
grep "Référence taille" brand/products/creme-apaisante.md
```

Expected: one line with `https://cdn.shopify.com/...Test_main_-100-v2.jpg...`. Used as `--image` alongside `hero_image`.

- [ ] **Step 6: Commit a marker note (optional)**

If the dry-run reveals a parser-spec mismatch (e.g. an en-tête uses `-` instead of `—`), update the SKILL.md "Étape 0" parser hint and commit:

```bash
git add .claude/skills/ugc-full-video-pipeline/SKILL.md
git commit -m "ugc-full-video-pipeline: tolerate dash variants in segment headers"
```

If the dry-run is clean, no commit needed. Move to Task 8.

---

## Task 8: Smoke test — end-to-end on segment 3 (face mask + new segment)

**Files:**
- Will create: `output/2026-05-08-le-3eme/frames/segment_1/first_frame.png`, `output/2026-05-08-le-3eme/frames/segment_1/face_mask_prompt.txt`, `output/2026-05-08-le-3eme/frames/segment_1/first_frame_face_mask.png`, `output/2026-05-08-le-3eme/frames/segment_3/video_prompt.txt`, `output/2026-05-08-le-3eme/videos/segment_3_final.mp4`

**Goal:** Run the skill on `output/2026-05-08-le-3eme/` to generate **only segment 3** (which doesn't exist yet) — exercises Étape 4 (face mask) + Étape 5 (anchor with face mask, no product) without burning credits on segments 1, 2, 4, 5 that already exist or aren't needed for the smoke test.

- [ ] **Step 1: Confirm segment 3 doesn't exist yet**

```bash
ls -la output/2026-05-08-le-3eme/videos/segment_3_final.mp4
```

Expected: `No such file or directory`. If the file exists, this smoke test target won't exercise Étape 5 properly — pick a different missing segment or pass `--force`.

- [ ] **Step 2: Confirm the lo-fi audio for segment 3 exists**

```bash
ls -la output/2026-05-08-le-3eme/voice_sections_1.2x_lofi/section-03.mp3
ls -la output/2026-05-08-le-3eme/voice_sections_1.2x/section-03.mp3
```

Expected: both files exist (used for `--audio` auto-attach and Seedance duration calc respectively).

- [ ] **Step 3: Confirm `.env` is set**

```bash
grep -E "^(ARK_API_KEY|OPENAI_API_KEY|CELLAR_)" .env | wc -l
```

Expected: ≥ 4 lines (ARK + OPENAI + CELLAR_HOST + CELLAR_KEY_ID + CELLAR_KEY_SECRET).

- [ ] **Step 4: Invoke the skill with the test target**

In a fresh Claude conversation (or in the current one), run:

> Lance le skill `ugc-full-video-pipeline` sur `output/2026-05-08-le-3eme/` pour le segment 3 uniquement. Ne régénère pas ce qui existe déjà.

Expected behavior:
1. Pré-vérifications passent silencieusement.
2. Étape 0 parse 5 segments. is_anchor[3] = True. products_detected[3] = [].
3. Étape 1 sélectionne `french-farmer-60` → `asset-20260225022658-zn9dj`.
4. Étape 2 alias map chargée. Pour le segment 3 (PROBLÈME, voix `Après 50 ans, c'est 1 sur 2...`), aucun keyword produit ne match. Detected = [].
5. Étape 3 skippée (segment 1 final.mp4 existe déjà, `--force` pas passé).
6. Étape 4 face mask :
   - Si `frames/segment_1/first_frame.png` n'existe pas → ffmpeg l'extrait depuis `videos/segment_1_final.mp4`.
   - Si `frames/segment_1/first_frame_face_mask.png` n'existe pas → appel `generate_image.sh --ref` produit le PNG.
7. Étape 5 segment 3 :
   - Écrit `frames/segment_3/video_prompt.txt` (template anchor + cadence `[Audio 1]` + phrase française "Après 50 ans, c'est 1 sur 2. Vraiment. Et on en parle pas. C'est notre génération qui se tait." entre guillemets droits).
   - Liste `--image` = `[frames/segment_1/first_frame_face_mask.png]` (anchor + N≥2, pas de produit).
   - Lance `generate_video_seedance.py output/2026-05-08-le-3eme 3 --character-asset-id asset-20260225022658-zn9dj --image .../first_frame_face_mask.png`.
   - Sortie `videos/segment_3_final.mp4`.
8. Étape 6 rapport :
   ```
   Personnage Seedance : french-farmer-60 (asset asset-20260225022658-zn9dj) — persona Homme 58-62 ans senior actif.
   Face-mask : output/2026-05-08-le-3eme/frames/segment_1/first_frame_face_mask.png

   segment 3 — anchor=Y — products=[] — videos/segment_3_final.mp4 (Xs, Y MB) [face mask attached]
   ```

- [ ] **Step 5: Verify outputs**

```bash
ls -la output/2026-05-08-le-3eme/frames/segment_1/
ls -la output/2026-05-08-le-3eme/frames/segment_3/
ls -la output/2026-05-08-le-3eme/videos/segment_3_final.mp4
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
  output/2026-05-08-le-3eme/videos/segment_3_final.mp4
```

Expected:
- `frames/segment_1/first_frame.png` exists (~MB-sized PNG).
- `frames/segment_1/first_frame_face_mask.png` exists (~MB-sized PNG, opaque oval over face).
- `frames/segment_3/video_prompt.txt` exists with the literal voice phrase between straight quotes and the `[Audio 1]` lipsync clause.
- `videos/segment_3_final.mp4` exists, duration roughly the audio duration + ~1s buffer (so ~7-8s for segment 3 voice ≈ 6.5s).

- [ ] **Step 6: Visual sanity check**

Open `videos/segment_3_final.mp4` in Quicktime/preview. Verify:
- Same character as segment 1 and segment 2 (same face, same hair, same skin tone).
- Same bathroom décor as segment 1 (mirror, tile, lighting).
- Lip movement roughly aligns with the French voice over.
- No watermark, no captions, no on-screen text.

If any of those fail, root-cause:
- Different face → check that `--character-asset-id` was passed.
- Different décor → check that `--image first_frame_face_mask.png` was passed first in the list (face-mask anchors composition; later refs only bias content).
- Lipsync drift → re-read the prompt in `frames/segment_3/video_prompt.txt`, ensure the literal French phrase is present and the `[Audio 1]` clause is intact.
- On-screen text appearing → strengthen the anti-watermark clause.

If a fix is needed, edit the SKILL.md, `--force` re-run segment 3, commit the doc fix.

- [ ] **Step 7: Commit smoke-test artifacts (optional)**

```bash
# Only if the smoke test produced anything worth keeping in git
# (probably nothing — output/ might be gitignored)
git status output/2026-05-08-le-3eme/
```

If `output/` is gitignored (likely — generated artifacts), no commit needed.

---

## Task 9: Final review and skill description sanity-check

**Files:**
- Read-only: `.claude/skills/ugc-full-video-pipeline/SKILL.md`

- [ ] **Step 1: Re-read the frontmatter `description`**

```bash
head -5 .claude/skills/ugc-full-video-pipeline/SKILL.md
```

Verify the description includes the user-likely trigger phrases in French:
- "génère toute la vidéo"
- "pipeline complet vidéo"
- "vidéo UGC complète"
- "lance la génération vidéo de bout en bout"
- "génère tous les segments"

If any are missing, edit and commit:

```bash
git add .claude/skills/ugc-full-video-pipeline/SKILL.md
git commit -m "ugc-full-video-pipeline: broaden trigger phrases"
```

- [ ] **Step 2: Verify nothing in the SKILL.md contradicts the spec**

Cross-check the SKILL.md against `docs/superpowers/specs/2026-05-08-ugc-full-video-pipeline-design.md`:
- Anchor rule: `Plan ancre` substring, case-insensitive. ✓
- Product alias map matches the spec table. ✓
- Sequential, never parallel. ✓
- Face mask attached only for N ≥ 2 AND anchor. ✓
- `generate_video_seedance.py` invoked without `--audio` (auto-attach). ✓
- Face mask via `generate_image.sh --ref`, `OPENAI_IMAGE_QUALITY=high`, `1024x1536`. ✓
- Persona match: gender strict + closest age, no fallback. ✓
- `--force` semantics: skip if `_final.mp4` exists. ✓
- Failure on segment N: log + skip, don't stop pipeline. ✓
- Pre-checks: 7 listed in spec, all present in skill. ✓

If any drift, fix and commit.

- [ ] **Step 3: Verify against existing skills' style**

The SKILL.md should feel consistent with `.claude/skills/ugc-video-seedance/SKILL.md` and `.claude/skills/ugc-face-mask-extractor/SKILL.md`:
- French-first prose, English for pure technical terms.
- Bash blocks with `set -a; source .env; set +a` where credentials are needed.
- "Anti-patterns à éviter" and "Erreurs possibles" sections at the end.
- "Sortie attendue à l'utilisateur" or "Rapport final" describing what to print.

- [ ] **Step 4: Verify final commit graph**

```bash
git log --oneline -10
```

Expected: 6 commits added by this plan, on top of the spec commit:
1. Scaffold ugc-full-video-pipeline skill
2. inputs, pre-checks, script parse rules
3. persona match + product alias table
4. segment 1 generation + face-mask extraction
5. segments 2..N loop + final report
6. overrides, anti-patterns, error catalog
   (+ optional fix commits from Tasks 7-8)

- [ ] **Step 5: Final summary to the user**

Paste a one-block summary:

```
Skill ugc-full-video-pipeline en place.
Body : .claude/skills/ugc-full-video-pipeline/SKILL.md (~Y lignes)
Spec : docs/superpowers/specs/2026-05-08-ugc-full-video-pipeline-design.md
Smoke test : output/2026-05-08-le-3eme/ (segment 3 généré end-to-end avec face-mask)

Suite probable :
- Itération sur l'alias map quand de nouveaux produits arrivent au catalogue.
- Skill ugc-concat pour assembler les N segments en un mp4 final.
```

---

## Self-Review Notes

**Spec coverage:**
- Goal & Non-goals → covered by intro + Tasks 2-6.
- Inputs (session_dir, --segments, --force) → Task 2 Step 1.
- Pipeline Steps 0-6 → Tasks 2-5.
- Reference matrix → Tasks 4 (segment 1) + 5 (segments 2..N) Step 5.2.
- Anchor detection → Task 2 Step 1, locked rule.
- Product detection (alias map) → Task 3 Step 1.
- Per-segment video_prompt.txt → Task 4 Step 1 + Task 5 Step 1.
- Pre-checks → Task 2 Step 1.
- Failure & idempotency rules → Task 5 Step 1 (skip-if-exists, fail-and-continue) + Task 6 Step 1 (errors catalog).
- Final report format → Task 5 Step 1.
- Anti-patterns → Task 6 Step 1.
- Open questions → not an implementation requirement; tracked in spec.

**Placeholder scan:** No "TBD"/"TODO"/"implement later" in the plan. Code samples in tasks are full markdown blocks ready to paste. Expected outputs and exact commands stated.

**Type/name consistency:**
- `is_anchor`, `products_detected[N]`, `seedance_asset_id`, `hero_image`, `size_reference[slug]` used consistently across Tasks 2-5.
- `frames/segment_<N>/video_prompt.txt`, `frames/segment_1/first_frame.png`, `frames/segment_1/first_frame_face_mask.png`, `videos/segment_<N>_final.mp4` paths consistent.
- Bash variable names `images`, `seedance_asset_id`, `N` consistent in all snippets.

No fixes needed.
