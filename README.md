# Butt Butter UGC Generator

A set of Claude Code skills that turn a short brief into a publish-ready vertical
UGC video (TikTok / Reels / Shorts) for [Butt Butter](https://buttbutter.fr).
Each skill is a single step; the orchestrator chains them end-to-end.

## Orchestrator

### `ugc-full-video-pipeline`
The end-to-end video engine. Takes a session folder (`output/<date-slug>/`)
that already contains a `script.md` and lo-fi voice tracks
(`voice_sections_1.2x_lofi/section-NN.mp3`) and produces a finished
`<session>/final.mp4`. It runs **sequentially, segment by segment** (never in
parallel):

1. **Parse** the script into timed segments and scene directives.
2. **Match the persona** to a real character asset via `scripts/characters.json`
   (strict gender, closest age).
3. **Resolve products** cited in the script by keyword-matching the catalog
   (`brand/products/catalog.yaml`).
4. **Segment 1 (anchor seed):** generate the first shot with the character asset,
   auto-attached lo-fi audio, and product packshots.
5. **Face-mask 1:** extract segment 1's first frame and paint an opaque shape over
   the face — a continuity reference that locks body + set + phone while letting
   Seedance re-generate the face on later shots.
6. **Segments 2..N:** generate each remaining shot, attaching face-mask 1 to
   `Plan ancre 1` shots and the relevant product references.
7. **De-AI** (`ugc-deai`) and **concat** (`ugc-concat`) to produce `final.mp4`.

It optionally supports a **second anchor plan** (`Plan ancre 2`, a different
environment): its seed shot is generated *without* a face-mask, then a second
face-mask is extracted and attached to the following `Plan ancre 2` shots. Max one
second anchor per script.

This skill replaces manually looping the atomic `ugc-video-seedance` →
`ugc-face-mask-extractor` → `ugc-video-seedance` steps.

## Sub-skills called

### `ugc-deai` (pipeline step 7)
Breaks the "too crisp / too AI" look of the Seedance segments and harmonizes their
color on segment 1. Applies a frozen ffmpeg filter (micro-blur + film grain) to
every segment, plus per-channel gamma + saturation correction on segments N>1 to
match segment 1's mean RGB. Originals are preserved under `videos/raw/`; output is
written back to the canonical path so `ugc-concat` picks it up. Idempotent.

### `ugc-concat` (pipeline step 8)
Concatenates `videos/segment_<N>_final.mp4` in ascending order into
`<session>/final.mp4` using the ffmpeg concat demuxer with `-c copy` (no
re-encode, instant, lossless). Falls back to `libx264 + aac` re-encode if segment
codecs differ.

## Atomic video skills (the pipeline's building blocks)

### `ugc-video-seedance`
Generates a single UGC shot via the Seedance API (BytePlus Ark). Auto-attaches the
lo-fi voice as reference audio for lip-sync, embeds the exact French line in the
prompt so Seedance doesn't hallucinate text, and bakes the audio into
`videos/segment_<N>_final.mp4`. Used to test or regenerate one shot in isolation.

### `ugc-face-mask-extractor`
Extracts a segment's first frame and uses `gpt-image-2` to paint an opaque shape
over the face while keeping body, phone, outfit, and set identical — the
continuity reference consumed by the orchestrator.

## Upstream skills (produce the pipeline's inputs)

The pipeline consumes the output of this chain:

### `ugc-script-writer`
Writes the short vertical UGC script (hook, staging, voice-over lines, scene
directives) for a Butt Butter product.

### `ugc-voice-generator`
Generates the ElevenLabs voice-over segment by segment, then speeds each to 1.2x.
Produces `voice_sections/` (originals) and `voice_sections_1.2x/` (sped-up), plus
per-segment durations used to size the video shots.

### `ugc-voice-lofi`
Degrades the voice into a cheap-phone + bathroom-reverb "real UGC" sound
(ffmpeg bandpass + light compression, then sox reverb). Produces
`voice_sections_lofi/` and `voice_sections_1.2x_lofi/` — the latter is the
pipeline's required input.

## Supporting skills

- **`ugc-character-sheet-generator`** — renders a 5-angle character/continuity
  sheet of a script's persona for briefing or image-to-video reference.
- **`collect-brand-data`** — refreshes all Butt Butter brand data under `brand/`
  (guidelines, product catalog, JudgeMe reviews, Instagram history).

## Typical flow

```
collect-brand-data
        │
ugc-script-writer ──▶ ugc-voice-generator ──▶ ugc-voice-lofi
                                                    │
                                       ugc-full-video-pipeline
                                       (seedance + face-mask ×N
                                        → ugc-deai → ugc-concat)
                                                    │
                                            <session>/final.mp4
```

## Requirements

A repo-root `.env` (gitignored; see `.env.example`) with at least
`ARK_API_KEY`, `OPENAI_API_KEY`, the `CELLAR_*` storage keys, plus `ffmpeg` and
`sox` on the `PATH`.
