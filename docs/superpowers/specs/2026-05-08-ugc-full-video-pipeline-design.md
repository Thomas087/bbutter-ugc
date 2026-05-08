# UGC Full Video Pipeline — Design

**Date:** 2026-05-08
**Status:** Approved (design phase). Ready for implementation plan.
**Skill name:** `ugc-full-video-pipeline`
**Skill location:** `.claude/skills/ugc-full-video-pipeline/SKILL.md`

## Goal

Orchestrate end-to-end UGC video generation for a single Butt Butter script, starting from the moment the lo-fi voice has already been produced (`voice_sections_1.2x_lofi/section-NN.mp3`). The skill walks segment-by-segment through the script, generates each plan via `scripts/generate_video_seedance.py`, extracts a face-mask reference from segment 1, then generates the remaining segments with the right combination of references (character asset, lo-fi audio, face mask, product packshot, product size reference) per segment.

The skill replaces the manual "run `ugc-video-seedance` then `ugc-face-mask-extractor` then `ugc-video-seedance` per segment" loop. It is consumed downstream of `ugc-script-writer` → `ugc-voice-generator` → `ugc-voice-lofi`.

## Non-goals

- Generating script, voice, or lo-fi audio. The skill assumes those already exist.
- Final concatenation of segments into a single video. Out of scope (handled by a future `ugc-concat` skill or by `scripts/combine_segment.sh`).
- Music, captions, on-screen-text overlay. Out of scope.
- Generating in parallel. Explicitly sequential — see "Anti-patterns".

## Inputs

| Input | Default | Notes |
|---|---|---|
| `session_dir` | latest dir under `output/` (most recent by ISO date) | Must contain `script.md` and `voice_sections_1.2x_lofi/`. |
| `--segments` | all segments in `script.md` | Comma-separated 1-based indices, e.g. `--segments 2,4`. |
| `--force` | off | Re-generate even if `videos/segment_N_final.mp4` already exists. |

## Pipeline

```
Step 0 — parse script.md
  ├─ split into segments by `**[h:mm:ss – h:mm:ss] — TITLE**` headers
  ├─ for each segment: index N, stage direction (italics line), voice text,
  │  on-screen text, insert annotations
  └─ build per-segment metadata: { anchor: bool, products: [slug, ...], voice }

Step 1 — resolve persona → character asset
  ├─ read script header `**Persona :**` line
  ├─ match against scripts/characters.json (gender strict, age closest)
  └─ capture seedance_asset_id, character description

Step 2 — build product alias map
  ├─ load brand/products/catalog.yaml (slug → name → hero_image)
  ├─ load brand/products/<slug>.md per product, extract
  │  `**Référence taille du produit :** <url>` if present
  └─ alias table (markdown in SKILL.md, tweakable):
        creme-apaisante                 ← crème, tube, noisette, apaise
        complement-circulation-transit  ← complément, gélule, circulation, transit
        probiotique                     ← probiotique
        soin-lavant-hygiene-intime      ← soin lavant, savon, lavant

Step 3 — generate segment 1 (anchor seed)
  ├─ Claude writes frames/segment_1/video_prompt.txt
  ├─ build --image list:
  │    [packshot of each detected product, size ref of each detected product]
  ├─ scripts/generate_video_seedance.py <session> 1
  │       --character-asset-id <id>
  │       [--image <packshot> --image <size_ref>]
  │   (lo-fi audio auto-attached by the script)
  └─ output: videos/segment_1_final.mp4

Step 4 — extract face mask
  ├─ ffmpeg -y -i videos/segment_1_final.mp4 -vframes 1 -update 1 -q:v 2
  │       frames/segment_1/first_frame.png
  ├─ Claude writes face-mask prompt (template from ugc-face-mask-extractor)
  └─ OPENAI_IMAGE_QUALITY=high scripts/generate_image.sh
        --ref frames/segment_1/first_frame.png
        frames/segment_1/first_frame_face_mask.png
        "<face mask prompt>" 1024x1536

Step 5 — generate segments 2..N (sequential, one at a time)
  for each segment N ≥ 2:
    ├─ Claude writes frames/segment_N/video_prompt.txt
    ├─ build --image list:
    │    [face_mask_path]      if segment is anchor
    │    [packshot, size_ref]  for each detected product
    ├─ scripts/generate_video_seedance.py <session> N
    │       --character-asset-id <id>
    │       --image ... --image ...
    │   (lo-fi audio auto-attached by the script)
    └─ output: videos/segment_N_final.mp4

Step 6 — final report (one line per segment)
  segment N — anchor=Y/N — products=[slugs] — videos/segment_N_final.mp4 (Xs, Y MB)
  + closing line pointing at next-step (concat).
```

