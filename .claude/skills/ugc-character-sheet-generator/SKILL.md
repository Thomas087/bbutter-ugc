---
name: ugc-character-sheet-generator
description: >-
  Génère un character sheet (fiche de continuité visuelle) à partir d'un script UGC Butt Butter, montrant la persona du script en 5 angles standards (face, 3/4 gauche, profil gauche, 3/4 dos, dos) sur une seule image landscape sans aucun texte. Lit la persona, la tenue et le décor dans l'en-tête du script (sortie de `ugc-script-writer`), construit un prompt photoréaliste, puis appelle `gpt-image-2` (avec fallback `gpt-image-1`) via `scripts/generate_image.sh --no-crop`. Indispensable pour garantir la cohérence du personnage entre plans, briefer un acteur ou un illustrateur, ou servir de référence à un outil image-to-video. Utilise ce skill dès que l'utilisateur demande "character sheet", "fiche personnage", "model sheet", "fiche de continuité", "visualiser la persona", "image de la persona", "rendu du personnage", ou veut voir à quoi ressemble la persona d'un script déjà écrit. Utilise-le aussi quand l'utilisateur veut une référence visuelle de la persona pour briefer une production.
---

# UGC Character Sheet Generator — Butt Butter

Ce skill prend la persona d'un script UGC Butt Butter et produit une **fiche de continuité visuelle** : une seule image landscape qui montre la même personne sous 5 angles standards, dans la même tenue, sous la même lumière. Aucun texte dans l'image.

## Pourquoi un character sheet

- **Cohérence** : si plusieurs plans de la vidéo sont générés (image-to-video, packshots avec figurant, illustration), tu pars d'une référence unique. Sinon le personnage dérive (cheveux, tenue, âge apparent).
- **Brief acteur / casting** : sert de moodboard concret quand l'équipe production cherche le bon visage. Plus parlant qu'une ligne de persona.
- **Référence pour outil image-to-video** : la plupart des outils (Runway, Kling, Veo) acceptent une image de référence. Un character sheet donne un meilleur ancrage qu'une seule pose.

## Entrées

- **Script source** : chemin vers un `.md` produit par `ugc-script-writer`. Si l'utilisateur ne précise pas, prends le dernier dossier sous `output/` (le plus récent par date) et son `script.md`.
- **Persona** : à lire dans le tableau d'en-tête du script :
  - `| **Persona** | … |` — prénom, âge, genre, profil
  - `| **Tenue** | … |` — la tenue (souvent avec alternative type "peignoir éponge OU polo + pull"). **Choisis-en une seule** et utilise-la dans les 5 angles.
  - `| **Décor** | … |` — utile uniquement comme contexte. Le character sheet lui-même est sur fond studio neutre (gris clair), pas sur le décor du script.
- **Override utilisateur** : si l'utilisateur précise une tenue différente, plus d'angles, ou des traits spécifiques (lunettes, barbe, etc.), suis ce qu'il dit plutôt que d'inventer.

## Procédure

### 1. Pré-vérifications (silencieuses, ne pas commenter sauf erreur)

- `OPENAI_API_KEY` est dans `.env` à la racine du repo. Si absent, demande à l'utilisateur de l'ajouter, ne tente pas de deviner.
- `scripts/generate_image.sh` existe et accepte le flag `--no-crop` (`grep -q -- '--no-crop' scripts/generate_image.sh`). Le flag est nécessaire car le crop par défaut force du 9:16, ce qui amputerait les angles latéraux du sheet.
- Le dossier de sortie cible (`<script_dir>/character_sheet/`) peut être créé.

### 2. Choix de la tenue et étoffement de la persona

La persona du script est volontairement minimaliste (ex : "Bernard, 58 ans, fin de carrière, ancien commercial, vélo le dimanche"). Pour générer une image cohérente, tu dois **étoffer plausiblement** :

