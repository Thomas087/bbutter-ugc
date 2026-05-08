---
name: ugc-concat
description: >-
  Concatène les segments vidéo d'un script UGC Butt Butter en une vidéo finale unique. Prend en entrée un dossier de session contenant `videos/segment_<N>_final.mp4` (sortie de `ugc-video-seedance` ou `ugc-full-video-pipeline`), trie par index N croissant, et utilise le concat demuxer de ffmpeg avec `-c copy` (pas de ré-encodage, instant, qualité 100% préservée). Sortie : `<session>/final.mp4`. Fallback automatique en ré-encodage `libx264 + aac` si les codecs des segments diffèrent et que le concat copy échoue. Utilise ce skill dès que l'utilisateur demande "concatène les segments", "assemble la vidéo finale", "joins les plans", "ffmpeg concat", "monte la vidéo UGC", "fusionne les segments", "produit le mp4 final", "stitch the segments together", ou veut produire le mp4 final d'un script déjà découpé en N plans Seedance. Utilise-le aussi pour re-générer le mp4 final après régénération d'un seul segment, ou pour assembler un sous-ensemble de segments via `--segments`.
---

# UGC Concat — Butt Butter

Ce skill assemble les `videos/segment_<N>_final.mp4` d'une session en une vidéo finale unique `<session>/final.mp4`. Concat sans ré-encodage par défaut (ffmpeg concat demuxer + `-c copy`) — instantané, qualité préservée. Fallback en ré-encodage si les codecs/dimensions ne matchent pas.

Consomme en aval de `ugc-video-seedance` ou `ugc-full-video-pipeline`. Pas d'overlay texte, pas de musique, pas de transitions — c'est volontairement minimal. Les overlays/captions se font dans un éditeur en post.

## Entrées

| Paramètre | Défaut | Notes |
|---|---|---|
| `session_dir` | dernier dossier sous `output/` (le plus récent par date ISO) | Doit contenir `videos/segment_<N>_final.mp4` pour au moins 2 N consécutifs. |
| `--segments` | tous les `segment_<N>_final.mp4` trouvés, triés par N croissant | Liste 1-based séparée par virgules, ex : `--segments 1,2,3` (utile pour assembler un brouillon partiel). |
| `--output` | `<session>/final.mp4` | Surcharge le chemin de sortie. |
| `--force` | off | Écrase `final.mp4` s'il existe déjà. |

## Pré-vérifications (silencieuses sauf erreur)

1. `<session_dir>` existe et contient `videos/`.
2. Au moins 2 fichiers `videos/segment_<N>_final.mp4` existent (pas la peine de "concat" un seul plan).
3. Les indices N sont **consécutifs** à partir de 1 (1, 2, 3, ...). Si un trou (ex : 1, 2, 4, 5), **stoppe** et demande à l'utilisateur s'il veut concat les segments existants tels quels (`--segments 1,2,4,5`) ou re-générer le segment manquant.
4. `command -v ffmpeg` retourne un chemin.

Si une vérif échoue : message d'erreur en une ligne pointant le pré-requis manquant.

## Procédure

### 1. Lister et trier les segments

```bash
SESSION="<session_dir>"
shopt -s nullglob
mapfile -t SEGMENTS < <(
  ls "$SESSION/videos"/segment_*_final.mp4 2>/dev/null \
    | sort -V
)
```

`sort -V` (version sort) gère correctement `segment_2`, `segment_10` (vs lexicographique qui mettrait `segment_10` avant `segment_2`).

Si l'utilisateur a passé `--segments 1,3,5`, filtre la liste pour ne garder que ces indices.

Affiche la liste pour validation visuelle :

```
Segments trouvés (5) :
  videos/segment_1_final.mp4 (5.0s, 1.3 MB)
  videos/segment_2_final.mp4 (5.0s, 1.4 MB)
  videos/segment_3_final.mp4 (10.0s, 2.5 MB)
  videos/segment_4_final.mp4 (10.0s, 2.6 MB)
  videos/segment_5_final.mp4 (5.0s, 1.3 MB)
```

(Durées via `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 <mp4>`.)

### 2. Construire la concat list pour ffmpeg

```bash
LIST="$SESSION/.concat_list.txt"
: > "$LIST"
for f in "${SEGMENTS[@]}"; do
  printf "file '%s'\n" "$f" >> "$LIST"
done
```

Notes :
- Le format attendu par le concat demuxer est `file '<path>'` une ligne par segment.
- Les chemins absolus sont OK et plus robustes que les relatifs (évite les surprises avec `cd`).
- Le fichier est temporaire — supprime-le après le concat.

### 3. Concat sans ré-encodage (chemin rapide)

```bash
OUT="$SESSION/final.mp4"

ffmpeg -y -hide_banner -loglevel error \
  -f concat -safe 0 -i "$LIST" \
  -c copy -movflags +faststart \
  "$OUT"
```

- `-f concat` active le concat demuxer.
- `-safe 0` autorise les chemins absolus (sinon ffmpeg refuse pour des raisons de sécurité).
- `-c copy` : pas de ré-encodage, instantané (~1 s pour 5 segments).
- `-movflags +faststart` : déplace le moov atom au début, le mp4 démarre à streamer immédiatement (utile pour upload TikTok / preview).

