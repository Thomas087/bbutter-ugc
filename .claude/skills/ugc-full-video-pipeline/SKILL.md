---
name: ugc-full-video-pipeline
description: >-
  Pipeline complet de génération vidéo UGC Butt Butter à partir d'un script déjà voicé en lo-fi (sortie de `ugc-voice-lofi`). Orchestration séquentielle, segment par segment, via `scripts/generate_video_seedance.py` : génère segment 1 (le plan ancre 1 seed) avec character asset + audio lo-fi (auto-attaché) + packshot/size-ref des produits détectés, extrait le face-mask 1 depuis sa première frame via ffmpeg + `scripts/generate_image.sh --ref`, puis génère les segments 2..N en attachant le face-mask 1 aux segments `Plan ancre 1` et le packshot + référence taille pour chaque produit cité. Supporte un **second plan ancre optionnel** (`Plan ancre 2`, environnement différent) : son segment seed est généré sans face-mask (nouveau cadre), puis le face-mask 2 est extrait via la même procédure ffmpeg + ChatGPT et attaché aux segments `Plan ancre 2` suivants. Détection des produits par keyword match sur le catalogue (`brand/products/catalog.yaml` + fichiers `<slug>.md`). Détection des plans ancre par parsing des directives scène `Plan ancre`, `Plan ancre 1`, `Plan ancre 2` dans le `script.md`. Match persona → character asset via `scripts/characters.json` (genre strict, âge le plus proche). Termine automatiquement par un passage `ugc-deai` (Étape 7 — texture micro-blur + grain + correction colorimétrique gamma per-channel pour matcher chaque segment N>1 sur les moyennes RGB du segment 1) et un `ugc-concat` (Étape 8 — concat demuxer ffmpeg `-c copy` avec fallback re-encode libx264+aac si codecs mismatch), produisant `<session>/final.mp4` prêt à publier. Utilise ce skill dès que l'utilisateur demande "génère toute la vidéo", "pipeline complet vidéo", "vidéo UGC complète", "lance la génération vidéo de bout en bout", "génère tous les segments", "vidéo UGC du script avec face-mask", "génère le clip complet", ou veut produire la vidéo intégrale d'un script Butt Butter une fois la voix lo-fi prête. Utilise-le aussi quand l'utilisateur veut régénérer plusieurs segments à la suite ou enchaîner segment 1 → face mask → segments 2..N sans repasser par les skills atomiques `ugc-video-seedance` et `ugc-face-mask-extractor` un par un.
---

# UGC Full Video Pipeline — Butt Butter

Ce skill orchestre la génération vidéo UGC complète d'un script Butt Butter déjà voicé en lo-fi. Il prend en entrée un dossier de session contenant `script.md` + `voice_sections_1.2x_lofi/section-NN.mp3` (sortie de `ugc-voice-lofi`) et produit `videos/segment_<N>_final.mp4` pour chaque segment du script, dans l'ordre.

Pipeline en 6 étapes, séquentielles, **jamais en parallèle** : parse → persona → alias produits → segment 1 (seed ancre 1) → face-mask 1 → segments 2..N. Le face-mask extrait du premier frame du segment 1 sert d'image de référence aux segments `Plan ancre 1` suivants pour figer la posture corps + décor + téléphone tout en laissant Seedance re-générer le visage proprement depuis le character asset.

**Second plan ancre (optionnel).** Si le script contient au moins un segment marqué `Plan ancre 2` (environnement différent de l'ancre 1, typiquement vers la fin de la vidéo), le pipeline répète la sous-routine face-mask : son premier segment (le "seed ancre 2") est généré **sans** face-mask attaché (c'est un nouveau cadre, on veut que Seedance compose librement le nouvel environnement), puis ffmpeg extrait sa première frame et `generate_image.sh --ref` produit `face_mask_2` à partir de cette frame. Les segments `Plan ancre 2` suivants reçoivent ce nouveau face-mask en référence. Les deux face-mask coexistent : ancre 1 → face-mask 1, ancre 2 → face-mask 2, inserts → aucun face-mask. Au maximum **un seul second plan ancre** par script (pas de `Plan ancre 3`).

Ce skill remplace le loop manuel `ugc-video-seedance` → `ugc-face-mask-extractor` → `ugc-video-seedance` × (N-1). Il consomme en aval de `ugc-script-writer` → `ugc-voice-generator` → `ugc-voice-lofi`.

> **Pré-requis dur** : le dossier session DOIT contenir `script.md` ET `voice_sections_1.2x_lofi/section-NN.mp3` pour chaque N ciblé. Si la lo-fi manque, **stoppe** et pointe vers `ugc-voice-lofi`. Pas d'auto-recovery — c'est un pipeline aval, pas un orchestrateur global.

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
3. `<session_dir>/voice_sections/section-<NN>.mp3` existe pour chaque N ciblé (utilisé par `generate_video_seedance.py` pour calculer la durée Seedance, basée sur la voix non-accélérée + 1 s).
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

Ensuite, pour chaque segment, calcule trois flags :

- **`anchor_group`** : `1`, `2`, ou `None`. Logique de détection (ordre obligatoire) :
   1. Si `stage_direction.lower()` contient le substring `plan ancre 2` → `anchor_group = 2`.
   2. Sinon si `stage_direction.lower()` contient le substring `plan ancre` (avec ou sans `1`) → `anchor_group = 1`.
   3. Sinon → `anchor_group = None` (insert / B-roll).

  **Tester `plan ancre 2` AVANT `plan ancre`**, sinon `plan ancre 2` serait mal classé en groupe 1 (le substring `plan ancre` matche les deux).

