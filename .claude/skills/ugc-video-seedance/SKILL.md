---
name: ugc-video-seedance
description: >-
  Génère un plan vidéo UGC Butt Butter, segment par segment, via l'API Seedance (BytePlus Ark, modèle `dreamina-seedance-2-0-...`). Pipeline en un seul appel : `scripts/generate_video_seedance.py` auto-attache la voix `voice_sections_1.2x_lofi/section-<NN>.mp3` comme `reference_audio`, le prompt la référence par `[Audio 1]` pour piloter la cadence labiale, le prompt contient aussi la phrase française exacte du segment entre guillemets droits pour empêcher Seedance d'halluciner le texte, et `generate_audio=True` (par défaut) embarque directement la piste audio dans la vidéo finale → `videos/segment_<N>_final.mp4`. Lit `scripts/characters.json` (champ `seedance_asset_id`) pour résoudre le character asset BytePlus depuis la persona du script. Lit `brand/products/catalog.yaml` pour récupérer le packshot du produit en référence visuelle. Utilise ce skill dès que l'utilisateur demande "génère la vidéo Seedance", "génère le segment N en vidéo", "vidéo UGC du script", "plan vidéo Seedance", "vidéo avec lipsync sur la voix lo-fi", "génère le clip pour le segment X", ou veut produire / régénérer un plan vidéo à partir d'un segment de script déjà voicé. Utilise-le aussi quand l'utilisateur veut tester un seul plan avant d'enchaîner toute la vidéo, ou quand il veut raffiner la lipsync d'un plan existant.
---

# UGC Video Seedance — Butt Butter

Ce skill prend un script UGC Butt Butter (sortie `ugc-script-writer`) avec sa voix lo-fi déjà produite (sortie `ugc-voice-lofi`) et génère un plan vidéo via l'API Seedance (BytePlus Ark, modèle `dreamina-seedance-2-0-260128`), un segment à la fois. Il est consommé en aval de `ugc-script-writer` → `ugc-voice-generator` → `ugc-voice-lofi`.

## Pipeline en un appel

`scripts/generate_video_seedance.py` :

1. Auto-attache `voice_sections_1.2x_lofi/section-<NN>.mp3` comme `reference_audio` (référencée `[Audio 1]` dans le prompt).
2. Pousse le prompt contenant **la phrase française exacte entre guillemets droits** + une instruction explicite "Lip movement, phoneme timing, pauses and breathing are tightly synchronised with [Audio 1]".
3. Lance Seedance avec `generate_audio=True` (par défaut). Seedance synthétise la voix biaisée par la référence audio (cadence) et par le texte (contenu), et l'embarque dans le mp4.

Sortie unique : `<session>/videos/segment_<N>_final.mp4`. Pas de mux ffmpeg, pas de fichier silencieux intermédiaire.

> Pourquoi garder la phrase française dans le prompt même avec `[Audio 1]` : sans le texte, Seedance hallucine (test empirique : "J'ai 60 ans" devient "Je suis homosexuel" parce que le modèle ré-aligne phonétiquement sur ce qui colle à la lipsync). Le texte est l'ancre, l'audio est la cadence.

> Pourquoi accepter la voix Seedance plutôt que muxer la lo-fi : `generate_audio=True` ré-encode la voix (stéréo, pleine bande passante 0–22 kHz, durée étirée à la durée vidéo). On perd le bandpass + reverb salle de bain. Le compromis assumé : pipeline en un seul appel, lipsync visiblement plus serrée qu'avec l'ancien flux silencieux + mux. La lo-fi reste passée comme `reference_audio` car elle biaise positivement le timbre généré.

## Entrées

- **Script source** : chemin vers un `.md` produit par `ugc-script-writer`. Si l'utilisateur ne précise pas, prends le dernier dossier sous `output/` (le plus récent par date) et son `script.md`.
- **Numéro de segment** : index 1-based (1 = HOOK, 2 = RÉVÉLATION, etc.). Doit correspondre à l'ordre des sections horodatées du markdown — c'est le même index que celui utilisé par `ugc-voice-generator` pour les fichiers `section-NN.mp3`.
- **Persona** : à lire dans l'en-tête du script. Sert à résoudre le `seedance_asset_id`.
- **Voix lo-fi** : `<session>/voice_sections_1.2x_lofi/section-<NN>.mp3` (sortie de `ugc-voice-lofi`). Si absent, signale qu'il faut d'abord faire tourner `ugc-voice-lofi` et stoppe — le pipeline a besoin de la lo-fi comme référence audio.