Si la commande retourne 0 et que `OUT` existe avec une durée plausible (= somme des durées des segments, à 0.1 s près), passer à l'étape 5.

### 4. Fallback : ré-encodage si concat copy échoue

Le concat copy échoue (typiquement code de retour ≠ 0 ou warning "Non-monotonic DTS in output stream") quand les segments ont des codecs/résolutions/timebases différents. Cas classique : un segment Seedance a été regénéré avec un modèle différent, ou un segment vient d'une autre source (Kling, etc.).

Bascule sur ré-encodage uniforme :

```bash
ffmpeg -y -hide_banner -loglevel error \
  -f concat -safe 0 -i "$LIST" \
  -c:v libx264 -preset medium -crf 18 \
  -c:a aac -b:a 192k \
  -movflags +faststart \
  "$OUT"
```

- `crf 18` ≈ visuellement lossless pour du UGC vertical 9:16.
- `preset medium` : compromis vitesse/taille raisonnable. Pour un encode plus rapide passer `fast` ou `veryfast`.
- ~10-30 s pour 5 segments selon le CPU.

### 5. Nettoyer

```bash
rm -f "$LIST"
```

### 6. Sortie attendue à l'utilisateur

Une réponse courte qui contient, dans l'ordre :

1. Chemin de la vidéo finale.
2. Durée totale (`ffprobe ... format=duration`) et taille (`ls -lh`).
3. Mode : `copy` (sans ré-encodage) ou `re-encoded` (libx264 + aac).
4. Si re-encodé : la raison probable (mismatch codec/résolution constatée).

Exemple :

```
Vidéo finale : output/2026-05-08-le-3eme/final.mp4 (35.0s, 6.8 MB) — concat sans ré-encodage.
```

ou

```
Vidéo finale : output/2026-05-08-le-3eme/final.mp4 (35.0s, 9.2 MB) — re-encoded (libx264 crf 18 + aac 192k). Cause : segment 3 en h265 vs autres en h264.
```

Pas de commentaire gratuit. Pas de "concat réussi" / "fichiers écrits" — c'est implicite.

## Override courants

- **Sous-ensemble de segments** : `--segments 1,2,3` pour assembler un brouillon des 3 premiers plans avant de générer le reste.
- **Output personnalisé** : `--output /tmp/preview.mp4` pour ne pas écraser `<session>/final.mp4`.
- **Forcer re-encode** (debug ou normalisation) : passer le ffmpeg de l'étape 4 directement, sans tenter le copy. Utile si tu veux unifier le bitrate avant publication.
- **Concat avec un segment d'une autre session** : ffmpeg concat ne fait pas de magie de format — si les sources ont des codecs/dimensions différents, le copy échouera. Utilise le fallback re-encode.

## Anti-patterns à éviter

- **Ré-encoder par défaut.** Le concat copy est instantané et lossless. Ne re-encode que si le copy échoue ou si l'utilisateur demande explicitement à normaliser.
- **Concat avec `ffmpeg -i seg1.mp4 -i seg2.mp4 ...`** (filter complex). Marche mais lent (ré-encode obligatoire) et complexe à scripter pour N segments. Le concat demuxer est l'outil standard pour ce cas.
- **Oublier `-safe 0`** quand la concat list contient des chemins absolus. ffmpeg refuse silencieusement (ou bruyamment selon la version) sans cette flag.
- **Oublier `-movflags +faststart`** sur le mp4 final. Sans ça, le mp4 ne démarre pas en preview avant d'avoir téléchargé le fichier entier — irritant pour TikTok/Reels upload.
- **Concat un seul segment.** `cp segment_1_final.mp4 final.mp4` suffit. Le concat demuxer marche aussi mais c'est de la machinerie inutile.
- **Trier les segments en ordre lexicographique** (`ls` brut). Marche jusqu'à 9 segments puis `segment_10_final.mp4` se retrouve avant `segment_2_final.mp4`. Toujours `sort -V` (version sort) ou un tri numérique explicite.

## Erreurs possibles

- **`No such file or directory: videos/`** : le dossier session n'a pas été produit par les skills amont. Vérifier que `ugc-video-seedance` ou `ugc-full-video-pipeline` a tourné.
- **`Operation not permitted` sur la concat list** : `-safe 0` manquant et chemins absolus dans la liste. Ajouter le flag.
- **`Non-monotonic DTS in output stream`** (warning) : timebases différents entre segments. Le copy peut quand même produire un mp4 lisible mais avec des artefacts de seek. Si la lecture saute aux raccords, basculer sur le fallback re-encode.
- **Mp4 final lit la première partie puis se fige** : l'audio des segments a des sample rates différents. Le copy ne ré-aligne pas. Re-encode avec `-ar 48000` forcé sur la sortie.
- **Durée du mp4 final ≠ somme des segments** : un segment a un PTS corrompu. Re-encode pour normaliser.
- **`Output file is empty, nothing was encoded`** : la concat list est vide ou tous les fichiers listés sont introuvables. Vérifier `cat "$LIST"` et que les chemins sont absolus.