- **`is_anchor`** : raccourci, équivaut à `anchor_group is not None`. Utilisé tel quel par le template de prompt — les deux groupes d'ancres partagent le même template ancre (selfie front-camera + cadence `[Audio 1]`), voir Étape 5.1.

- **`products_detected`** : liste des slugs catalogue dont au moins un alias keyword apparaît dans `(voice_text + insert_annotations)`.lower(). Voir l'alias map à l'Étape 2. **Le `on_screen_text` est volontairement exclu** — il contient typiquement un CTA / overlay brand chip (ex : `Butt Butter — La Crème Apaisante`) qui mentionne le produit sans qu'il soit visuellement dans le plan. Inclure le on-screen-text produirait des faux positifs (packshot attaché à un selfie où le tube n'apparaît pas).

Identifie ensuite, sur l'ensemble du script, les deux **seed segments** :

- **`seed_segment[1]`** : toujours `1` (le segment ancre 1 est par convention le premier segment du script ; un script bien formé démarre obligatoirement sur un `Plan ancre` / `Plan ancre 1`).
- **`seed_segment[2]`** : index 1-based du **premier** segment avec `anchor_group == 2`, ou `None` si aucun segment du script n'est marqué `Plan ancre 2`. C'est ce segment qui sera généré sans face-mask et dont sera ensuite extrait le face-mask 2.

Validation : si `anchor_group[1] != 1` (le segment 1 n'est pas marqué comme plan ancre), stoppe avec un message d'erreur — le script doit obligatoirement démarrer sur un plan ancre 1. Si un segment a `anchor_group == 2` mais qu'aucun segment précédent n'a `anchor_group == 1`, c'est aussi une erreur (un Plan ancre 2 sans Plan ancre 1 amont n'a pas de sens).

Récupère également l'en-tête du script pour la persona (ligne `**Persona :**`) et le décor (souvent dans la même ligne, ex : `Tournage dans une salle de bain classique`).

> **Pourquoi ne pas utiliser un parser regex strict** : les en-têtes peuvent varier légèrement (`—` vs `-`, espaces, accents). Utilise un parser tolérant (regex permissif sur `**\[\d+:\d+`) et vérifie en sortie que le nombre de segments parsés correspond au nombre de fichiers `voice_sections_1.2x/section-NN.mp3`. Si mismatch, stoppe et pointe l'incohérence.

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

Pour chaque segment, le set des produits détectés est l'union de tous les slugs dont au moins un keyword apparaît dans `(voice_text + insert_annotations)` (toujours en lower-case). Le `on_screen_text` est exclu — voir Étape 0 pour la justification.

**Faux positifs acceptés** : un keyword "métaphorique" qui matche n'est pas grave — une référence image en plus ralentit Seedance d'~0 ms et n'altère pas la sortie. Un faux négatif (produit cité mais non détecté) casse la fidélité du packaging à l'écran. Donc on biaise vers la sur-détection.

> Si l'utilisateur ajoute un nouveau produit au catalogue, il doit aussi ajouter sa ligne à cette table. C'est volontairement statique pour rester explicite (pas d'embeddings ni d'extraction LLM à chaque run).

## Étape 3 — Générer le segment 1 (le seed du plan ancre)

Le segment 1 est toujours généré **en premier** et **sans face-mask** : c'est lui qui sert de seed pour fabriquer le face-mask utilisé par les segments suivants. Procédure :

### 3.1 — Écrire `frames/segment_1/video_prompt.txt`

```bash
mkdir -p "<session_dir>/frames/segment_1"
```

Le prompt suit le template documenté dans `.claude/skills/ugc-video-seedance/SKILL.md` (section "Écriture du video_prompt.txt"). Récapitule ici les pièces non-négociables :

