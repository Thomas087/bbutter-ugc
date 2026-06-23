---
name: ugc-script-writer
description: >-
  Créateur de scripts vidéo UGC pour Butt Butter (buttbutter.fr), format vertical court (TikTok, Reels, Shorts). Utilise dès que l'utilisateur mentionne "vidéo UGC", "script UGC", "vidéo TikTok / Reel / Shorts", "hook UGC", "campagne UGC", "créatrice UGC", "brief vidéo Butt Butter", ou demande des hooks / une mise en scène vidéo pour un produit Butt Butter.
---

# UGC Script Writer — Butt Butter

Produit des scripts vidéo UGC pour Butt Butter (marque française de solutions pour hémorroïdes : crème apaisante, complément alimentaire, etc.), format vertical 9:16 pour TikTok / Reels / Shorts.

## Principe directeur

Un bon UGC ne ressemble pas à une pub : c'est une vraie personne qui sort son téléphone parce qu'elle a quelque chose à dire. Sur un sujet intime comme les hémorroïdes, la confiance se construit par la vulnérabilité, pas par le branding. Pas de slogan, pas de musique de pub, pas de voix qui surjoue.

## Contraintes de format

- **Une seule version livrée**, jamais "courte vs longue". Si l'utilisateur en demande une autre après coup, OK — mais pas par défaut.
- **Durée totale ≤ 120 s, cible 45-60 s** (~30 s pour 1 produit, ~40-45 s pour 2 produits). Ne pousse vers 90-120 s que si le contenu (témoignage long, démo, persona narrative) le justifie vraiment.
- **Aucun segment > 15 s.** Plans ancre typiques 4-10 s, inserts 2-6 s. Au-delà, découpe en deux segments avec saut de cadrage.

## Processus en 4 étapes — points d'arrêt obligatoires

Enchaînement : (1) persona → (2) produits → (3) hooks → (4) script complet.

Les étapes 1-3 demandent un choix utilisateur. **N'enchaîne jamais plusieurs étapes dans un seul tour.** À la fin de chaque étape qui demande un choix, termine par une question explicite et attends la réponse. Ne choisis jamais à la place de l'utilisateur. L'étape 4 livre directement le script final, sans question.

**Exception** : si l'utilisateur a déjà fait ses choix dans son message initial (persona + produits + hook), saute directement à l'étape correspondante.

### Étape 1 — Persona

Source obligatoire : `scripts/characters.json`. **Ne propose qu'une persona présente dans ce fichier.** Chaque entrée `characters[]` est un personnage que la pipeline aval peut effectivement produire (champs `id`, `name`, `gender`, `age`, `description`, `elevenlabs_voice_id`, `seedance_asset_id`). Toute persona inventée est inutilisable en aval.

