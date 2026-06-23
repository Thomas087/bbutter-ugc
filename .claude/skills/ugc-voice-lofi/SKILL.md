---
name: ugc-voice-lofi
description: >-
  Transforme la voix off d'un script UGC Butt Butter en version "lo-fi téléphone + reverb salle de bain". Lance par défaut sur un dossier de session UGC contenant `voice_sections/` et/ou `voice_sections_1.2x/` (sortie de `ugc-voice-generator`) et produit en parallèle `voice_sections_lofi/` et `voice_sections_1.2x_lofi/`. Accepte aussi un dossier plat de MP3 (sortie `<input>_lofi/`). Pipeline figé : ffmpeg bandpass 200–5000 Hz + compression légère (effet micro iPhone bon marché), puis sox `reverb 45 50 40 100 5 -3` (reverb algorithmique, petite pièce carrelée). Utilise ce skill dès que l'utilisateur demande "rends la voix lo-fi", "effet téléphone", "comme un iPhone bon marché", "voix UGC dégueu", "ajoute de l'écho / du reverb / une salle de bain", "voix qui sonne comme enregistrée dans un AirBnB", "fais sonner la voix moins clean", ou veut donner un rendu "amateur" / "vrai UGC" à une voix off ElevenLabs trop propre. Utilise-le aussi quand l'utilisateur veut traiter en lot tous les segments audio d'un script.
---

# UGC Voice Lo-Fi — Butt Butter

Ce skill prend un dossier de MP3 voix off (sortie de `ugc-voice-generator`) et applique un effet lo-fi + reverb réaliste pour casser le côté trop propre d'ElevenLabs et donner le rendu "vrai UGC tourné au téléphone dans une salle de bain".

## Pourquoi cet effet

ElevenLabs en `eleven_v3` sort une voix studio, sans bruit, sans pièce. Sur un format UGC court (TikTok / Reels), ce trop-de-qualité sonne *fake*. L'audience attend une voix prise au téléphone, dans une vraie pièce. On ajoute donc :

- **Bandpass 200–5000 Hz** : c'est la bande passante d'un micro de smartphone bon marché. Coupe les sub-basses et les aigus brillants.
- **Compression légère** (2.5:1 @ -20dB) : aplatit la dynamique comme le ferait l'AGC d'un téléphone.
- **Reverb algorithmique sox** (`reverb 45 50 40 100 5 -3`) : petite pièce carrelée, queue dense et naturelle. Beaucoup plus crédible que des `aecho` discrets.

## Quand l'utiliser

- L'utilisateur a généré sa voix off via `ugc-voice-generator` et trouve le rendu "trop clean" / "trop studio" / "trop AI".
- L'utilisateur demande un effet "téléphone", "iPhone bon marché", "salle de bain", "AirBnB", "écho", "reverb", "lo-fi".
- L'utilisateur veut traiter en lot tous les segments d'un script d'un coup.

## Quand NE PAS l'utiliser

- Si l'utilisateur veut tout autre chose qu'une "petite pièce carrelée" (grande salle, cathédrale, distorsion lourde, effet radio, etc.) : les paramètres sont figés sur "petite salle de bain". Pour autre chose, ajuster le script à la main, ne pas appeler ce skill.
- Si l'utilisateur veut traiter UN seul fichier vs un dossier : le script attend un dossier. Pour un fichier unique, mettre temporairement le fichier dans un dossier dédié.

## Procédure

### 1. Pré-vérifications (silencieuses sauf erreur)

- `scripts/apply_lofi.sh` existe et est exécutable.
- `ffmpeg` et `sox` sont installés. Sinon : `brew install ffmpeg sox`.
- Le dossier d'entrée contient des `*.mp3`.

### 2. Identifier le dossier source

- Si l'utilisateur précise un chemin, l'utiliser tel quel.
- Sinon, par défaut, prendre la **session** la plus récente sous `output/` (le dossier qui contient `voice_sections/` et `voice_sections_1.2x/`). Annoncer le choix en une ligne avant de lancer.

### 3. Lancer le traitement

```bash
./scripts/apply_lofi.sh --in <session_dir>
```

Mode session (par défaut sur un dossier `output/<date>-<slug>/`) : détecte les sous-dossiers `voice_sections/` et `voice_sections_1.2x/`, les traite tous les deux, et écrit `voice_sections_lofi/` + `voice_sections_1.2x_lofi/` à côté.

Mode flat : si `--in` pointe directement sur un dossier de MP3 (sans les sous-dossiers attendus), sortie unique `<input>_lofi/`.

Options :
- `--out <dir>` : force la destination (uniquement en mode flat — erreur en mode session).
- `--bitrate 96k` / `192k` : changer le bitrate MP3 (défaut `128k`).

### 4. Sortie attendue à l'utilisateur

Une réponse courte :

1. Le dossier source utilisé (1 ligne, si auto-détecté).
2. Le dossier de sortie (chemin complet).
3. Optionnellement : lancer `afplay <out_dir>/section-01.mp3` en background pour que l'utilisateur entende le rendu immédiatement.

Pas de blabla sur le déroulé technique ni sur la chaîne d'effets — c'est implicite.

## Override courants

- **Effet trop fort / trop faible** : le skill ne tune pas. Si l'utilisateur trouve l'effet exagéré ou pas assez marqué, sortir du skill et ajuster à la main `scripts/apply_lofi.sh` (paramètres `highpass`, `lowpass`, et `reverb 45 50 40 …`). Ne pas baker un mode "soft" / "hard" sans demande explicite et persistante.
- **Traiter un seul des deux** : passer explicitement `--in <chemin>/voice_sections` ou `--in <chemin>/voice_sections_1.2x` pour ne traiter que l'un des deux. Le mode flat s'active et la sortie est `<chemin>/voice_sections_lofi/` ou `<chemin>/voice_sections_1.2x_lofi/`.

## Erreurs possibles

- **`sox: command not found`** : `brew install sox`, puis relancer.
- **`no .mp3 files in <dir>`** : mauvais dossier ; vérifier le chemin et la sortie de `ugc-voice-generator`.
- **Sortie qui clippe** : peu probable avec `volume=1.1` mais possible sur voix très fortes. Réduire `volume` dans le script (ex. `volume=1.0`).
