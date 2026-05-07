---
name: ugc-voice-generator
description: >-
  Génère la voix off d'un script UGC Butt Butter (sortie de `ugc-script-writer`) via ElevenLabs, segment par segment, puis accélère chaque segment à 1.2x pour le montage TikTok/Reels/Shorts. Choisit automatiquement la voix dans `scripts/voices.json` en fonction de la persona du script (âge, genre). Produit un dossier `voice_sections/` (originaux) et `voice_sections_1.2x/` (accélérés), plus un tableau des durées segment par segment, indispensable pour caler la durée des plans vidéo. Utilise ce skill dès que l'utilisateur demande "génère les audios", "génère la voix off", "génère les voix", "audio du script", "voix UGC", "TTS du script", ou demande à accélérer / changer la vitesse de la voix d'un script déjà écrit. Utilise-le aussi quand l'utilisateur veut connaître la durée réelle de chaque segment vocal pour ajuster le montage.
---

# UGC Voice Generator — Butt Butter

Ce skill prend un script UGC Butt Butter (markdown produit par `ugc-script-writer`, avec ses segments `**Voix :** "..."`) et génère la voix off complète, segment par segment, puis accélère chaque segment à 1.2x pour un rendu TikTok/Reels/Shorts plus dynamique.

## Pourquoi segment par segment + 1.2x

- **Segment par segment** : chaque plan vidéo doit être calé sur la durée *réelle* de son audio. Un MP3 unique combiné ne suffit pas — il faut une durée par segment pour le montage.
- **1.2x** : la voix ElevenLabs en `eleven_v3` est posée par défaut. Sur un format short (TikTok / Reels), un léger speed-up (1.2x) donne le rythme attendu sans déformer la voix (l'`atempo` ffmpeg garde le pitch).

## Entrées

- **Script source** : chemin vers un `.md` produit par `ugc-script-writer`. Si l'utilisateur ne précise pas, prends le dernier dossier sous `output/` (le plus récent par date) et son `script.md`.
- **Persona** : à lire dans le tableau d'en-tête du script (ligne `| **Persona** | … |`). Sert à choisir la voix.

## Catalogue de voix

Le catalogue est dans `scripts/voices.json`. Listing rapide :

```bash
jq -r '.voices[] | "\(.id)\t\(.gender)\t\(.age)\t\(.description)"' scripts/voices.json
```

Format : `id`, `gender` (Homme / Femme), `age` (entier), `description`.

### Règle de sélection automatique

Compare la persona du script aux entrées du catalogue, dans cet ordre de priorité :

1. **Genre** : strictement match. Si la persona est féminine, ne prends pas une voix masculine, même si l'âge colle mieux. (Si aucune voix du bon genre n'existe encore, signale-le à l'utilisateur et propose d'en ajouter une plutôt que de défaut sur le mauvais genre.)
2. **Âge** : prends la voix dont l'âge est le plus proche (différence absolue minimale).
3. **Description** : départage à description neutre par défaut. Si le script demande un ton particulier (chaleureux, jeune, autoritaire) et qu'une description correspond, privilégie-la.

Annonce ton choix à l'utilisateur en une ligne avec la justification : `Voix choisie : <id> (<gender>, <age> ans, <description>) — match avec la persona <prénom>, <âge> ans.`

L'utilisateur peut override en passant une voice id explicite (`--voice <id>`) — dans ce cas, ne fais pas de sélection auto.

## Procédure

### 1. Pré-vérifications (silencieuses, ne pas commenter sauf erreur)

- `scripts/generate_voice.sh` existe et est exécutable
- `scripts/voices.json` existe
- `ffmpeg` est installé (`command -v ffmpeg`) — requis pour le speed-up. Si absent, demande à l'utilisateur de l'installer (`brew install ffmpeg`) et stoppe.
- Le script source contient bien des lignes `**Voix :** "..."` (`grep -c '^\*\*Voix' <script>`). Sinon, signale-le.

### 2. Choix de la voix

Lis la persona dans l'en-tête du script. Applique la règle de sélection ci-dessus contre `scripts/voices.json`. Annonce le choix à l'utilisateur en une ligne avant de lancer la génération.

### 3. Génération des segments

Lance `scripts/generate_voice.sh` avec `--per-section`, `--voice <id>` et `--out <output_dir>/voice.mp3` :

```bash
./scripts/generate_voice.sh \
  --script <script_path> \
  --voice <selected_voice_id> \
  --per-section \
  --out <script_dir>/voice.mp3
```

