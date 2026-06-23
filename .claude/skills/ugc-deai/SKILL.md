---
name: ugc-deai
description: >-
  Casse le rendu "trop AI / trop crisp" des segments vidéo Seedance d'une session UGC Butt Butter et harmonise leur colorimétrie sur le segment 1. Prend un dossier de session contenant `videos/segment_<N>_final.mp4` (sortie de `ugc-video-seedance` ou `ugc-full-video-pipeline`) et applique, segment par segment, un filtre ffmpeg figé : micro-blur (`unsharp=5:5:-0.5:5:5:0.0`) + film grain (`noise=alls=8:allf=t+u`) pour casser le pixel-perfect AI ; et pour les segments N>1 : `eq=saturation=0.88` + `gamma_r` / `gamma_g` calculés automatiquement à partir du delta de mean RGB vs segment 1 (heuristique ratio mid-gray, clampée à `[0.8, 1.2]`). Les originaux sont déplacés sous `videos/raw/` au premier run ; les versions de-AI'd sont écrites au chemin canonique `videos/segment_<N>_final.mp4` pour que `ugc-concat` les pick up sans changement. Idempotent : sur un re-run, la source est `videos/raw/` et les segments déjà traités sont skipped sauf si `--force`. Utilise ce skill dès que l'utilisateur demande "de-AI les segments", "casse le rendu AI", "les segments sont trop crisp / trop saturés", "harmonise les couleurs entre segments", "match la colorimétrie sur le segment 1", "rends les segments plus réalistes", "ajoute du grain aux segments", "Seedance est trop propre / trop net", ou veut un dernier passage de polish colorimétrique avant le concat final. Utilise-le aussi en fin de pipeline complet (déclenché automatiquement par `ugc-full-video-pipeline` après l'Étape 6).
---

# UGC De-AI — Butt Butter

Ce skill applique un dernier filtre vidéo aux segments d'une session UGC pour (a) casser le "trop crisp / trop pixel-perfect" qui trahit la génération IA et (b) harmoniser la colorimétrie entre segments en alignant chaque segment N>1 sur les moyennes RGB du segment 1. Sortie : les segments en place au chemin canonique `videos/segment_<N>_final.mp4`, originaux préservés sous `videos/raw/`. Pas de concat ici — c'est en aval (`ugc-concat`).

## Pourquoi cet effet

Seedance sort des plans techniquement propres mais visuellement *too clean* : edges pixel-perfect, vibrance lift artificielle, légère dérive colorimétrique d'un segment à l'autre (notamment un excès de rouge sur les inserts/segments postérieurs). Sur un format UGC, ces signaux trahissent immédiatement l'IA. Le filtre applique trois corrections empiriquement validées (cf. tuning `output/2026-05-12-le-bug-du-canape/`) :

- **`unsharp=5:5:-0.5:5:5:0.0`** (micro-blur sur la luma) : casse les edges pixel-perfect sans flouter perceptiblement. Le `-0.5` est un unsharp inversé — ffmpeg le traite comme un léger gaussian blur ciblé.
- **`noise=alls=8:allf=t+u`** : film grain temporel + uniforme, force 8/100. Single change le plus efficace pour faire passer une image AI pour de la captation iPhone. Le grain coûte cher en bitrate (le mp4 gonfle ~4x à CRF 18) — c'est attendu.
- **`eq=saturation=0.88`** (segments N>1 uniquement) : −12% de saturation pour tuer la vibrance AI. Le segment 1 n'en a pas besoin (c'est la référence).
- **`gamma_r` / `gamma_g` per-segment** (segments N>1) : calculés en runtime via `gamma = R_ref / R_N` (et idem pour G), clampé à `[0.8, 1.2]`. Heuristique ratio mid-gray — au mid-gray (~128/255), un gamma `g` produit un shift de mean ≈ `g`. C'est correct à ±5% près sur la plupart des plans UGC où la mean tourne autour de 0.4-0.6 luma.

## Quand l'utiliser

- L'utilisateur a sorti N segments via `ugc-video-seedance` ou `ugc-full-video-pipeline` et trouve la colorimétrie incohérente d'un plan à l'autre.
- L'utilisateur trouve que les segments "sentent l'IA" (trop saturé, trop net, plastique).
- Auto-déclenché en fin de `ugc-full-video-pipeline` (Étape 7) avant le concat.

## Quand NE PAS l'utiliser