- **Description du personnage** : recopie tels quels les détails de l'en-tête `**Persona :**` du script (âge, look, tenue, cheveux, décor). Pas de paraphrase.
- **Plan caméra ancre** : `iPhone front-camera selfie clip — the viewer IS the iPhone's front camera, this is the raw front-camera feed`, `vertical 9:16 frame`, `fixed framing`.
- **POV front-camera (bloc complet, obligatoire pour tout segment ancre)** : recopie tel quel le bloc défini dans `.claude/skills/ugc-video-seedance/SKILL.md`, section "POV front-camera (obligatoire, bloc complet, non négociable)". C'est le bloc qui interdit explicitement (a) le téléphone visible dans le cadre (dos d'iPhone, logo Apple, bumps caméra, bezel, main-tenant-un-téléphone), (b) le mirror-selfie / la réflexion dans un miroir, (c) le cadrage 3e personne. **Sans ce bloc, Seedance retombe par défaut sur un cadrage 3e personne ou mirror-selfie** (précédent : segment 1 du `output/2026-05-12-le-mot-interdit/`, dos d'iPhone visible). Adapte uniquement les pronoms du personnage (his/her).
- **Stage direction téléphone (une phrase complémentaire au bloc POV)** : ajoute **une seule phrase courte en anglais** qui précise uniquement la **main + l'angle**, sans répéter "holding the phone" (cette formulation est piégée). Exemples — pioche dans cette liste :
  - Plan ancre selfie main gauche : `Camera angle suggests the phone is held by the creator's left hand at arm's length, slight upward angle toward the face. Hand and phone body remain off-frame.`
  - Plan ancre selfie main droite : `Camera angle suggests the phone is held by the creator's right hand at arm's length, slight downward angle. Hand and phone body remain off-frame.`
  - Plan ancre posé / à distance : `Phone is set on a stable surface about 1 meter away from the creator, at chest height. Not selfie mode. The shot is wider — head and shoulders visible.`
  Détail volontairement minimal — pas de paragraphe, pas de description de la pièce ici. La phrase couvre uniquement : main + angle, ou distance si plan posé. Voir `.claude/skills/ugc-video-seedance/SKILL.md` pour la liste complète des variantes et le bloc POV non négociable.
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

## Étape 4 — Sous-routine "extract face-mask" depuis un seed ancre

Cette étape est une **sous-routine paramétrable** appelée au moins une fois (après le segment 1, pour le face-mask 1) et potentiellement une seconde fois pendant l'Étape 5 (juste après la génération du `seed_segment[2]`, pour le face-mask 2 — voir Étape 5.6).

Paramètre d'entrée : un **seed segment index** `S` (= `1` pour le face-mask 1, = `seed_segment[2]` pour le face-mask 2). Toutes les sous-étapes 4.1 → 4.4 ci-dessous opèrent sur `<session_dir>/frames/segment_<S>/`, pas seulement `segment_1`.

Sortie : `<session_dir>/frames/segment_<S>/first_frame_face_mask.png`, prêt à servir de référence aux segments suivants du même groupe d'ancre.

### 4.1 — Première frame via ffmpeg

```bash
mkdir -p "<session_dir>/frames/segment_<S>"

ffmpeg -y -i "<session_dir>/videos/segment_<S>_final.mp4" \
  -vframes 1 -update 1 -q:v 2 \
  "<session_dir>/frames/segment_<S>/first_frame.png"
```

`-update 1` silence le warning "filename does not contain an image sequence pattern". `-q:v 2` quasi-lossless. `-vframes 1` strictement la frame 0.

### 4.2 — Construire le prompt face-mask

Réutilise le template documenté dans `.claude/skills/ugc-face-mask-extractor/SKILL.md` (section "Construire le prompt de face-mask"). Récap des blocs non-négociables :

- **Bloc forme opaque** : `paint a single opaque flat oval of solid neutral light grey completely covering the {{persona courte — ex: man's}} face. The shape must be: large enough to cover from forehead to chin and from ear to ear, fully opaque, smooth-edged, no transparency, no gradient, no texture, no features, no eyes, no mouth, no nose, no shadows, no highlights — a clean flat blocking shape sitting on top of the face area like a censorship sticker.`
- **Bloc EVERYTHING else IDENTICAL** (reprend la formulation exacte de `.claude/skills/ugc-face-mask-extractor/SKILL.md` lignes 64-66) — non négociable, sinon le décor dérive.
- **Bloc no transparency, no gradient** — non négociable, sinon le visage transparaît.
- **Bloc Photoreal everywhere except the shape itself + iPhone front-camera look + anti-watermark.**

Récupère les détails persona/décor :

- En priorité depuis `<session_dir>/frames/segment_<S>/video_prompt.txt` (vient d'être écrit à l'Étape 3.1 pour `S=1`, ou à l'Étape 5.1 pour `S=seed_segment[2]`). Pour le face-mask 2, c'est important : le video_prompt du seed ancre 2 décrit le **nouvel environnement**, donc le prompt face-mask doit s'appuyer sur ce nouveau décor (pas sur celui du segment 1).
- Sinon depuis l'en-tête `**Persona :**` du `script.md` (persona identique pour les deux groupes d'ancres, seul le décor change).

Aspect ratio : déduis-le des dimensions du PNG via `sips -g pixelWidth -g pixelHeight "<session_dir>/frames/segment_<S>/first_frame.png"`. Si le ratio est ≈9:16, écris `vertical 9:16` dans le prompt.

Sauvegarde le prompt dans `<session_dir>/frames/segment_<S>/face_mask_prompt.txt` avant l'appel API (permet d'itérer sans re-rédiger).

### 4.3 — Appel `generate_image.sh --ref`

```bash
set -a; source .env; set +a

OPENAI_IMAGE_QUALITY=high \
  ./scripts/generate_image.sh \
    --ref "<session_dir>/frames/segment_<S>/first_frame.png" \
    "<session_dir>/frames/segment_<S>/first_frame_face_mask.png" \
    "$(cat "<session_dir>/frames/segment_<S>/face_mask_prompt.txt")" \
    1024x1536
```

`OPENAI_IMAGE_QUALITY=high` est obligatoire (memory utilisateur). En `low` le bord de la forme est crénelé et le décor est reconstruit flou.

Pour un script vertical 9:16, `1024x1536` est la bonne taille (sortie cropée à 864x1536 par défaut). Pour landscape passe `1536x1024 --no-crop`.

### 4.4 — Vérification visuelle rapide

Après la génération, ouvre/affiche les deux PNGs (`first_frame.png` et `first_frame_face_mask.png` du dossier `segment_<S>`) inline pour que l'utilisateur puisse comparer. Si le masque déborde sur le cou/téléphone, ou si le décor a visiblement bougé, **signale-le** dans le rapport final et propose un re-tirage. Ne re-tire pas automatiquement — la variance API a un coût et l'utilisateur doit valider.

