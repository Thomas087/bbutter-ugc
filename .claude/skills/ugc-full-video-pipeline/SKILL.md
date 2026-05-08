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