- **Choisir une tenue parmi les options** de la ligne `| **Tenue** | … |`. Préfère la version "habillée" (polo + pull) plutôt que peignoir, sauf demande explicite — un peignoir n'aide pas le casting et expose des angles inutiles. Annonce ton choix à l'utilisateur en une ligne.
- **Inférer les traits manquants** sans contredire la persona :
  - Carnation, cheveux, yeux : cohérents avec le profil (un sénior ancien commercial = cheveux poivre-sel courts, peau légèrement marquée, etc.)
  - Carrure, posture : cohérents avec l'activité mentionnée (vélo le dimanche → silhouette sèche-moyenne, posture droite)
  - Pas d'accessoires non mentionnés (lunettes, montre, casquette) sauf si la persona les implique.
- **Ne jamais inventer d'élément qui contredit la persona** (ex : barbe sur une persona décrite "fraîchement rasé").

### 3. Construire le prompt

Utilise le gabarit ci-dessous. Remplis les slots `{{...}}` avec les détails concrets, en anglais (gpt-image-2 répond mieux aux prompts en anglais, même pour des sujets francophones — pas de difference visuelle).

```
Character reference sheet, photographic style, neutral light grey seamless studio background, soft natural daylight from the left, no props, no furniture, full character isolated.

Subject: {{prénom}}, a {{âge}}-year-old {{nationalité, ex: French}} {{homme/femme}}, {{profil court tiré du script}}. Build: {{carrure}}. Skin: {{carnation + détails type rides, taches, etc.}}. Hair: {{coupe, couleur, longueur}}. Eyes: {{couleur, expression}}. {{traits distinctifs}}. {{expression faciale: smile/neutral/etc.}}.

Outfit: {{tenue détaillée — haut, bas, chaussures, accessoires}}. Same outfit in every view — this is a continuity reference.

Layout: a single horizontal sheet showing the SAME person five times, side by side, evenly spaced, all standing, full body visible from head to feet, identical scale, identical lighting, identical outfit, identical hairstyle:
1. Front view, arms relaxed along the body.
2. Three-quarter view from the left, slight turn.
3. Pure left side profile.
4. Three-quarter view from the back-left.
5. Back view.

Photo-realistic, sharp focus on face, even exposure, no shadows on the background, no vignette, no film grain. The five figures stand on the same invisible ground line. Studio character-sheet aesthetic used by film costume departments.

ABSOLUTELY NO TEXT, no labels, no numbers, no captions, no logos, no watermarks, no arrows, no annotations of any kind anywhere in the image.
```

**Le bloc final (NO TEXT) n'est pas négociable.** Sans cette répétition de négations, gpt-image-2 ajoute spontanément des étiquettes "Front", "Side", "Back" en haut des figures. Ne raccourcis pas ce paragraphe.

### 4. Appel API via `generate_image.sh --no-crop`

```bash
set -a; source .env; set +a
OUT_DIR=<script_dir>/character_sheet
mkdir -p "$OUT_DIR"

# Écris le prompt dans un fichier pour pouvoir le réutiliser / itérer
cat > "$OUT_DIR/prompt.txt" <<'PROMPT'
<le prompt rempli ci-dessus>
PROMPT

OPENAI_IMAGE_QUALITY=high \
  ./scripts/generate_image.sh --no-crop \
    "$OUT_DIR/<persona_slug>_character_sheet.png" \
    "$(cat "$OUT_DIR/prompt.txt")" \
    1536x1024
```

Notes :
- **`OPENAI_IMAGE_QUALITY=high`** est essentiel. En `low` (défaut), les visages dérivent entre les 5 angles et le résultat n'est plus utilisable comme référence de continuité. Le surcoût se justifie largement (1 image, 1 fois).
- **`1536x1024`** : c'est le seul format landscape supporté par gpt-image-2. Permet de loger 5 figures en pied côte à côte.
- **`--no-crop`** : sans ce flag, le post-process recadre à 9:16 (864x1536) et coupe les angles latéraux. Toujours requis pour un character sheet.
- **`<persona_slug>`** : prénom en minuscules sans accent (ex. `bernard`, `lea`, `marie_claire`).

### 5. Sauvegarde du prompt à côté de l'image