Quand la sous-routine est appelée pour le face-mask 2, vérifie en plus que le **décor est bien distinct** de celui du face-mask 1 (le seed ancre 2 doit avoir composé un nouvel environnement). Si le décor du seed ancre 2 ressemble visiblement à celui de l'ancre 1, signale-le : c'est souvent symptôme d'une description trop vague dans le `Plan ancre 2` du script ou d'un prompt Étape 5.1 qui n'a pas assez insisté sur le nouvel environnement.

> Cas de fallback **gpt-image-2 → gpt-image-1** : `generate_image.sh` retombe automatiquement sur `gpt-image-1` si le compte OpenAI n'est pas vérifié pour `gpt-image-2`. La précision du masque est plus basse mais utilisable. Mentionne le fallback une fois dans le rapport final si déclenché.

## Étape 5 — Générer les segments 2..N (séquentiel)

Boucle séquentielle, **jamais en parallèle**. L'utilisateur veut pouvoir inspecter la lipsync de chaque plan avant de payer le suivant.

Pour chaque segment N ≥ 2 (dans l'ordre du script, sauf si `--segments` filtre) :

### 5.1 — Décider du template de prompt selon `anchor_group`

- **Si `anchor_group == 1`** : utilise le template "plan ancre" décrit à l'Étape 3.1 (selfie front-camera + cadence `[Audio 1]` + phrase française exacte + tag ElevenLabs). Reprend le décor du segment 1.
- **Si `anchor_group == 2`** : même template ancre que ci-dessus (selfie front-camera + cadence + phrase exacte), **mais le décor doit être celui décrit dans la stage direction `Plan ancre 2`**, pas celui du segment 1. Recopie la description d'environnement de la stage direction `*Plan ancre 2 : ...*` dans le prompt. Pour le **seed ancre 2** (`N == seed_segment[2]`), insiste explicitement dans le prompt sur le changement d'environnement (ex : « now in the kitchen, matte countertop background, daylight from the side » plutôt que « bathroom »). Le seed ancre 2 ne reçoit pas de face-mask (voir 5.2), c'est la description écrite du prompt qui doit porter à elle seule le nouvel environnement.
- **Si `anchor_group is None`** (insert/B-roll, ex : `*Insert : gros plan tube en main.*`) : utilise un template close-up :

  ```
  Macro/close-up shot of {{description du sujet — ex: a hand holding the
  Butt Butter cream tube}}. Photoreal, soft natural daylight, shallow
  depth of field, iPhone rear-camera UGC look. Stable framing — no zoom,
  no pan. The product packaging is clearly readable. No on-screen text,
  no captions, no watermarks.
  ```

  Pas de cadence `[Audio 1]` pour les inserts (pas de lipsync à driver). Pas de phrase française exacte non plus (l'insert est silencieux côté image). L'audio lo-fi est **quand même** attaché — Seedance utilise sa durée pour caler la durée vidéo, et la voix de fond reste cohérente avec le segment.

  Ajoute aussi pour l'insert **une phrase de stage direction téléphone minimale**, comme pour les plans ancre. Pour un insert macro produit, typique : `This insert is shot with the iPhone's rear camera, held in one hand close to the product. Not a selfie shot. The creator's face is NOT in this frame.` Pas plus — la phrase suffit à empêcher Seedance de retomber par défaut sur un cadrage selfie hérité du segment précédent. Pour les inserts, le bloc "POV front-camera" complet des segments ancre **ne s'applique pas** (l'insert est, par définition, en rear-camera et le téléphone n'est de toute façon pas censé apparaître dans le cadre macro).

Écris le prompt dans `<session_dir>/frames/segment_<N>/video_prompt.txt` avant l'appel.

### 5.2 — Construire la liste `--image`

Ordre :

1. **Sélection du face-mask** (dépend de `anchor_group[N]` et de la position vis-à-vis des seeds) :

   - **Si `anchor_group[N] == 1` ET `N ≥ 2`** : ajoute le face-mask 1

     ```
     <session_dir>/frames/segment_1/first_frame_face_mask.png
     ```

   - **Si `anchor_group[N] == 2` ET `N == seed_segment[2]`** (= le seed ancre 2 lui-même) : **aucun face-mask attaché**. C'est volontaire — le seed ancre 2 doit composer librement le nouvel environnement à partir du prompt (Étape 5.1) et du character asset. Le face-mask 1 aurait verrouillé l'ancien décor (salle de bain) ; on veut justement que Seedance ouvre un nouveau cadre.

   - **Si `anchor_group[N] == 2` ET `N > seed_segment[2]`** (= un segment ancre 2 postérieur au seed) : ajoute le face-mask 2

     ```
     <session_dir>/frames/segment_<seed_segment[2]>/first_frame_face_mask.png
     ```

     **Pré-requis** : ce fichier doit exister, ce qui implique que la sous-routine face-mask de l'Étape 5.6 a déjà tourné après le seed ancre 2. Si le fichier manque, log un warning et tombe sur "aucun face-mask attaché" (le segment perdra en cohérence de décor mais ne stoppera pas le pipeline).

   - **Si `anchor_group[N] is None`** (insert) : aucun face-mask attaché. Les inserts sont des close-ups silencieux, le face-mask casserait le cadrage.

   `generate_video_seedance.py` détecte que le chemin est local et le passe à `storage.sh` pour l'uploader sur Cellar avant l'appel API.

2. **Pour chaque slug dans `products_detected[N]`** :
   - `catalog[slug]["hero_image"]` (https Shopify, passthrough)
   - `size_reference[slug]` si non-`None` (https Shopify, passthrough)

Si la liste est vide (segment ancre sans produit + seed ancre 2 sans produit), c'est valide — on appelle Seedance avec character asset + audio lo-fi seuls.

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

### 5.6 — Si N était le seed ancre 2 : extraire le face-mask 2 (inline)

Juste après que la génération du segment `N` ait abouti avec succès (mp4 produit, pas en `failed`), vérifie : `anchor_group[N] == 2 ET N == seed_segment[2]` ? Si oui, **appelle la sous-routine de l'Étape 4** avec `S = N` (paramètre `seed segment index`). Concrètement :

1. ffmpeg extrait `<session_dir>/frames/segment_<N>/first_frame.png` (Étape 4.1).
2. Construit `<session_dir>/frames/segment_<N>/face_mask_prompt.txt` en récupérant les détails persona/décor depuis `<session_dir>/frames/segment_<N>/video_prompt.txt` — **insiste sur le nouvel environnement décrit dans `Plan ancre 2`**, pas celui de l'ancre 1 (Étape 4.2).
3. Appelle `generate_image.sh --ref` pour produire `<session_dir>/frames/segment_<N>/first_frame_face_mask.png` (Étape 4.3).
4. Vérification visuelle (Étape 4.4), avec contrôle additionnel : le décor du face-mask 2 doit être visiblement distinct de celui du face-mask 1.

**Cette extraction doit terminer AVANT de lancer le segment N+1** s'il y en a un dans le même groupe ancre 2 — le segment N+1 a besoin du `first_frame_face_mask.png` du seed ancre 2 dans son `--image`. Le pipeline reste donc strictement séquentiel : pas de génération de `segment_N+1` en parallèle de l'extraction du face-mask 2.

Si l'extraction face-mask 2 échoue (par exemple gpt-image-2 + fallback gpt-image-1 tous deux KO), log un warning et continue : les segments ancre 2 suivants utiliseront la sortie de Seedance "à nu" (character asset + prompt seuls), avec un risque de dérive de décor entre eux. Le rapport final mentionnera cet échec.

Si `anchor_group[N] != 2` OU `N != seed_segment[2]` (cas le plus courant — pas de second plan ancre dans le script, ou segment N est juste un segment ancre 1 / insert), ne fais rien ici, continue directement à `N+1`.

## Étape 6 — Rapport final à l'utilisateur

Après la dernière itération, affiche un bloc compact, **sans commentaire** sur les étapes qui ont marché. Format :

```
Personnage Seedance : <id> (asset <seedance_asset_id>) — persona <résumé>.
Face-mask 1 (anchor 1) : <session_dir>/frames/segment_1/first_frame_face_mask.png[, gpt-image-1 fallback]
Face-mask 2 (anchor 2, seed = segment <K>) : <session_dir>/frames/segment_<K>/first_frame_face_mask.png[, gpt-image-1 fallback]

segment 1 — anchor=1 — products=[]                 — videos/segment_1_final.mp4 (5.0s, 1.3 MB) [seed anchor 1]
segment 2 — anchor=1 — products=[]                 — videos/segment_2_final.mp4 (5.0s, 1.4 MB) [face mask 1 attached]
segment 3 — anchor=N — products=[creme-apaisante]  — videos/segment_3_final.mp4 (4.0s, 1.1 MB) [insert, packshot + size ref]
segment 4 — anchor=1 — products=[]                 — videos/segment_4_final.mp4 (5.0s, 1.3 MB) [face mask 1 attached]
segment 5 — anchor=2 — products=[]                 — videos/segment_5_final.mp4 (5.0s, 1.4 MB) [seed anchor 2 — no face mask, face mask 2 extracted after]
segment 6 — anchor=2 — products=[]                 — videos/segment_6_final.mp4 (5.0s, 1.3 MB) [face mask 2 attached]
```

(Pas de ligne « Suite » ici — les Étapes 7 et 8 enchaînent automatiquement le de-AI puis le concat.)

Si le script ne contient pas de `Plan ancre 2` (cas le plus courant), omets la ligne `Face-mask 2 ...` et la colonne `anchor=` ne prend que les valeurs `1` ou `N`.

Récupère durée + taille via `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 <mp4>` et `ls -lh <mp4>`. Si un segment a échoué, remplace la ligne par :

```
segment 4 — FAILED — <message Ark résumé>
```

Pas de commentaire gratuit ("génération réussie", "fichiers écrits"). Seulement ce qui est notable ou cassé.

## Étape 7 — De-AI + harmonisation colorimétrique (automatique)

Dernière étape **toujours déclenchée** une fois que ≥ 2 segments ont été générés avec succès (au moins le segment 1 + un autre). Délègue intégralement à `ugc-deai` — ne pas inliner la chaîne de filtres ici.

Pourquoi cette étape est obligatoire : Seedance sort des plans techniquement propres mais qui trahissent l'IA (edges pixel-perfect, vibrance lift, dérive colorimétrique segment à segment — typiquement +10 sur R aux segments 2+). Sans ce passage final, le concat final mélange un plan "réel" (segment 1) et N-1 plans "AI-crisp" → l'œil détecte immédiatement la rupture. Le filtre `ugc-deai` casse cette rupture en deux temps : texture (micro-blur + grain) sur tous les segments + correction colorimétrique per-channel sur les segments 2..N pour matcher la mean RGB du segment 1.

### 7.1 — Déclenchement

Juste après le bloc de rapport de l'Étape 6, lance :

```bash
./scripts/deai_videos.sh --in "<session_dir>"
```

Pas d'options. Le script auto-détecte tous les `videos/segment_<N>_final.mp4`, prend le segment 1 comme référence, et traite tout le reste.

**Cas où on saute l'Étape 7** :

- Un seul segment a été produit avec succès (rien à harmoniser).
- L'utilisateur a passé `--no-deai` à `ugc-full-video-pipeline` (override explicite — voir Override courants).
- Tous les segments demandés ont été skipped (déjà existants sans `--force`) → rien de neuf à de-AI'er, mais il faut quand même lancer pour les segments précédemment générés sans de-AI. **Cas limite à arbitrer** : si l'utilisateur re-lance le pipeline pour ajouter 1 segment manquant, lancer `ugc-deai` traitera juste ce nouveau segment (les autres sont skipped par idempotence). C'est le comportement souhaité.

### 7.2 — Layout résultant

```
<session_dir>/videos/
├── segment_1_final.mp4          ← de-AI'd (texture seulement)
├── segment_2_final.mp4          ← de-AI'd + color matched
├── ...
└── raw/
    └── segment_<N>_final.mp4    ← originaux Seedance préservés
```

Le `videos/raw/` contient les sorties brutes Seedance, jamais touchées par `ugc-deai`. C'est le filet de sécurité pour comparer / restaurer un segment / re-tirer la chaîne de filtres en cas de tuning ultérieur.

### 7.3 — Sortie attendue

Relayer en 1-2 lignes après le rapport de l'Étape 6 :

```
De-AI + color match : N segment(s) traité(s) (originaux dans videos/raw/).
Delta colorimétrique max : segment <K> (gamma_r=0.92, gamma_g=0.99).
```

Le "delta max" se lit dans les logs de `deai_videos.sh` (ligne `[segment <N>] raw RGB=… → gamma_r=… gamma_g=…`). Ne pas re-coller les RGB de chaque segment — l'utilisateur ne lit pas ça pour 5 lignes. Juste le pire offender pour signaler "voilà le plus déviant si tu veux contrôler visuellement".

L'Étape 8 (concat) enchaîne juste après — pas d'attente utilisateur.

## Étape 8 — Concat final (automatique)

Dernière étape **toujours déclenchée** une fois que ≥ 2 segments de-AI'd existent au canonical `videos/segment_<N>_final.mp4` (i.e. l'Étape 7 a tourné avec succès sur au moins 2 segments). Délègue intégralement à `ugc-concat` — la procédure complète (tri version-aware, concat list, fallback re-encode, faststart, gestion d'erreurs) est documentée là-bas et ne doit **pas** être ré-inlinée ici. Cette étape se contente d'invoquer le skill aval avec la bonne session.

Pourquoi cette étape est obligatoire : sans le concat, le pipeline laisse l'utilisateur devant N fichiers `segment_<N>_final.mp4` séparés. Le format de publication (TikTok / Reels / Shorts) attend un seul mp4. Faire le concat dans la foulée du de-AI évite (a) un context-switch pour l'utilisateur et (b) un oubli qui produirait `final.mp4` non-déyé.

### 8.1 — Déclenchement

Juste après l'Étape 7, invoque le skill `ugc-concat` sur la même session :

```bash
SESSION="<session_dir>"

# 1. Lister les segments de-AI'd au canonical, triés numériquement.
shopt -s nullglob
SEGMENTS=()
while IFS= read -r f; do SEGMENTS+=("$f"); done < <(
  ls "$SESSION/videos"/segment_*_final.mp4 2>/dev/null | sort -V
)

# 2. Pré-requis : ≥ 2 segments (sinon skip silencieux).
if [[ ${#SEGMENTS[@]} -lt 2 ]]; then
  echo "Skip concat: only ${#SEGMENTS[@]} segment(s) found." >&2
  exit 0
fi

# 3. Concat list temporaire (chemins absolus + -safe 0).
LIST="$SESSION/.concat_list.txt"
: > "$LIST"
for f in "${SEGMENTS[@]}"; do
  printf "file '%s'\n" "$f" >> "$LIST"
done

# 4. Concat copy (instantané, lossless). Fallback re-encode si échec.
OUT="$SESSION/final.mp4"
if ! ffmpeg -y -hide_banner -loglevel error \
      -f concat -safe 0 -i "$LIST" \
      -c copy -movflags +faststart \
      "$OUT"; then
  echo "Concat copy failed — falling back to libx264 + aac re-encode." >&2
  ffmpeg -y -hide_banner -loglevel error \
    -f concat -safe 0 -i "$LIST" \
    -c:v libx264 -preset medium -crf 18 \
    -c:a aac -b:a 192k \
    -movflags +faststart \
    "$OUT"
fi

rm -f "$LIST"
```

Pour les overrides (`--segments` partiel, `--output` custom, forçage re-encode), pointer l'utilisateur vers `ugc-concat` directement — pas la peine de relayer ces options à travers le pipeline complet.

### 8.2 — Cas où on saute l'Étape 8

- Un seul segment au canonical (rien à concat-er).
- L'utilisateur a passé `--no-concat` à `ugc-full-video-pipeline` (override explicite — voir Override courants).
- L'Étape 7 a échoué pour tous les segments (= aucun mp4 au canonical). Ne pas concat-er des `videos/raw/segment_<N>_final.mp4` à la place — c'est un pipeline aval qui doit lire les versions de-AI'd. Si l'Étape 7 plante, signaler et stopper.

### 8.3 — Sortie attendue

Une ligne après le bloc de l'Étape 7 :

```
Vidéo finale : <session>/final.mp4 (35.0s, 6.8 MB) — concat sans ré-encodage.
```

Format identique à celui du skill `ugc-concat`. Si le fallback re-encode a été déclenché, mentionne brièvement la cause :

```
Vidéo finale : <session>/final.mp4 (35.0s, 9.2 MB) — re-encoded (libx264 crf 18 + aac 192k). Cause : segment 3 timebase mismatch.
```

C'est la dernière ligne du pipeline. Pas de "vidéo prête", pas de "tu peux uploader" — implicite.

## Override courants (suite — propres aux Étapes 7 et 8)

- **Désactiver le de-AI sur une session** : passer `--no-deai` à `ugc-full-video-pipeline`. Utile pour debug visuel pur du Seedance raw, ou si la session a été générée avec un look déjà voulu (rare). Le concat (Étape 8) tourne quand même sur les segments raw.
- **Désactiver le concat** : passer `--no-concat` à `ugc-full-video-pipeline`. Utile si l'utilisateur veut inspecter chaque segment individuellement avant l'assemblage, ou s'il a besoin d'un montage manuel dans un éditeur en post.
- **Désactiver les deux** (sortie segments raw Seedance, pas de concat) : `--no-deai --no-concat`. Équivaut à l'ancien comportement avant que les Étapes 7-8 soient ajoutées au pipeline.
- **Re-lancer le de-AI seul** après régénération d'un segment : commencer par **supprimer le raw périmé** (`rm <session>/videos/raw/segment_<N>_final.mp4`), sinon `deai_videos.sh` lit l'ancien raw et ignore silencieusement la nouvelle génération. Une fois le raw effacé : `./scripts/deai_videos.sh --in <session> --segments <N>` (pas besoin de `--force` puisque le raw a disparu, le script traite ce N comme un premier run). Ne touche pas les autres segments. Re-lancer ensuite `ugc-concat` à la main pour refaire `final.mp4`. Détails complets dans `ugc-deai` → section "Idempotence et re-runs".
- **Re-concat seul** (ex : après avoir restauré un segment depuis `videos/raw/`) : invoquer `ugc-concat` directement sur la session. Pas besoin de re-passer par le pipeline complet.
- **Tuner les paramètres** (saturation, grain strength, unsharp) : modifier directement `scripts/deai_videos.sh`. C'est volontairement figé dans le script — pas exposé en CLI pour éviter le tuning par projet qui dériverait sans justification.

## Override courants

- **Régénérer un seul segment** : `--segments 3` + `--force`. Réutilise le face-mask déjà extrait pour son groupe ancre (face-mask 1 pour les segments `anchor_group == 1`, face-mask 2 pour les segments `anchor_group == 2 ET N > seed_segment[2]`). Si l'utilisateur demande à re-tirer le face-mask, voir l'override suivant.
- **Re-tirer juste un face-mask** (variance API) : choisis `S = 1` pour le face-mask 1, `S = seed_segment[2]` pour le face-mask 2. Si `frames/segment_<S>/first_frame.png` existe déjà, saute l'Étape 4.1 (extraction ffmpeg) et passe directement à l'Étape 4.3 (appel API). Le PNG `first_frame_face_mask.png` du dossier `segment_<S>` est écrasé. Coût : ~30s par face-mask.
- **Forcer un personnage non-catalogue** : si l'utilisateur passe un `seedance_asset_id` explicite (test d'un nouvel asset BytePlus pas encore inscrit dans `characters.json`), saute l'Étape 1 et utilise l'asset fourni.
- **Variante silencieuse** d'un segment (debug A/B) : passer `--no-generate-audio` à `generate_video_seedance.py`. Pas un mode officiel du skill, à invoquer manuellement.
- **Segment-only** sans face-mask (test prompt seul) : invoquer directement `ugc-video-seedance` sur ce segment, ne pas passer par ce skill.

## Anti-patterns à éviter

- **Générer les segments en parallèle.** Le pipeline est séquentiel par design : segment 1 doit finir avant le face-mask, et même les segments 2..N restent séquentiels. Ça permet à l'utilisateur d'inspecter chaque lipsync avant de payer le suivant, et ça garde la queue Ark calme. **Pas de `&` ni de `xargs -P` derrière les appels Seedance.**
- **Réutiliser le face-mask avant qu'il existe.** Segment 1 → face-mask → segments 2..N. Ne tente jamais de lancer le segment 2 en parallèle de l'extraction face-mask.
- **Attacher le face-mask à un segment insert (non-ancre).** Tue le cadrage close-up que l'insert est censé livrer. Le flag `anchor_group` se vérifie segment par segment (`None` → pas de face-mask), pas une fois pour toutes.
- **Attacher le face-mask 1 à un segment `Plan ancre 2`.** Verrouille l'ancien décor (typiquement la salle de bain) sur ce qui était censé être un nouvel environnement → le `Plan ancre 2` perd son intérêt. Le mapping est strict : `anchor_group == 1` → face-mask 1, `anchor_group == 2 ET N > seed_segment[2]` → face-mask 2, `anchor_group == 2 ET N == seed_segment[2]` → aucun face-mask.
- **Sauter l'extraction face-mask 2 ("le décor est presque le même, ça ira").** Sans face-mask 2, les segments ancre 2 postérieurs au seed dérivent un peu à chaque génération (lumière, posture, cadrage). Pour 2+ segments dans le groupe ancre 2, le face-mask 2 est obligatoire.
- **Décrire un environnement trop proche de l'ancre 1 dans `Plan ancre 2`.** Si le script écrit `Plan ancre 2 : salle de bain, fond mat` alors que le `Plan ancre 1` était déjà dans la salle de bain, la créatrice "change de salle de bain" en plein milieu de la vidéo — incohérence immédiate. Le `Plan ancre 2` doit décrire une **pièce franchement distincte** (cuisine, salon, bureau, voiture, extérieur). Si la stage direction du script est ambiguë, signale-le à l'utilisateur avant de lancer le pipeline.
- **Sauter le `video_prompt.txt` par segment.** Un prompt générique entre segments produit une dérive visible (cadrage, lumière, ton). Chaque segment a son propre prompt, ancré sur sa stage direction et son texte voix.
- **Défaut sur un personnage approchant.** Si `characters.json` n'a pas de match strict (genre + âge proche), **stoppe**. Ne prends pas le moins pire — la cohérence visuelle entre plans repose sur le match.
- **Auto-lancer les skills amont.** Ce skill suppose script + lo-fi déjà produits. Ne lance jamais `ugc-script-writer`, `ugc-voice-generator` ou `ugc-voice-lofi` toi-même. Stoppe et pointe.
- **Passer `--audio` manuellement** depuis le skill. `generate_video_seedance.py` auto-attache `voice_sections_1.2x_lofi/section-NN.mp3`. Le passer à la main risque de pointer vers le mauvais fichier (ex : `voice_sections/` non-accéléré, ou `voice_sections_1.2x/` non-lo-fi).
- **Sauter le bloc "POV front-camera" dans le prompt d'un segment ancre.** Sans ce bloc explicite, Seedance retombe par défaut sur un cadrage 3e personne ou mirror-selfie — on voit alors le dos d'un iPhone (logo Apple, bumps caméra) dans la frame, ce qui détruit immédiatement l'effet UGC et trahit un rendu IA mal cadré. Précédent connu : segment 1 du `output/2026-05-12-le-mot-interdit/`. Le bloc complet est documenté dans `.claude/skills/ugc-video-seedance/SKILL.md` (section "POV front-camera (obligatoire, bloc complet, non négociable)") — recopier tel quel pour chaque segment ancre, adapter uniquement les pronoms.
- **Décrire un environnement avec miroir, vitre ou surface réfléchissante** dans le prompt d'un segment ancre, même implicitement. La règle "no mirror" du script-writer doit se propager au prompt vidéo : le bloc POV front-camera l'interdit explicitement, mais ne décris jamais dans le `video_prompt.txt` un "bathroom with mirror visible", "kitchen with reflective splashback", "car interior with side window reflection", etc. Cadrer en disant clairement la surface mate qu'on garde derrière le personnage (mur mat, faïence mate, bois, tissu).

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
- **Décor visiblement différent entre segment 1 et segment 2 (groupe ancre 1)** : le face-mask 1 n'a pas été passé en `--image` au segment 2 (vérifier que `anchor_group == 1`), ou Seedance a interprété le character asset au lieu du face-mask comme cadre de réf. Re-tirer le segment 2 avec face-mask 1 explicitement listé en premier `--image`.
- **Décor du seed ancre 2 trop proche de l'ancre 1** : le prompt Étape 5.1 n'a pas assez insisté sur le nouvel environnement. Re-tirer le seed ancre 2 avec un prompt qui décrit explicitement la nouvelle pièce (« now in the kitchen, matte countertop background » plutôt que reprendre la description de la salle de bain). Ensuite re-tirer le face-mask 2 (Étape 4 avec `S = seed_segment[2]`) puis les segments ancre 2 suivants.
- **Face-mask 2 absent au moment de générer un segment ancre 2 postérieur** : la sous-routine Étape 5.6 a échoué ou a été sautée. Re-tirer manuellement l'Étape 4 avec `S = seed_segment[2]`, puis re-générer les segments ancre 2 postérieurs avec `--segments <liste> --force`.
- **Dos d'iPhone visible dans le rendu (logo Apple, bumps caméra), ou main-tenant-un-téléphone visible** : le `video_prompt.txt` du segment ne contient pas le bloc "POV front-camera" complet. Insérer le bloc tel que documenté dans `.claude/skills/ugc-video-seedance/SKILL.md` (téléphone OUT of frame + interdiction mirror-selfie / 3e personne), supprimer toute formulation `holding the phone in selfie mode` qui suggère un cadrage 3e personne, puis `--segments <N> --force`.
- **Miroir / réflexion du personnage visible dans le rendu** : soit le `video_prompt.txt` décrit explicitement un environnement avec miroir (à corriger), soit le bloc POV front-camera est absent (l'interdiction "NO mirror-selfie" n'a pas été poussée au modèle). Réécrire le prompt avec un décor mat documenté (mur peint mat, faïence mate, bois) ET le bloc POV complet, puis `--segments <N> --force`.
