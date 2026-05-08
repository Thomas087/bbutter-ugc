---
name: ugc-face-mask-extractor
description: >-
  Génère un "face-mask reference" (frame UGC avec le visage du créateur entièrement recouvert par une forme opaque, le reste de l'image inchangé) à partir du premier frame d'un segment vidéo UGC Butt Butter, pour servir de référence de continuité corps + décor aux plans suivants tout en laissant Seedance ou un outil de face-swap re-générer le visage proprement. Pipeline en deux temps : extraction de la première image du `videos/segment_<N>_final.mp4` via ffmpeg → `frames/segment_<N>/first_frame.png`, puis appel `gpt-image-2` (avec fallback `gpt-image-1`) via `scripts/generate_image.sh --ref` qui peint une forme opaque (typiquement un ovale gris neutre) par-dessus le visage en gardant le corps, le téléphone, la tenue et le décor identiques → `frames/segment_<N>/first_frame_face_mask.png`. Utilise ce skill dès que l'utilisateur demande "face mask", "masque le visage", "anonymise le visage", "cache le visage avec une forme", "blank face reference", "frame avec visage masqué", "référence sans le visage", "face cutout", ou veut figer la posture corps + décor d'un plan UGC sans figer le visage. Utile aussi pour briefer un face-swap post-prod, anonymiser un cadre pour partage, ou nourrir un image-to-video avec une référence où seul le visage est libre de varier.
---

# UGC Face Mask Extractor — Butt Butter

Ce skill prend la **première image** d'un plan vidéo UGC déjà généré (typiquement par `ugc-video-seedance`) et produit un **face-mask reference** : la même image, mais avec le visage du personnage entièrement recouvert par une forme opaque (ovale gris neutre, sans dégradé, sans transparence). Tout le reste — corps, mains, téléphone, vêtements, cheveux autour du visage, décor, lumière — reste identique. Utile pour :

- **Continuité corps + décor sans figer le visage** : nourrir Seedance/Kling/Runway avec un cadre de référence où la posture, le téléphone, la tenue et le décor sont fixés, mais où le visage doit être re-généré depuis le character asset (le modèle a tendance à mieux re-synthétiser un visage cohérent quand on lui retire le visage référence partiellement dérivé du run précédent).
- **Brief face-swap post-prod** : montrer "voilà la composition figée, on swap juste le visage en post" à un retoucheur ou un outil dédié (DeepFaceLab, Insight FaceSwap, etc.).
- **Anonymisation rapide** : partager un cadre de référence sans exposer un visage de figurant ou de modèle généré.
- **Référence image-to-video** : la zone masquée force le modèle à inventer le visage plutôt qu'à essayer de le copier — souvent plus stable visuellement entre plans.

## Entrées

- **Dossier de sortie du script** : par défaut, le dernier dossier sous `output/` (le plus récent par date). L'utilisateur peut en passer un autre.
- **Numéro de segment** : par défaut `1`. Format de la vidéo source : `<output_dir>/videos/segment_<N>_final.mp4`. Si `_final.mp4` n'existe pas, retombe dans cet ordre : `segment_<N>_seedance_lofi_lipsync.mp4`, `segment_<N>_seedance_lofi.mp4`, `segment_<N>_seedance_silent.mp4`.
- **Forme du masque** : par défaut `oval` (le plus naturel pour couvrir tête + menton + oreilles sans déborder sur les épaules). Alternatives utiles : `circle`, `rounded rectangle`. Couleur par défaut `neutral light grey` — uni, sans dégradé.
- **Override utilisateur** : si l'utilisateur précise un timestamp autre que la première frame, passe `-ss <ts> -frames:v 1` à ffmpeg.

## Procédure

### 1. Pré-vérifications (silencieuses, ne pas commenter sauf erreur)

- `OPENAI_API_KEY` est dans `.env` à la racine du repo. Si absent, demande à l'utilisateur de l'ajouter, ne tente pas de deviner.
- `ffmpeg` est installé (`command -v ffmpeg`). Sur macOS : `brew install ffmpeg` si manquant.
- `scripts/generate_image.sh` accepte `--ref` (`grep -q -- '--ref' scripts/generate_image.sh`).
- Le dossier `<output_dir>/videos/segment_<N>_*.mp4` contient au moins une variante.

### 2. Extraction de la première frame

```bash
OUT_DIR=<output_dir>
N=<segment_number>
mkdir -p "$OUT_DIR/frames/segment_$N"

# Choisis la première variante existante par ordre de préférence
for cand in \
  "$OUT_DIR/videos/segment_${N}_final.mp4" \
  "$OUT_DIR/videos/segment_${N}_seedance_lofi_lipsync.mp4" \
  "$OUT_DIR/videos/segment_${N}_seedance_lofi.mp4" \
  "$OUT_DIR/videos/segment_${N}_seedance_silent.mp4"; do
  [[ -f "$cand" ]] && SRC="$cand" && break
done

ffmpeg -y -i "$SRC" -vframes 1 -update 1 -q:v 2 \
  "$OUT_DIR/frames/segment_$N/first_frame.png"
```

Notes :
- **`-update 1`** : silence le warning "filename does not contain an image sequence pattern" — sans lui ffmpeg écrit quand même mais affiche un avertissement parasite.
- **`-q:v 2`** : qualité PNG quasi-lossless. Pas de raison d'aller plus bas, le PNG sera ré-uploadé à OpenAI.
- **`-vframes 1`** : strictement la frame 0. Si l'utilisateur veut un autre instant, ajoute `-ss <hh:mm:ss>` AVANT `-i` (pour seek rapide) ou APRÈS `-i` (pour seek précis).

### 3. Construire le prompt de face-mask

Le prompt force le modèle à peindre une forme opaque uniquement sur la zone du visage et à laisser tout le reste de l'image strictement intact. Sans cette insistance répétée, gpt-image-2 a tendance soit à redessiner le corps autour de la forme, soit à ajouter une transparence / un dégradé sur le masque, soit à ajuster la lumière du décor.

```
Reference frame with the face fully blocked. In this {{description du décor — ex: bathroom selfie}} image, paint a single opaque flat {{shape: oval / circle / rounded rectangle}} of solid {{color: neutral light grey, no gradient}} completely covering the {{description courte de la personne — ex: man's}} face. The shape must be: large enough to cover from forehead to chin and from ear to ear, fully opaque, smooth-edged, no transparency, no gradient, no texture, no features, no eyes, no mouth, no nose, no shadows, no highlights — a clean flat blocking shape sitting on top of the face area like a censorship sticker.

Keep absolutely EVERYTHING else IDENTICAL to the input image: same camera framing, same vertical {{aspect ratio}} aspect, same lighting, same body posture, same hands, same phone (same color, same case, same exact position and angle), same clothes, same hair visible around the masked area, same {{détails clés du décor — ex: tiles, mirror, towel, shelf}}, same overall color cast and grain. Do NOT redraw the body, the hands, the phone, the clothes or the background — only paint the opaque shape on top of the face area. The result should look exactly like the input image with a flat censorship oval pasted over the face.

Photoreal everywhere except the shape itself (which is flat by design). iPhone front-camera look. Absolutely no on-screen text, captions, subtitles, watermarks, labels, or annotations of any kind.
```

**Récupération automatique des détails** :
- Lis le `frames/segment_<N>/video_prompt.txt` s'il existe (généré par `ugc-video-seedance`). Il contient déjà la description précise de la personne, du décor et de la pose — extrais-en les éléments à protéger (mur, fenêtre, meubles, accessoires, téléphone, vêtements) et la description courte de la personne (genre, âge approximatif).
- Sinon, lis le `script.md` du dossier (en-tête : ligne `| **Décor** | … |` et `| **Persona** | … |`).
- Aspect ratio : déduis-le des dimensions du PNG extrait (`sips -g pixelWidth -g pixelHeight`). Si le ratio est ≈9:16, écris `vertical 9:16`. Si ≈16:9, `landscape 16:9`. Si ≈1:1, `square`.

**Bloc "EVERYTHING else IDENTICAL" non négociable** : sans cette répétition, gpt-image-2 dérive sur le corps ou le décor. Si tu raccourcis ce paragraphe, le rendu n'est plus utilisable comme référence de continuité.

**Bloc "no transparency, no gradient, no features"** non négociable non plus : sinon le modèle a tendance à laisser transparaître le visage à 30% sous la forme, ce qui casse l'usage de "masque vraiment opaque".

### 4. Appel API via `generate_image.sh --ref`

```bash
set -a; source .env; set +a

OPENAI_IMAGE_QUALITY=high \
  ./scripts/generate_image.sh \
    --ref "$OUT_DIR/frames/segment_$N/first_frame.png" \
    "$OUT_DIR/frames/segment_$N/first_frame_face_mask.png" \
    "$(cat "$OUT_DIR/frames/segment_$N/face_mask_prompt.txt")" \
    1024x1536
```

Notes :
- **`OPENAI_IMAGE_QUALITY=high`** : indispensable. En `low`, le bord de la forme est crénelé / pixelisé et certaines parties du décor / des vêtements sont reconstruits flous au lieu d'être laissés tels quels.
- **`--ref <first_frame.png>`** : passe la frame originale en multipart `image[]` à `/v1/images/edits`. C'est ce qui ancre le modèle à la composition existante. Sans cette ref, le modèle hallucine un nouveau cadrage.
- **Taille** : `1024x1536` pour des plans verticaux 9:16 (sortie cropée à 864x1536 par défaut). Pour du landscape 16:9, utilise `1536x1024` + `--no-crop`. Pour du carré, `1024x1024`.
- **Sauvegarde du prompt** : écris-le d'abord dans `face_mask_prompt.txt` à côté du PNG (même logique que `ugc-character-sheet-generator`). Permet d'itérer sans re-rédiger.

### 5. Sortie attendue à l'utilisateur

Une réponse courte qui contient, dans l'ordre :

1. Le chemin de la frame source extraite (`first_frame.png`) et du face-mask généré (`first_frame_face_mask.png`).
2. Les deux images affichées inline (`Read` sur les PNG) — l'utilisateur veut comparer visuellement et vérifier que seul le visage est masqué.
3. **Une vérification rapide** : si la forme déborde sur le cou / les épaules / le téléphone, ou si le décor a visiblement bougé, signaler le défaut et proposer un re-tirage (variance modèle) ou un raffinage du prompt (forcer "shape covers ONLY the face, NOT the neck, NOT the shoulders, NOT the phone"). Pas de commentaire si le rendu est propre.
4. Une ligne d'invitation à itérer ("Si tu veux un autre segment, une autre forme/couleur de masque, ou un autre instant dans le clip, dis-moi.").

## Overrides courants

- **Multi-segments** : si l'utilisateur veut un face-mask par segment ("génère les face-masks pour les 5 segments"), boucle sur `N` et appelle l'API en parallèle (gpt-image-2 supporte plusieurs requêtes concurrentes — environ 30s chacune en `high`). Saute les segments dont le face-mask existe déjà sauf si `--force`.
- **Forme alternative** : par défaut `oval`. Si l'utilisateur précise `circle`, `rounded rectangle`, `pixelated mosaic`, ajuste le bloc `paint a single opaque flat ...` du prompt. Pour `pixelated mosaic`, change la cohérence : `apply a coarse pixelation effect (large square pixels, ~30 pixels per row) over the face area — same intent: face fully unreadable`.
- **Couleur alternative** : `neutral light grey` par défaut. `solid black`, `solid white`, `safety yellow`, `pure red` marchent tous. Évite les couleurs qui matchent le décor (un gris qui se confond avec le carrelage rend la forme illisible).
- **Frame autre que la première** : si l'utilisateur dit "prends la frame du milieu" ou "à 2 secondes", utilise `ffprobe` pour récupérer la durée et calcule le timestamp, puis passe `-ss <ts> -frames:v 1` à ffmpeg. Le nom de fichier devient `frame_<ts>.png` / `frame_<ts>_face_mask.png` au lieu de `first_frame.png` pour ne pas écraser.
- **Ré-extraction sans ré-edit** : si la première frame existe déjà mais que l'utilisateur veut juste re-tirer le face-mask (variance du modèle), saute l'étape 2 et passe directement à l'étape 4. gpt-image-2 a une variance non négligeable — un second tirage corrige souvent un défaut localisé (forme qui déborde sur le cou, opacité insuffisante).
- **Personne réelle déjà tournée** : si l'utilisateur fournit une vraie vidéo (pas une génération Seedance), le pipeline marche pareil. Adapte la description de la personne dans le prompt à ce qu'on voit dans la frame, pas à la persona du script.
- **Inversion (clean plate, pas de personne du tout)** : si l'utilisateur veut le contraire — retirer la personne entière au lieu de masquer juste le visage — change le prompt en "Remove the person entirely from this image, keep everything else identical, reconstruct the area that was occluded by the person and their phone with a plausible continuation of the same {{décor}}". Sortie : `first_frame_clean_plate.png`. (C'est l'ancien comportement de ce skill avant qu'il soit pivoté sur le face-mask.)
- **Masque flou plutôt qu'opaque** : pour anonymisation type "blur visage" plutôt que "censure", remplace `paint a single opaque flat oval...` par `apply a strong gaussian blur over the face area, fully unreadable, soft circular falloff, no recognizable features remain`. Garde le bloc "everything else IDENTICAL" intact.