- Sur un seul segment (le concept de "harmoniser sur le segment 1" suppose ≥ 2 segments).
- Si l'utilisateur veut un look spécifique différent (cinematic, vintage, B&W, hue shift…) : les paramètres sont figés sur "casser l'AI + matcher seg 1". Pour autre chose, faire un grade à la main dans un éditeur.
- Pour récupérer un plan avec un défaut **structurel** (lipsync décalée, dos d'iPhone visible, mirror-selfie) : aucun filtre couleur ne corrige ça. Re-générer le segment.

## Procédure

### 1. Pré-vérifications (silencieuses sauf erreur)

- `scripts/deai_videos.sh` existe et est exécutable.
- `ffmpeg` et `ffprobe` sont installés. Sinon : `brew install ffmpeg`.
- `<session_dir>/videos/` contient au moins `segment_1_final.mp4` (référence colorimétrique obligatoire) et un second segment (sinon rien à harmoniser).

### 2. Identifier la session

- Si l'utilisateur précise un chemin, l'utiliser tel quel.
- Sinon, par défaut, prendre la **session** la plus récente sous `output/` (le dossier qui contient `videos/segment_*_final.mp4`). Annoncer le choix en une ligne avant de lancer.

### 3. Lancer le traitement

```bash
./scripts/deai_videos.sh --in <session_dir>
```

Options :
- `--segments 2,3` : ne traite que les segments listés (utile pour ré-harmoniser un sous-ensemble après régénération).
- `--force` : ré-encode même si le segment a déjà été de-AI'd (idempotent par défaut : ne re-traite pas si `videos/raw/segment_<N>_final.mp4` existe déjà et que le canonical existe aussi).

### 4. Sortie attendue à l'utilisateur

Le script logge ligne par ligne :

```
Reference (segment 1): R=117 G=111 B=102
[segment 1] reference — texture only
[segment 1] → <session>/videos/segment_1_final.mp4  (post RGB=115/111/101, target=117/111/102)
[segment 2] raw RGB=127/112/103 → gamma_r=0.921 gamma_g=0.991
[segment 2] → <session>/videos/segment_2_final.mp4  (post RGB=118/114/103, target=117/111/102)
done: 2 segment(s) de-AI'd. Originals preserved in <session>/videos/raw/
```

Relayer à l'utilisateur :

1. Le dossier session utilisé (1 ligne, si auto-détecté).
2. Le delta colorimétrique le plus marqué (segment qui demandait le plus de correction).
3. Pointer vers `videos/raw/` pour les originaux (rassure : non-destructif).
4. Lancer optionnellement `open <session_dir>/videos/segment_2_final.mp4` pour validation visuelle.

Pas de blabla sur la chaîne de filtres ni sur le grain — c'est implicite.

## Layout fichiers (post-run)

```
<session_dir>/videos/
├── segment_1_final.mp4          ← de-AI'd (texture only, couleurs préservées)
├── segment_2_final.mp4          ← de-AI'd + color matched sur seg 1
├── segment_3_final.mp4          ← de-AI'd + color matched sur seg 1
├── ...
└── raw/
    ├── segment_1_final.mp4      ← original Seedance préservé
    ├── segment_2_final.mp4      ← original Seedance préservé
    └── ...
```

Le `videos/raw/` est créé au premier run et n'est plus touché ensuite. `ugc-concat` lit `videos/segment_<N>_final.mp4` (les versions de-AI'd) sans rien savoir de `raw/`.

## Idempotence et re-runs

- **Premier run** : pour chaque N, déplace `videos/segment_<N>_final.mp4` → `videos/raw/segment_<N>_final.mp4`, puis ré-encode depuis `raw/` vers le canonical.
- **Re-run sans `--force`** : détecte que `videos/raw/segment_<N>_final.mp4` ET `videos/segment_<N>_final.mp4` existent → skip ce N.
- **Re-run avec `--force`** : ré-encode depuis `raw/`, écrase le canonical. La source reste toujours `raw/` — pas de dégradation cumulative possible.
- **Régénération d'un segment seul amont** (via `ugc-video-seedance --force` ou ré-appel manuel de `scripts/generate_video_seedance.py`) : **étape manuelle obligatoire AVANT de re-lancer `ugc-deai`** — supprimer le raw périmé du segment concerné, sinon le script va lire l'ancien raw et ignorer la nouvelle génération :

  ```bash
  rm <session>/videos/raw/segment_<N>_final.mp4
  ./scripts/generate_video_seedance.py <session> <N> [--image ...]
  ./scripts/deai_videos.sh --in <session> --segments <N>
  ```

  Pourquoi : `deai_videos.sh` détermine sa source via `src_for()` qui retourne `raw/segment_<N>.mp4` en priorité s'il existe. Sans le `rm` préalable, la nouvelle génération (déposée au canonical par `generate_video_seedance.py`) sera écrasée par un ré-encodage de l'ancien raw — silencieusement, sans erreur. Le script `--force` ne sauve pas dans ce cas, parce que `--force` contourne juste le skip-check, pas le choix de source.