Le script crée :
- `<script_dir>/voice.mp3` — version combinée (utile pour preview rapide, pas pour le montage)
- `<script_dir>/voice_sections/section-01.mp3` … `section-NN.mp3` — un MP3 par segment `**Voix :** "..."` du markdown, dans l'ordre.

Le script est idempotent : il ne régénère pas un MP3 plus récent que la source. Si l'utilisateur veut forcer la régénération, supprime d'abord les MP3 existants ou demande-lui s'il préfère un dossier de sortie différent.

### 4. Accélération à 1.2x

Pour chaque section, applique `atempo=1.2` (préserve le pitch) :

```bash
mkdir -p <script_dir>/voice_sections_1.2x
cd <script_dir>/voice_sections
for f in section-*.mp3; do
  ffmpeg -y -loglevel error -i "$f" -filter:a "atempo=1.2" -vn \
    "../voice_sections_1.2x/$f"
done
```

Sortie : `<script_dir>/voice_sections_1.2x/section-NN.mp3`.

Note : `atempo` accepte `[0.5, 100.0]`. Pour 1.2x un seul filtre suffit. Si l'utilisateur demande > 2x un jour, chaîner deux `atempo` (ex `atempo=2.0,atempo=1.5` pour 3x).

### 5. Mesure des durées et tableau récapitulatif

Mesure la durée de chaque section accélérée :

```bash
for f in <script_dir>/voice_sections_1.2x/section-*.mp3; do
  dur=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$f")
  printf "%s : %.2fs\n" "$(basename "$f")" "$dur"
done
```

Puis livre un tableau markdown à l'utilisateur, en mappant chaque `section-NN.mp3` au segment correspondant du script (titre de la section H2, ex. `HOOK`, `RÉVÉLATION`, `PRODUIT 1 — Crème`) et à sa durée prévue (extraite des timecodes `[0:XX – 0:YY]`).

Format attendu :

| # | Segment | Prévu script | Audio 1.2x |
|---|---|---|---|
| 01 | HOOK | 3,0s | **4,82s** |
| 02 | RÉVÉLATION | 6,0s | **3,08s** |
| … | … | … | … |
| | **Total** | **45,0s** | **37,61s** |

### 6. Diagnostic

Compare prévu vs réel et signale en clair :

- **Plus court que prévu** (gap > 1,5s) : le plan vidéo va sprinter. Suggérer ralenti packshot, silence respiré, plan d'illustration supplémentaire.
- **Plus long que prévu** (gap > 1,5s) : l'audio déborde. Suggérer de raccourcir la formulation au prochain pass d'écriture, OU d'allonger le plan.
- **Total < prévu** : la vidéo sera plus courte que le brief. OK pour TikTok (35-40s reste dans la zone), à signaler si on visait 45s pile.

Ne fais pas le diagnostic à la place de l'utilisateur si le gap est < 1,5s — pas la peine de polluer.

## Sortie attendue à l'utilisateur

Une réponse courte qui contient, dans l'ordre :

1. La voix choisie (1 ligne, avec justification)
2. Les chemins des dossiers générés (`voice_sections/`, `voice_sections_1.2x/`)
3. Le tableau des durées
4. Le diagnostic, uniquement si pertinent

Pas de commentaire sur le déroulé technique (génération réussie, fichiers écrits) — c'est implicite.

## Override courants

- **Vitesse différente** : si l'utilisateur demande 1.0x (pas d'accélération), 1.1x, 1.3x, etc., ajuste `atempo` et nomme le dossier `voice_sections_<vitesse>x` (ex `voice_sections_1.3x`). Garde toujours les originaux dans `voice_sections/`.
- **Voix forcée** : si l'utilisateur passe une voice id, skip la sélection auto, mentionne juste la voix utilisée.
- **Régénération forcée** : supprime `voice_sections/` et `voice_sections_1.2x/` avant relance, ou propose un sous-dossier daté.

## Erreurs possibles

- **`no '**Voix :** "..."' lines found`** : le script source n'a pas le format attendu. Demande à l'utilisateur si c'est bien un script produit par `ugc-script-writer`. Possible aussi que les guillemets soient typographiques `"…"` au lieu de droits `"…"` — dans ce cas, demande à corriger le markdown source.
- **`ELEVENLABS_API_KEY missing`** : la clé n'est pas dans `.env` à la racine du repo. Demande à l'utilisateur de l'ajouter. Ne tente pas de la deviner ni de la chercher ailleurs.
- **HTTP 401 ElevenLabs** : clé invalide ou quota épuisé.
- **HTTP 429 ElevenLabs** : rate limit. Attendre, ou réduire le nombre de segments.
- **`ffmpeg: command not found`** : `brew install ffmpeg`, puis relancer.