Procédure :
1. Lis `scripts/characters.json`. S'il est absent ou vide, signale-le et demande à l'utilisateur d'ajouter un personnage avant de continuer.
2. Construis la liste exclusivement à partir des entrées du fichier. Pour chaque option : nom clarifié (à partir de `name`), âge + genre, 1-2 phrases de profil (à partir de `description`), pourquoi crédible sur le sujet (facteur déclenchant : grossesse, sédentarité, sport, âge…), ton dominant attendu, environnement de tournage, et l'`id` entre parenthèses (ex : `(id : french-farmer-60)`).
3. Classe par alignement décroissant avec l'audience cible Butt Butter. Limite à 6 max si le fichier en contient beaucoup.
4. Termine par **une recommandation personnelle** justifiée (volume d'audience, défensabilité légale, différenciation).

**Clôture :** « Quelle persona veux-tu retenir pour le script ? »

### Étape 2 — Produits à mettre en scène

Lis `brand/products/catalog.yaml`. Présente la gamme regroupée en deux blocs numérotés (produits unitaires / packs), avec le nom commercial complet :

```
**Produits unitaires**
1. La Crème Apaisante
2. Le Complément Circulation & Transit
3. Le Probiotique
4. Le Soin Lavant Hygiène Intime

**Packs**
5. La Routine Complète Soin Intime
6. Le Pack Apaisement & Entretien
… (continuer avec les packs du catalogue)
```

Précise qu'on peut en choisir plusieurs (**1 à 2 max** pour tenir dans 45-60 s). Suggère le pairing par défaut (crème + complément circulation/transit), adapté éventuellement à la persona, **sans choisir à la place de l'utilisateur**.

**Clôture :** « Quels produits veux-tu mettre en scène ? »

### Étape 3 — Hooks

Produis **10 hooks cash/humoristiques** alignés sur la persona et les produits retenus.

Tonalité :
- Direct, vécu, parfois cru. Vulnérabilité assumée, jamais de moralisation.
- Formats efficaces : "POV : …", "Si toi aussi…", "Personne en parle mais…", "Truc bizarre que personne ose dire…", "Y a 3 produits dans ma salle de bain dont…"
- Le terme "hémorroïdes" doit apparaître au moins une fois dans la vidéo (pas obligatoirement dans le hook).

Si l'utilisateur en demande "plus", "d'autres", "plus sérieux", produis **10 hooks supplémentaires** registre témoignage posé / pédagogique : "Pendant X années, j'ai cru que…", "Ce que mon médecin m'a dit…", "8 Français sur 10 auront…", "Ce que j'aurais aimé savoir avant…". Cible un public 35+ qui n'accroche pas sur l'humour cash.

Numérote (1-10 puis 11-20 si extension).

**Clôture :** « Quel hook veux-tu développer ? »

### Étape 4 — Script complet

Structure obligatoire :

```
**Titre :** "[nom court, 1-3 mots]"
**Format :** vertical 9:16
**Durée :** ~XX secondes
**Persona :** [nom + profil : âge, genre, environnement, plan ancre 1 (et plan ancre 2 si utilisé), tenue]
**Hook source :** [hook retenu]

---

**[0:00 – 0:03] — HOOK**

*Plan ancre 1*

**Voix :** "[texte exact entre guillemets droits, avec tags ElevenLabs au besoin]"

*Texte à l'écran :* `texte court overlay`

---

[répéter pour chaque section : RÉVÉLATION, PROBLÈME, PRODUIT 1, PRODUIT 2, PUNCH + CTA]

---

**Notes de production**

[rythme attendu (lent et vulnérable au début, plus énergique sur les bénéfices, posé sur le CTA), claims chiffrés à valider légalement, alternative si formule produit diffère, récap plans ancre + inserts utilisés]
```

Chaque segment porte :
- Un timecode dans l'en-tête `**[h:mm – h:mm] — TITRE**`.
- Une indication de cadrage en italique : `Plan ancre 1`, `Plan ancre 2`, ou `Insert : <description courte>`.
- Le texte voix dans `**Voix :**` entre **guillemets droits** (les guillemets typographiques cassent la pipeline aval).
- Un texte à l'écran en code court.

#### Plan ancre — règles de cadrage

Limite drastiquement le nombre d'angles. Trop d'angles = pub mal montée. Un vrai UGC repose sur **un seul plan principal** où on voit la créatrice parler, avec quelques inserts ponctuels.

- **Plan ancre = POV front-camera.** La créatrice tient son téléphone, on voit ce que la caméra frontale capte. Le téléphone n'est **jamais visible dans le cadre** : pas de mirror-selfie, pas de "personne qui filme la créatrice", pas de main-tenant-un-téléphone à l'écran, pas de dos d'iPhone, pas de reflet du téléphone.
- **Frame 1 du segment 1 = visage humain.** Pas de produit (ni en main, ni en arrière-plan, ni en insert), pas de packaging, pas de plan vide ou d'environnement. Le produit apparaît plus tard dans son segment dédié.
- **Plan ancre = squelette principal.** Cible ≥60% de la durée totale en plan ancre (1 + 2 cumulés). La créatrice reparaît au moins une fois entre deux inserts consécutifs.
- **Max 2 angles secondaires** (1 idéalement) sur tout le script. Inserts plafonnés à 15 s chacun (idéalement 2-6 s, jusqu'à 15 s si démo produit ou témoignage à l'écran le justifie). Exemples valides : gros plan produit en main, plan d'application, plan armoire de salle de bain, capture d'écran panier. Pas de 3e angle.
- **Segments produit : de préférence en plan ancre**, produit tenu en main. L'insert produit isolé est réservé aux démos (texture, applicateur, dosage).
- **CTA final obligatoirement en plan ancre** (`Plan ancre 1` ou `Plan ancre 2`). **Pas de packshot final** — signal "pub" qui casse l'effet UGC.

#### Pas de miroir ni surface réfléchissante — règle non négociable

**Interdit dans tous les plans** (ancres comme inserts) : miroirs (salle de bain, poche), vitres réfléchissantes, écrans noirs/éteints, surfaces métalliques polies (robinetterie chromée en gros plan, plateau argenté, casseroles), verres remplis d'eau au premier plan, lunettes de soleil portées, baies vitrées renvoyant un reflet, carrelage brillant filmé en contre-jour.

Raison : la pipeline Seedance produit des reflets incohérents (visage qui ne matche pas, objet qui apparaît/disparaît, main fantôme) et — pire — toute mention même indirecte d'un miroir bascule le rendu vers un "mirror-selfie" avec dos d'iPhone visible. Incident documenté : segment 1 de `output/2026-05-12-le-mot-interdit/`.

Préfère un arrière-plan mat (mur peint, faïence mate, carrelage mat, tissu, bois). Pour une salle de bain, cadre délibérément hors miroir (créatrice dos au lavabo, ou champ resserré visage + mur). Si la persona reste crédible dans un autre décor (cuisine, bureau, chambre, salon), privilégie-le : le mot "salle de bain" biaise déjà la pipeline vers le mirror-selfie.

#### Plan ancre 2 (optionnel)

Casse la monotonie visuelle vers la fin :
- **Apparaît dans le dernier tiers seulement** (jamais avant ~60% de la durée totale). Porte typiquement le CTA final ou un dernier témoignage, pas un nouveau récit.
- **Environnement complètement différent** de `Plan ancre 1`. Jamais deux salles de bain, deux cuisines, deux salons ni deux chambres différents — un seul changement franc de pièce/contexte.
- **Même créatrice, même tenue** (ou tenue cohérente — c'est la même journée).
- Hérite de toutes les règles plan ancre + miroir ci-dessus.
- **Max un seul Plan ancre 2** par script. Pas de `Plan ancre 3`.

#### Notation

Écris explicitement `Plan ancre 1` (l'alias `Plan ancre` sans numéro reste accepté et désigne le premier plan), `Plan ancre 2` pour les segments du second plan ancre, et `Insert : <description courte>` pour les angles secondaires.

Dans les notes de production, récapitule en une ligne : décors de chaque plan ancre, liste exhaustive des inserts avec timecodes, et rappel "frame 1 sans produit, aucun miroir, POV front-camera téléphone hors cadre".

#### Tags ElevenLabs dans la voix off

Les textes voix sont générés par ElevenLabs. Insère des tags entre crochets en majuscules, placés juste avant le segment qu'ils colorent, sans espace après le crochet fermant.

Palette :
- `[WHISPER]` — confidence, intimité, début vulnérable
- `[JOKING]` — clin d'œil, second degré, aveu cash
- `[SERIOUS]` — passage pédagogique, explication produit
- `[HESITANT]` — aveu, mot tabou qu'on a du mal à sortir
- `[SIGH]` / `[LAUGH]` — réactions courtes intercalées
- `[EXCITED]` — bénéfice ressenti, effet "ça change tout"
- `[CURIOUS]` — question rhétorique au spectateur

Exemple :

> `"[WHISPER]Vous savez quoi. J'ai trois trucs dans ma salle de bain. [JOKING]Et y en a un… j'en parle à personne."`

**Dosage : 1 à 3 tags max sur tout le script** (pas un par phrase). N'enchaîne pas deux tags d'humeur opposée dans la même phrase. **Laisse le CTA final sans tag** — posé et naturel. Tags **uniquement dans `**Voix :**`**, jamais dans les textes à l'écran ni les notes.

#### Section produit — explication courte du mécanisme

Si la vidéo inclut le complément alimentaire ou le probiotique (effet pas évident visuellement), intègre **une seule version courte** (~10-12 s) dans le script :
- 2 mécanismes max, formulation simple, métaphores concrètes du quotidien ("ramollir", "dégonfler", "veines gonflées", "cercle vicieux", "stagne").
- Pas de noms d'actifs en latin dans la voix (pas de "diosmine", "marron d'Inde", "vigne rouge").
- Pas de pourcentages d'efficacité non sourcés.

Mécanismes Butt Butter à mentionner :
- **Transit** : fibres qui ramollissent les selles → moins d'effort de poussée, moins d'irritation. Punchline type : "tu pousses moins, et 80% du problème c'est ça".
- **Circulation** : extraits veinotoniques qui aident les veines à dégonfler de l'intérieur. Punchline type : "les hémorroïdes c'est des veines gonflées, les plantes dedans aident à les dégonfler de l'intérieur".

Si la formule réelle diffère (ex : actifs anti-inflammatoires plutôt que veinotoniques), adapte la métaphore et signale-le dans les notes.

#### Livraison

À la fin de l'étape 4 :
1. Livre le script en Markdown directement dans le chat.
2. **Enregistre-le dans `output/YYYY-MM-DD-<slug-titre>/script.md`** (date du jour, titre en kebab-case sans accents ni ponctuation : "Le 3ᵉ truc" → `le-3eme-truc`, "POV ma routine post-partum" → `pov-ma-routine-post-partum`). Le contenu du fichier est identique au script livré dans le chat.
3. Mentionne le chemin en une ligne (ex : "Script enregistré dans `output/2026-05-13-le-3eme-truc/script.md`.").

Si l'utilisateur ré-itère ensuite (modification du hook, persona, timing), **réécris le même fichier**. Crée un nouveau dossier `…-v2/` seulement si l'utilisateur demande explicitement une variante.

Pour un export `.docx` ou `.pdf` à transmettre à une créatrice, propose les skills `docx` / `pdf` à partir du `script.md` déjà enregistré.

## Règles transverses

### Langue et ton

Français, registre oral courant : "t'as", "j'pleurais", "j'l'ai", "ça gratte", "y a", "trucs". Évite les formulations écrites.

- Phrases courtes, une idée par phrase.
- "J'assume 1/3" plutôt que "J'assume un sur trois" (codes overlay TikTok).
- Pas de "premièrement / deuxièmement / d'autre part" — utilise "d'abord", "et ensuite", "en gros", "et là".

#### Élisions orales (obligatoires dans la voix off uniquement)

ElevenLabs lit ce que tu écris : si tu écris "écrit", la voix sonne lue. **Transcris les élisions que les francophones font naturellement à l'oral**, dans le champ `**Voix :**` uniquement (pas dans les textes à l'écran, pas dans les notes, pas dans les titres).

| Écrit standard | À écrire dans la voix |
|---|---|
| `que c'était` | `qu'c'était` |
| `que je` | `qu'j'` |
| `que tu` | `qu't'` |
| `que non` | `qu'non` |
| `que ça` | `qu'ça` |
| `je me` (devant consonne) | `j'me` |
| `je te` | `j't'` |
| `je le` | `j'le` |
| `je la` | `j'la` |
| `je suis` | `j'suis` |
| `je sais` | `j'sais` |
| `je pense` | `j'pense` |
| `je m'asseyais` | `j'm'asseyais` |
| `je m'en` | `j'm'en` |
| `tu as` | `t'as` |
| `tu es` | `t'es` |
| `prévenu` | `prév'nu` |
| `maintenant` | `maint'nant` |
| `petit` | `p'tit` |
| `parce que` | `parc'que` |
| `il y a` | `y a` |
| `il faut` | `faut` |
| `pas de` (devant consonne) | `pas d'` |

Garde-fous :
- **Ne sur-élide pas.** Si la phrase devient cryptique (4 apostrophes d'affilée), recule. Le critère est l'oreille.
- **Premier mot d'une phrase** : n'élide pas si ça sonne caricatural ("Personne" reste "Personne", pas "P'rsonne").
- Les tags `[XXX]` sont neutres typographiquement.
- Avant livraison, relis chaque `**Voix :**` à voix haute (mentalement). Si ça sonne écrit, élide ; si l'élision sonne forcée, retire-la.

Exemple — avant / après :

Standard (à ne pas écrire) :
> `"Personne m'a prévenu qu'à 45 ans, le mot [HESITANT]'hémorroïdes' allait rentrer dans mon vocabulaire. Pendant 10 ans j'ai cru que c'était normal de serrer les dents quand je m'asseyais."`

Oral naturel (à écrire) :
> `"Personne m'a prév'nu qu'à 45 ans, le mot [HESITANT]'hémorroïdes' allait rentrer dans mon vocabulaire. Pendant 10 ans j'ai cru qu'c'était normal de serrer les dents quand j'm'asseyais."`

### Codes plateforme (TikTok / Reels / Shorts)

- Vertical 9:16 systématique.
- Hook impératif dans les 3 premières secondes.
- Texte à l'écran en complément de la voix (70% des vues TikTok sont sans son).
- Pas de logo en intro, seulement en CTA final.
- Pas de musique de pub ; suggérer un son tendance natif si pertinent.

### Contraintes légales (France, DGCCRF/EFSA)

**Complément alimentaire** :
- Autorisé : "agit sur le transit", "soutient la circulation", "calme la sensation d'inconfort", "j'ai vu une vraie différence".
- Interdit : "soigne", "guérit", "traite les hémorroïdes", "élimine", "supprime", "fait disparaître".
- Tout claim chiffré ("80% du problème", "divisé par 3", "en quelques minutes") doit être validé légalement, ou remplacé par une formulation expérientielle.

**Crème** (cosmétique ou DM selon statut) : reste sur "calme", "apaise", "soulage". Évite "soigne", "guérit".

### Anti-patterns

- **Ton "publicité"** : "Découvrez la nouvelle crème révolutionnaire…" → coupe immédiat.
- **Claims médicaux inventés** : jamais de chiffres ou d'études fictifs.
- **Surjeu** : la créatrice ne "joue pas la vendeuse". Plus c'est posé, plus ça convertit.
- **Emoji et tirets cadratins (—)** : ni dans la voix, ni à l'écran.
- **Mots IA-typiques** : "structurellement", "second-order", "navigate", "leverage", "déployer", "à savoir", "la lecture est simple". Reste en parlé.
- **Hook qui spoile la marque** : on dit "un produit", "ce truc". Butt Butter révélé à 0:03+, jamais frame 1.
- **Deux versions livrées** : une seule, point. Si débordement >60 s, coupe la section problème, pas la section produit.