Toujours laisser `prompt.txt` à côté du PNG. Permet à l'utilisateur de :
- Itérer en modifiant uniquement les slots qu'il veut changer
- Comprendre pourquoi le rendu est ce qu'il est
- Reproduire à l'identique plus tard

## Sortie attendue à l'utilisateur

Une réponse courte qui contient, dans l'ordre :

1. La tenue choisie (1 ligne, avec justification courte si l'utilisateur n'a pas tranché)
2. Le chemin du PNG généré et de son `prompt.txt`
3. L'image elle-même (lue via `Read` sur le PNG, pour que l'utilisateur la voie inline)
4. Une ligne d'invitation à itérer ("Si tu veux changer la tenue, ajouter des lunettes, ou passer en 3 angles uniquement, dis-moi.")

Pas de commentaire sur le déroulé technique (call API, base64, sauvegarde). C'est implicite.

## Overrides courants

- **Vertical 9:16** : si l'utilisateur veut une fiche au format Reels (pour la garder dans le même dossier que les plans verticaux), génère 3 angles seulement (face, 3/4, dos) en `1024x1536`, et **enlève** `--no-crop` pour laisser le crop 864x1536. Ajuste le bloc `Layout:` pour ne demander que 3 figures empilées verticalement.
- **Plus / moins d'angles** : ajuste la liste numérotée du bloc `Layout:`. Garde toujours au moins face + profil + dos pour que la fiche reste utile.
- **Expressions multiples** : si l'utilisateur veut "même personne, 3 expressions" plutôt que "même personne, 5 angles", remplace le bloc `Layout:` par une variante "Three head-and-shoulders shots, identical lighting, identical outfit: neutral, slight smile, concerned." Documente le choix dans `prompt.txt`.
- **Tenue alternative** : si l'utilisateur veut tester deux tenues (ex. "même persona en peignoir ET en polo"), génère deux PNG séparés avec deux `prompt.txt`, suffixés `_outfit_polo.png` et `_outfit_peignoir.png`. Ne tente pas de mettre les deux tenues dans une seule image — gpt-image-2 mélange les vêtements entre figures.
- **Re-rendu** : si le rendu actuel a un défaut (un angle est cassé, le visage dérive entre figures), **ne touche pas au prompt** — relance simplement la même commande. gpt-image-2 a une variance non négligeable entre runs ; un second tirage corrige souvent. Si après 2 essais le défaut persiste, alors itère le prompt.
- **Référence à partir d'une photo** : si l'utilisateur fournit une photo de la personne réelle (acteur déjà casté), utilise `--ref <chemin>` en plus de `--no-crop` pour passer la photo en référence à `gpt-image-2` (route `/images/edits`). Ajuste alors le prompt pour décrire la persona de façon plus minimale (le modèle prend les traits depuis la ref).

## Erreurs possibles

- **`OPENAI_API_KEY not set`** : la clé n'est pas dans `.env`. Demande à l'utilisateur de l'ajouter.
- **HTTP 403 "must be verified"** : le compte OpenAI n'est pas vérifié pour `gpt-image-2`. `generate_image.sh` retombe automatiquement sur `gpt-image-1` — la qualité visage est plus basse mais utilisable. Mentionne le fallback à l'utilisateur.
- **HTTP 400 "invalid size"** : la taille passée n'est pas dans `{1024x1024, 1024x1536, 1536x1024, auto}`. Repasse à `1536x1024`.
- **Texte présent dans l'image malgré le prompt** : le bloc `ABSOLUTELY NO TEXT` a été raccourci ou modifié. Vérifie que les négations multiples sont bien présentes. Si elles le sont déjà et que le texte revient, relance le run (variance modèle).
- **Visage dérive entre les 5 figures** : qualité trop basse. Relance avec `OPENAI_IMAGE_QUALITY=high` (vérifier que la variable est bien exportée pour le sous-process).
- **Image cropée à 864x1536 alors qu'on voulait du landscape** : le flag `--no-crop` a été oublié. Toujours nécessaire pour le format landscape.