## Catalogue des personnages

Le catalogue est dans `scripts/characters.json` (catalogue partagé avec `ugc-voice-generator`). Champs utilisés ici : `id`, `gender`, `age`, `description`, `seedance_asset_id`.

Listing :

```bash
jq -r '.characters[] | "\(.id)\t\(.gender)\t\(.age)\t\(.description)\t\(.seedance_asset_id)"' scripts/characters.json
```

### Règle de sélection

Identique à `ugc-voice-generator` :

1. **Genre** : strictement match.
2. **Âge** : différence absolue minimale.
3. **Description** : départage avec le ton dominant du script si pertinent.

Si la persona du script ne match aucun personnage existant (pas de `seedance_asset_id` du bon genre/âge), **signale-le et stoppe**. Demande à l'utilisateur d'enregistrer un nouveau character asset BytePlus (Console → Digital Character) puis d'ajouter la ligne à `characters.json`. Ne défaut pas sur un mauvais personnage — la cohérence visuelle entre plans repose sur ce match.

## Pré-vérifications (silencieuses sauf erreur)

- `scripts/generate_video_seedance.py` existe et est exécutable.
- `scripts/characters.json` existe.
- `ARK_API_KEY` et les variables `CELLAR_*` sont dans `.env`.
- Le segment N a sa voix lo-fi (`voice_sections_1.2x_lofi/section-<NN>.mp3`).
- Le segment N a aussi sa voix non-accélérée (`voice_sections/section-<NN>.mp3`) — utilisé pour calculer la durée Seedance (voix originale + 1 s, clampée 4-15 s).

## Procédure

### 1. Résolution du personnage

Charge `scripts/characters.json`, sélectionne le personnage correspondant à la persona du script (genre strict + âge le plus proche). Récupère son `seedance_asset_id`. Annonce :

`Personnage Seedance : <id> (asset <seedance_asset_id>) — match avec la persona <…>.`

### 2. Référence visuelle produit

Lis `brand/products/catalog.yaml` pour récupérer le `hero_image` (URL HTTPS) du produit principal du segment :

- Si la voix off du segment mentionne un produit (ex : "celui-là, c'est une crème"), prends le packshot du produit cité.
- Si le segment ne mentionne pas de produit (HOOK générique), prends le packshot du produit héros du script (généralement la Crème Apaisante) pour aider la cohérence visuelle entre plans, ou omets le `--image` si la scène est purement personnage seul.

L'URL est passée telle quelle à `--image` — pas besoin d'upload, le packshot Shopify est déjà public.

### 3. Écriture du video_prompt.txt

Crée `<session>/frames/segment_<N>/video_prompt.txt` avec un prompt qui contient :