## Reference matrix (which references go to each segment)

| Reference | Source | When attached |
|---|---|---|
| `--character-asset-id <seedance_asset_id>` | `scripts/characters.json` (matched by persona) | **Every** segment |
| `--audio` (lo-fi) | `voice_sections_1.2x_lofi/section-NN.mp3` | **Every** segment (auto-attached by `generate_video_seedance.py` when `--audio` is omitted) |
| `--image <face_mask_path>` | `frames/segment_1/first_frame_face_mask.png` (local — `storage.sh` uploads it) | Segments **N ≥ 2** AND segment is anchor |
| `--image <hero_image_url>` | `brand/products/catalog.yaml` per product slug | Each detected product in the segment |
| `--image <size_ref_url>` | `brand/products/<slug>.md` line `**Référence taille du produit :** ...` | Each detected product if its `.md` has that line; skip silently otherwise |

Segment 1 never gets the face mask — it is the seed image from which the face mask is *extracted*.

## Anchor detection

Stage direction = the italicised line directly below the `**[t1 – t2] — TITLE**` header (e.g. `*Plan ancre.*`, `*Plan ancre, elle sort le tube...*`, `*Insert : gros plan tube en main.*`).

A segment is **anchor** iff its stage direction (case-insensitive) contains `plan ancre`. Pure inserts / B-roll segments will not match and therefore will not get the face mask attached.

## Product detection (per segment)

For each segment, build the search corpus = `voice_text + insert_annotations + on_screen_text`, lower-cased, accent-preserved.

For each product slug in the alias table, attach its packshot (and size ref if present) iff **any** alias keyword appears as a substring of the corpus. Multiple products can match the same segment.

The alias table lives in the `SKILL.md` (markdown table). It is tweakable without code change. Default aliases listed under Step 2 above.

False positives are acceptable here: an extra reference image rarely hurts Seedance output, while a missing one ruins the packaging fidelity. If a segment matches no product, no `--image` is added beyond the optional face mask.

## Per-segment `video_prompt.txt`

Claude writes one prompt per segment (not a global template). Each prompt follows the structure already documented in `.claude/skills/ugc-video-seedance/SKILL.md`:

- Character description from script header (age, look, tenue, décor)
- Camera framing (selfie front-camera if anchor / close-up if insert)
- Tonal direction from ElevenLabs tags in the voice text (`[WHISPER]`, `[SERIOUS]`, etc.)
- `[Audio 1]` lipsync clause (anchor only — inserts don't need lipsync)
- Literal French voice phrase between straight quotes (anchor only)
- UGC look + anti-watermark + stability clauses

Anchor vs. insert split into two prompt skeletons inside the SKILL.md so future-Claude doesn't conflate them.

## Pre-checks (silent unless failing)

1. `<session_dir>/script.md` exists and parses into ≥ 1 segment
2. `<session_dir>/voice_sections_1.2x_lofi/section-NN.mp3` exists for every targeted N
3. `<session_dir>/voice_sections_1.2x/section-NN.mp3` exists for every targeted N (used by `generate_video_seedance.py` to compute Seedance duration)
4. `scripts/characters.json` exists; persona match found
5. `scripts/generate_video_seedance.py`, `scripts/generate_image.sh`, `scripts/storage.sh` exist
6. `ffmpeg` is on PATH
7. `.env` has `ARK_API_KEY`, `OPENAI_API_KEY`, `CELLAR_*`

If any check fails, stop with a single-line error pointing at the missing prerequisite. Do not attempt to recover (e.g. don't auto-run `ugc-voice-lofi`).

## Failure & idempotency rules

- **Persona mismatch** → stop. Tell the user to register a character asset (BytePlus Console → Digital Character) and add the row to `scripts/characters.json`. Do not default to a wrong character.
- **Lo-fi audio missing** → stop. Point at `ugc-voice-lofi`.
- **Seedance task `failed` on segment N** → log error, skip segment N, continue with segment N+1. Final report flags missing segments and shows the underlying Ark error message.
- **`videos/segment_N_final.mp4` already exists AND `--force` not set** → skip that segment, log `[segment N] skipped (already exists, pass --force to regenerate)`.
- **gpt-image-2 returns 403 "must be verified"** → `generate_image.sh` already falls back to gpt-image-1. Mention the fallback once in the report.
- **Face mask quality looks degraded** (mask transparent, mask spilling onto neck, décor redrawn) → mention in final report, suggest re-tirage. Do not auto-retry — variance is non-trivial and a re-tirage costs another credit.
- **Product `.md` has no size reference URL** → silently skip the size ref for that product. Don't fail.
- **No products detected in a segment** → only character asset + lo-fi audio (+ face mask if anchor). That's a valid call.

## Output to user (final report)

One line per segment, in segment-index order:

```
segment 1 — anchor=Y — products=[]                  — videos/segment_1_final.mp4 (5.0s, 1.3 MB)
segment 2 — anchor=Y — products=[]                  — videos/segment_2_final.mp4 (5.0s, 1.4 MB)
segment 3 — anchor=Y — products=[]                  — videos/segment_3_final.mp4 (10.0s, 2.5 MB) [face mask attached]
segment 4 — anchor=Y — products=[creme-apaisante]   — videos/segment_4_final.mp4 (10.0s, 2.6 MB) [face mask + packshot + size ref]
segment 5 — anchor=Y — products=[]                  — videos/segment_5_final.mp4 (5.0s, 1.3 MB) [face mask attached]
```

Plus:
- One line for the face-mask path (`frames/segment_1/first_frame_face_mask.png`).
- A closing line pointing at the next step ("Concat with `ffmpeg concat` or `scripts/combine_segment.sh` when you're satisfied with the segments.").

No commentary on the steps that worked. Only flag what's notable or broken.

## Skill structure (file layout)

```
.claude/skills/ugc-full-video-pipeline/
└── SKILL.md          # the entire skill — markdown only, no helper scripts
```

Pure-markdown. Calls existing helpers:
- `scripts/generate_video_seedance.py` — segment generation
- `scripts/generate_image.sh --ref` — face-mask edit
- `ffmpeg` — first-frame extraction
- `scripts/storage.sh` — invoked transitively by `generate_video_seedance.py` to upload local face-mask PNG

No new Python orchestrator. The model adapts the per-segment prompt and ref list per call.

## Anti-patterns (called out in SKILL.md)

- **Generating segments in parallel.** The pipeline is sequential by design: segment 1 must finish before face mask, face mask must finish before segments 2..N (since they need it as a reference image). Even segments 2..N stay sequential — lets the user inspect each lipsync before paying for the next, and keeps the Ark task queue calm.
- **Reusing the face mask before it exists.** Segment 1 finishes → face mask extracted → only then segments 2..N. Don't try to launch segment 2 in parallel with the face-mask call.
- **Attaching the face mask to a non-anchor (insert) segment.** Defeats the close-up framing the insert is meant to deliver. Anchor flag is checked per segment.
- **Skipping the per-segment `video_prompt.txt` rewrite.** A generic prompt across segments produces visible drift in framing, lighting, and tone. Each segment gets its own prompt, anchored on the script's stage direction and voice text.
- **Defaulting to a wrong character.** If `characters.json` has no match, stop. Don't pick the closest "similar" character — visual continuity across segments depends on the asset match.
- **Auto-running upstream skills.** This skill assumes script + lo-fi already exist. Don't try to invoke `ugc-script-writer` or `ugc-voice-lofi` from inside it. Stop and point.

## Open questions / future iterations

- **Concat step** — out of scope for this skill. Likely a separate `ugc-concat` skill.
- **Music / on-screen-text overlay** — out of scope. Probably belongs in a post-prod skill.
- **Alias map drift** — if new products get added to the catalog without their aliases being added to the SKILL.md table, products will be silently ignored. Acceptable for now; revisit if it bites.
- **Insert segment prompt template** — the design assumes Claude writes a sensible close-up prompt for inserts. The current sample script has only one insert (segment 4 in `output/2026-05-08-le-3eme/`). After 2-3 more scripts use inserts, formalise an insert prompt skeleton inside the SKILL.md.