## Override courants

- **Filtre trop fort / trop faible** : le skill ne tune pas. Si l'utilisateur trouve le grain exagéré ou la désaturation excessive, sortir du skill et ajuster à la main `scripts/deai_videos.sh` (valeurs `noise=alls=`, `saturation=`, `unsharp` strength). Ne pas baker un mode "soft" / "hard" sans demande explicite et persistante.
- **Restaurer un original** : `cp videos/raw/segment_N_final.mp4 videos/segment_N_final.mp4`. Le script ne ré-écrasera pas tant que `--force` n'est pas passé.
- **Skip un segment** (ex : insert macro qui souffre du grain) : passer `--segments <liste sans N>` et restaurer manuellement le canonical depuis `raw/` pour ce N.
- **Reference autre que segment 1** : non supporté par le script. Si le segment 1 n'est pas représentatif, c'est probablement le segment 1 qu'il faut re-générer.

## Anti-patterns à éviter

- **Lancer `ugc-deai` avant que tous les segments soient générés.** Le segment 1 doit exister et être la référence visée. Si la session est en cours et qu'un segment manque, `ugc-deai` traitera ce qui existe — au prochain ajout de segment, il faut re-lancer pour le traiter, ce qui marche mais ajoute du bruit dans les logs.
- **Ré-encoder depuis le canonical au lieu de `raw/`.** Sur un re-run, encoder depuis le canonical (= déjà de-AI'd) cumulerait grain sur grain et saturation sur saturation. Le script lit toujours `videos/raw/` si présent. Ne pas court-circuiter cette logique.
- **Sampler la référence sur la version de-AI'd du segment 1.** Le grain et le micro-blur shiftent légèrement la mean (~1-2 unités). Si on prend la version traitée comme référence pour les segments suivants, le delta cumulatif diverge run après run. Le script sample toujours depuis `raw/segment_1_final.mp4` (si présent) — vérifier en lisant la sortie : la ligne `Reference (segment 1): R=… G=… B=…` doit donner les mêmes nombres run après run.
- **Appliquer une saturation < 0.85 ou > 0.95.** Trop bas → tout devient gris-cadavre, on perd les rouges du produit. Trop haut → on n'a pas désaturé. La valeur figée 0.88 est tunée sur le tube Butt Butter (rouge corail) — ne pas la déplacer sans tester sur un plan avec packshot.
- **Clamper le gamma hors `[0.8, 1.2]`.** Au-delà, l'image part en banding sur les midtones. La heuristique ratio R_ref/R_N produit rarement plus que `[0.85, 1.15]` sur des plans UGC réels ; un clamp à `[0.8, 1.2]` protège des plans pathologiques (très sombres, très clairs, ou avec un cast de couleur extrême).
- **Lancer `ugc-deai` en parallèle de `ugc-video-seedance` pour les segments suivants.** Pas dramatique fonctionnellement, mais ça brouille les logs et complique le diagnostic si un segment échoue. Le pipeline standard est strictement séquentiel : segments générés → de-AI → concat.

## Erreurs possibles

- **`ffmpeg / ffprobe not installed`** : `brew install ffmpeg`, puis relancer.
- **`error: segment_1_final.mp4 not found`** : la session n'a pas (encore) de segment 1. Le segment 1 sert de référence colorimétrique — pas optionnel.
- **`error: no segment_<N>_final.mp4 found`** : aucun segment dans `videos/` ni dans `videos/raw/`. Mauvais dossier session probablement.
- **Sortie qui semble flouter trop** : `unsharp -0.5` est déjà conservateur. Si l'effet est visible, c'est probablement le grain qui masque la netteté plutôt que l'unsharp lui-même — tester en isolant (commenter la ligne `noise=alls=` dans le script).
- **Saturation après filtre nettement < saturation cible** : peut arriver si le segment 1 lui-même était très saturé et que les autres l'étaient encore plus — la heuristique R/G ne corrige pas la saturation globale, seulement le ton per-channel. Workaround : régénérer le segment problématique en amont avec un prompt qui calme l'éclairage.
- **Délai de seek ffmpeg sur les segments très courts (< 1s)** : le sampling au midpoint peut tomber sur une frame qui n'existe pas. Le script fallback sur `t=1s` si la durée n'est pas parsable, ce qui marche dans 99% des cas. Pour < 1s, sampler `t=0` à la main.
- **Le mp4 final concat-é (`ugc-concat`) saute aux raccords après `ugc-deai`** : tous les segments sont ré-encodés en libx264 CRF 18 avec le même pix_fmt, donc le concat copy devrait passer. Si le saut persiste, lancer `ugc-concat` qui fallback automatiquement sur le ré-encodage uniforme.