- **Description du personnage** dérivée de la persona du script : âge, look, tenue, environnement. Recopie tels quels les détails de l'en-tête du script (`pull en cachemire`, `cheveux gris poivre et sel`, `salle de bain classique`, etc.).
- **Indication de plan caméra** : pour un plan ancre selfie, "iPhone front-camera selfie clip — the viewer IS the iPhone's front camera, this is the raw front-camera feed", "vertical 9:16 frame", "fixed framing".
- **POV front-camera (obligatoire, bloc complet, non négociable)** : pour tout plan ancre, le prompt doit contenir un bloc explicite qui interdit (a) que le téléphone soit visible dans le cadre, (b) que la scène soit composée comme un mirror-selfie. **Sans ce bloc, Seedance retombe par défaut sur un cadrage 3e personne ou mirror-selfie** (test empirique : segment 1 du 2026-05-12, dos de l'iPhone avec logo Apple et bumps caméra visibles parce que le prompt disait "holding the phone in selfie mode"). Bloc à recopier tel quel, à adapter uniquement pour le pronom du personnage :

  ```
  POV / framing: this is a true front-camera selfie clip — the viewer's
  eye IS the iPhone's front-facing camera. The frame shows ONLY what
  that front camera captures: the creator's face fills most of the
  vertical frame, with the room visible behind.

  CRITICAL — what is NOT in the frame:
  - the phone itself: NO phone body, NO screen, NO Apple logo, NO rear
    camera bumps, NO phone bezel, NO hand-holding-a-phone composition
    anywhere in the image. The phone IS the camera, it cannot see itself.
  - NO mirror, NO mirror reflection, NO reflective surface showing the
    creator or the phone. This is NOT a mirror-selfie.
  - NO third-person framing, NO over-the-shoulder shot, NO second camera
    filming the creator.

  {{gender pronoun}} arm holding the phone is OUT of frame at all times.
  At most a small portion of {{his/her}} forearm or thumb may clip the
  bottom edge — never the phone body.
  ```

- **Stage direction téléphone (une phrase courte, en complément du bloc POV)** : ajoute une phrase qui précise uniquement la **main + l'angle**, sans répéter "holding the phone" (cette formulation est piégée — voir bloc POV ci-dessus). Exemples valides :
  - Plan ancre selfie main gauche : `Camera angle suggests the phone is held by the creator's left hand at arm's length, slight upward angle toward the face. Hand and phone body remain off-frame.`
  - Plan ancre selfie main droite : `Camera angle suggests the phone is held by the creator's right hand at arm's length, slight downward angle. Hand and phone body remain off-frame.`
  - Plan posé / à distance : `Phone is set on a stable surface about 1 meter away from the creator, at chest height. Not selfie mode. The shot is wider — head and shoulders visible.`
  - Insert / macro produit : `This insert is shot with the iPhone's rear camera, held in one hand close to the product. Not a selfie shot. The creator's face is NOT in this frame.`
  Choisis l'option qui colle à la stage direction du script. Une seule phrase, pas de paragraphe. Pour tout plan ancre selfie, **le bloc POV précédent reste la pièce maîtresse** ; cette phrase n'en est que le complément directionnel (main + angle).
- **Direction tonale** : ton vulnérable / posé / cash, dérivé du contenu et des tags ElevenLabs (`[WHISPER]` → "almost whispered, confidential tone", `[SERIOUS]` → "calm, articulated"). 
- **CRUCIAL — référence `[Audio 1]` pour la cadence labiale** :
  ```
  Lip movement, phoneme timing, pauses and breathing are tightly
  synchronised with [Audio 1] — match every syllable, every micro-pause
  and every breath in [Audio 1].
  ```
  C'est cette instruction qui dit au modèle d'utiliser le `reference_audio` comme guide de cadence (et non comme simple guide de timbre).
- **CRUCIAL — la phrase française exacte du segment entre guillemets droits**, découpée en sous-phrases avec indication des micro-pauses :
  ```
  The character speaks the following three short French phrases:
  "J'ai 60 ans" (small pause),
  "et y a un truc que mon père m'avait jamais raconté" (small pause),
  "personne en fait."
  ```
  Sans cette phrase exacte, **Seedance hallucine** (test empirique sur segment 2 : "J'ai 60 ans" est devenu "Je suis homosexuel"). Le texte du prompt est l'ancre du contenu, l'audio est l'ancre de la cadence — les deux sont nécessaires.
- **Mouvement labial et expression** : "mouth opens and closes softly with each syllable", "eyes locked on the lens", "micro head shifts of 1–3 degrees", "natural breathing between phrases", expressions cohérentes avec le ton ("conspiratorial half-smile", "subtle eyebrow lift").
- **Stabilité** : "fixed framing — no camera movement, no zoom, no pan, no tilt, no rotation", "background completely still", "lighting stable across the whole clip with no flicker".
- **Look UGC — home-made, mal éclairé, NOT cinematic (bloc obligatoire)** : sans ce bloc, Seedance retombe par défaut sur un rendu trop propre — ring-light, peau lissée, bokeh cinéma — qui tue la crédibilité UGC. Bloc à recopier (adapter le décor) :

  ```
  Look: raw amateur iPhone front-camera footage in an ordinary room.
  Home-made, casual, NOT cinematic, NOT professional, NOT a beauty shot.

  Lighting: single uneven source (one ceiling bulb or one window).
  Slightly off white balance, faint green-yellow tungsten/fluorescent
  cast. Visible top-light shadow under the eyes, nose or chin. Face
  brighter than the background, which sits slightly underexposed.

  Sensor: soft focus, compressed dynamic range, noise in shadows,
  barrel distortion at the edges, faint chromatic aberration, imperfect
  auto-white-balance, low-bitrate mushy skin texture.

  NOT: no ring-light catchlight, no softbox, no fill or rim light, no
  color grading, no cinematic LUT, no shallow depth of field, no creamy
  bokeh, no beauty-camera skin smoothing, no studio backdrop.
  ```
- **Anti-watermark** : "Absolutely no on-screen text, captions, subtitles, or watermarks visible in the image."

Modèle de référence : `output/2026-05-08-le-3eme/frames/segment_2/video_prompt_hybrid_test.txt`.

Le prompt est en **anglais** (Seedance est plus stable en anglais), **mais les phrases parlées restent en français pur** entre guillemets droits — pas de paraphrase anglaise, sinon le modèle peut prononcer le mot anglais à la place.

### 4. Génération de la vidéo finale

Une seule commande :

```bash
set -a; source .env; set +a
./scripts/generate_video_seedance.py <session_dir> <N> \
  --character-asset-id <seedance_asset_id> \
  --image <hero_image_url>
```

- `--character-asset-id` est obligatoire (vient du catalogue).
- `--image` peut être omis si pas de produit pertinent.
- `--audio` est facultatif : le script auto-attache `voice_sections_1.2x_lofi/section-<NN>.mp3` si présent. Le passer manuellement permet de pointer vers un autre fichier (ex. test d'une voix alternative).
- `generate_audio=True` est le défaut. Pour un test silencieux (ex. comparer avec un mux manuel), passer `--no-generate-audio`.
- Le script appelle `scripts/storage.sh` pour uploader d'éventuels fichiers locaux passés en `--image` ou `--audio`. `storage.sh` exporte déjà `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` pour Cellar (sans ça, `MissingContentLength`).

Sortie : `<session_dir>/videos/segment_<N>_final.mp4` (vidéo + audio synthétisée par Seedance, 5 ou 10 s selon la durée audio du segment).

## Sortie attendue à l'utilisateur

Réponse courte qui contient, dans l'ordre :

1. Personnage Seedance choisi (1 ligne).
2. Chemin de la vidéo finale (`videos/segment_<N>_final.mp4`).
3. Durée et taille du fichier (extraites avec `ffprobe` + `ls -lh`).
4. Si la lipsync semble dériver visiblement, suggérer une piste corrective (raffinage de la phrase exacte + des `(small pause)` dans le prompt, ou découpage en deux segments). Pas de diagnostic gratuit si la lipsync paraît correcte.

Pas de commentaire sur le déroulé technique (génération réussie, fichiers écrits) — c'est implicite.

## Override courants

- **Plusieurs segments** : génère segment par segment, en relançant le skill une fois par N. Chaque segment a son propre `video_prompt.txt` à raffiner. Pas de mode batch implicite — c'est volontaire, la qualité de la lipsync se gagne plan par plan.
- **Régénération d'un segment** : supprime `videos/segment_<N>_final.mp4`, ajuste le prompt, relance. Ou utilise un `--output-name` différent (ex : `segment_<N>_v2.mp4`) pour comparer.
- **Variante silencieuse** : `--no-generate-audio` pour récupérer un mp4 sans audio (utile pour A/B avec un mux manuel d'une autre piste, ou pour debug).
- **Durée forcée** : `--duration 5` ou `--duration 10` pour outrepasser le calcul auto basé sur la durée du fichier voice_sections_1.2x.
- **Watermark off** : `--no-watermark` (par défaut le watermark Seedance est laissé activé).
- **Personnage forcé** : si l'utilisateur passe un `seedance_asset_id` explicite (ex : pour tester un nouvel asset non encore inscrit dans `characters.json`), skip la sélection auto.

## Anti-patterns à éviter

- **Lancer Seedance sans `video_prompt.txt`** : le prompt par défaut intégré au script Python est minimal. Toujours écrire un prompt spécifique avec la phrase française exacte + l'instruction `[Audio 1]`.
- **Omettre la phrase française littérale** dans le prompt en pensant que `[Audio 1]` suffit pour driver le texte : non. Test empirique : sans le texte, Seedance hallucine (un "J'ai 60 ans" devient "Je suis homosexuel" parce que le modèle ré-aligne sur ce qui colle phonétiquement à la lipsync). Le texte du prompt est l'ancre du contenu.
- **Faire confiance à la lipsync sur des phrases longues** : Seedance gère bien 1 à 3 phrases courtes par segment de 5 secondes. Si le segment dépasse 8-9 mots de voix off, scinder en deux plans vidéo distincts ou passer en segment 10 secondes.
- **Mélanger anglais et français dans la voix off du prompt** : les phrases parlées doivent rester en français pur, sans paraphrase anglaise — sinon Seedance peut prononcer un mot anglais à la place.
- **Oublier le packshot quand le segment montre le produit** : sans `--image`, le tube de crème dans la main du personnage sera générique. Avec le packshot, Seedance reproduit raisonnablement le design réel.
- **Défaut sur un mauvais personnage** : si le genre/âge ne match pas, ne génère pas avec un personnage approximatif. Stoppe et fais ajouter le bon character asset.
- **Téléphone visible dans le cadre / mirror-selfie** : tout prompt selfie doit contenir le bloc "POV front-camera" complet (téléphone OUT of frame + interdiction explicite mirror-selfie / 3e personne / dos d'iPhone visible). Toute formulation type `UGC creator is holding the phone in selfie mode` est piégée — Seedance l'interprète comme un cadrage 3e personne ou mirror-selfie (logo Apple + bumps caméra visibles au dos du téléphone). Précédent connu : segment 1 du `output/2026-05-12-le-mot-interdit/`. Toujours vérifier la frame 0 du rendu : si on voit le dos d'un iPhone, regénérer avec le bloc POV au-dessus.
- **Rendu trop léché / "beauty-camera"** : sans bloc "Look UGC" explicite, Seedance produit un rendu de pub cosmétique. Symptômes frame 0 : catchlight circulaire dans l'œil (= ring-light), peau sans grain, bokeh cinéma, balance des blancs parfaite. Correctif : insérer le bloc "Look UGC" complet et ré-générer.

## Erreurs possibles

- **`ARK_API_KEY not set`** : ajouter dans `.env`.
- **`storage.sh ... failed (exit 254)`** : aws-cli 2.34+ retourne 254 sur HeadObject 404 (clé absente). La version actuelle de `storage.sh` gère ce cas, mais si l'erreur réapparaît, vérifier que la fonction `remote_size_etag` enveloppe bien l'appel `aws head-object` dans un `if ... fi`.
- **`MissingContentLength`** : Cellar refuse les bodies en streaming/trailer checksum. La version actuelle de `storage.sh` exporte `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` et `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required` pour ça — vérifier que ces lignes existent.
- **HTTP 401 / 403 Ark** : clé invalide ou pas d'accès au modèle.
- **Task `failed` sur Ark** : message d'erreur dans la réponse JSON. Souvent prompt trop long, langue mélangée, ou character asset invalide.
- **Lipsync clairement décalée** : raffiner les `(small pause)` dans le prompt, ou découper le segment en deux. Si le segment est très court (< 2 s d'audio), la lipsync peut être imprécise par construction du modèle.
- **Texte halluciné** (le personnage dit autre chose que la phrase prévue) : la phrase française exacte n'est pas dans le prompt, ou est paraphrasée en anglais. La remettre telle quelle entre guillemets droits.
- **Personnage qui ne ressemble pas à l'asset enregistré** : vérifier que le `seedance_asset_id` est valide (testable dans la BytePlus Ark Console) et que la référence visuelle utilisée pour créer l'asset était suffisamment précise.
- **Dos d'iPhone visible (logo Apple, bumps caméra) dans le rendu** : le prompt ne contient pas le bloc "POV front-camera / phone OUT of frame / no mirror-selfie" explicite. Insérer le bloc complet documenté dans la section "POV front-camera (obligatoire)" ci-dessus, supprimer toute formulation "creator is holding the phone" qui suggère un cadrage 3e personne, puis ré-générer avec `--force`.