## Erreurs possibles

- **`OPENAI_API_KEY not set`** : la clé n'est pas dans `.env`. Demande à l'utilisateur de l'ajouter.
- **`ffmpeg: No such file or directory`** : la vidéo source n'existe pas. Vérifie que `ugc-video-seedance` a bien produit le segment, ou que le numéro de segment est correct.
- **HTTP 403 "must be verified"** : le compte OpenAI n'est pas vérifié pour `gpt-image-2`. `generate_image.sh` retombe automatiquement sur `gpt-image-1` — la précision du masque est plus basse mais utilisable. Mentionne le fallback à l'utilisateur.
- **HTTP 400 "invalid size"** : la taille passée n'est pas dans `{1024x1024, 1024x1536, 1536x1024, auto}`. Repasse à `1024x1536` (vertical) ou `1536x1024` (landscape).
- **Le masque est semi-transparent / on devine le visage** : le bloc "no transparency, no gradient" a été raccourci ou le `OPENAI_IMAGE_QUALITY` n'est pas en `high`. Vérifie les deux et relance.
- **Le masque déborde sur le cou ou le téléphone** : ajoute explicitement "shape covers ONLY the face, NOT the neck, NOT the shoulders, NOT the phone, NOT the hand" dans le prompt. Si le rendu reste fautif, tire 2-3 fois (variance modèle).
- **Le décor a visiblement bougé / la lumière a changé / les vêtements ont été redessinés** : c'est exactement ce que le bloc "EVERYTHING else IDENTICAL" est censé empêcher. Vérifie qu'il est bien dans le prompt envoyé. Si oui, c'est de la variance modèle — relance.
- **Le PNG est en 864x1536 alors qu'on voulait conserver la résolution native du frame** : `generate_image.sh` croppe par défaut à 9:16. Si l'utilisateur veut conserver précisément la résolution de la vidéo source, downscale le face-mask à la résolution de la frame originale via `sips -Z` ou `ffmpeg -vf scale`. Préviens l'utilisateur que la résolution sortie est celle du modèle (864x1536), pas celle du clip Seedance.
