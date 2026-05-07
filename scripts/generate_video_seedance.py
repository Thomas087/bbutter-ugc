#!/usr/bin/env python3
"""
generate_video_seedance.py — generate one UGC video segment via the BytePlus
Ark Seedance content-generation API.

Unlike the Kling omni-video flow, Seedance does not need a start/end frame.
The character look is supplied by a reference asset ID (a "digital character"
in BytePlus terms) and any in-shot products are passed as additional
reference images. The model handles motion and lip-sync from the text prompt.

Given a session directory laid out by the upstream UGC pipeline:
    <session>/
        frames/segment_<N>/video_prompt.txt   (optional, falls back to default)
        voice_sections_1.2x/section-<NN>.mp3  (used to pick duration)

this script:
  1. Reads the accelerated audio duration of the matching voice section to
     pick a Seedance duration (5 or 10 seconds), unless --duration is given.
  2. Builds the content array: prompt text + one reference_image entry per
     --asset-id (asset:// URI) and per --image-url (https URI).
  3. POSTs to /api/v3/contents/generations/tasks with Bearer auth.
  4. Polls task status until succeeded or failed.
  5. Downloads the generated MP4 to <session>/videos/<output-name>.

Reads ARK_API_KEY from the environment. Source the project .env first
(`set -a; source .env; set +a`) or export it.

Usage:
    scripts/generate_video_seedance.py SESSION_DIR SEGMENT_NUM \\
        --asset-id asset-20260225022658-zn9dj \\
        [--asset-id ...] [--image-url https://...] \\
        [--audio-asset-id file-...] [--audio-url https://...] \\
        [--prompt TEXT] [--duration 5|10] [--ratio adaptive|16:9|9:16|1:1] \\
        [--model dreamina-seedance-2-0-260128] [--generate-audio] [--no-watermark] \\
        [--output-name segment_1_seedance.mp4]

Exit codes:
  0 — video written
  1 — bad arguments / missing env / missing input files
  2 — API error or task failure
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

ARK_BASE = "https://ark.ap-southeast.bytepluses.com/api/v3"
TASKS_PATH = "/contents/generations/tasks"
DEFAULT_MODEL = "dreamina-seedance-2-0-260128"
DEFAULT_PROMPT = (
    "Fixed front-camera selfie framing, vertical 9:16, iPhone UGC look. "
    "The character holds the phone at arm's length and speaks directly into "
    "the lens in a calm, natural tone. Lips move with natural French phonemes, "
    "micro head shifts of 1–3 degrees, natural breathing, eyes locked on the "
    "lens. No camera movement, no zoom, no pan. Stable natural daylight. "
    "Realistic, imperfect UGC — not glossy, not cinematic. Absolutely no text, "
    "no captions, no subtitles, no watermarks visible in the image."
)


def audio_duration_seconds(path: Path) -> float:
    out = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        text=True,
    ).strip()
    return float(out)


def pick_duration(audio_seconds: float) -> int:
    return 5 if audio_seconds <= 7.5 else 10


def http_post_json(url: str, token: str, payload: dict) -> dict:
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        err_body = e.read().decode(errors="replace")
        raise SystemExit(f"Ark POST {url} failed: HTTP {e.code}\n{err_body}")


def http_get_json(url: str, token: str) -> dict:
    req = urllib.request.Request(
        url,
        method="GET",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        err_body = e.read().decode(errors="replace")
        raise SystemExit(f"Ark GET {url} failed: HTTP {e.code}\n{err_body}")


def http_download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as resp, open(dest, "wb") as fh:
        while True:
            chunk = resp.read(1 << 16)
            if not chunk:
                break
            fh.write(chunk)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("session_dir", type=Path)
    ap.add_argument("segment_num", type=int)
    ap.add_argument(
        "--asset-id",
        action="append",
        default=[],
        help="Reference asset ID (e.g. character or product). May be repeated. "
        "Passed to the API as asset://<id> with role=reference_image.",
    )
    ap.add_argument(
        "--image-url",
        action="append",
        default=[],
        help="HTTPS reference image URL. May be repeated. Passed with role=reference_image.",
    )
    ap.add_argument(
        "--audio-asset-id",
        action="append",
        default=[],
        help="Reference audio asset/file ID (e.g. uploaded mp3). May be repeated. "
        "Passed to the API as asset://<id> with role=reference_audio.",
    )
    ap.add_argument(
        "--audio-url",
        action="append",
        default=[],
        help="HTTPS reference audio URL. May be repeated. Passed with role=reference_audio.",
    )
    ap.add_argument("--prompt", type=str, default=None)
    ap.add_argument("--duration", type=int, choices=[5, 10], default=None)
    ap.add_argument(
        "--ratio",
        default="9:16",
        help='Output aspect ratio. "adaptive" lets the model pick from references.',
    )
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument(
        "--generate-audio",
        action="store_true",
        help="Ask Seedance to generate audio. Off by default — the UGC pipeline "
        "already produces voice from voice_sections_1.2x and combines it later.",
    )
    ap.add_argument(
        "--no-watermark",
        action="store_true",
        help="Disable Seedance watermark. Defaults to watermark=True.",
    )
    ap.add_argument(
        "--output-name",
        default=None,
        help="Filename for the saved mp4 under <session>/videos/. "
        "Defaults to segment_<N>_seedance.mp4.",
    )
    ap.add_argument("--poll-interval", type=float, default=15.0)
    ap.add_argument("--max-wait", type=float, default=900.0)
    args = ap.parse_args()

    api_key = os.environ.get("ARK_API_KEY")
    if not api_key:
        print("generate_video_seedance.py: ARK_API_KEY not set", file=sys.stderr)
        return 1

    session = args.session_dir.resolve()
    n = args.segment_num
    seg_dir = session / "frames" / f"segment_{n}"
    voice = session / "voice_sections_1.2x" / f"section-{n:02d}.mp3"

    if not voice.exists():
        print(f"generate_video_seedance.py: missing input: {voice}", file=sys.stderr)
        return 1

    audio_sec = audio_duration_seconds(voice)
    duration = args.duration or pick_duration(audio_sec)

    prompt = args.prompt
    if prompt is None:
        prompt_file = seg_dir / "video_prompt.txt"
        if prompt_file.exists():
            prompt = prompt_file.read_text().strip()
        else:
            prompt = DEFAULT_PROMPT

    content: list[dict] = [{"type": "text", "text": prompt}]
    for aid in args.asset_id:
        content.append(
            {
                "type": "image_url",
                "image_url": {"url": f"asset://{aid}"},
                "role": "reference_image",
            }
        )
    for url in args.image_url:
        content.append(
            {
                "type": "image_url",
                "image_url": {"url": url},
                "role": "reference_image",
            }
        )
    for aid in args.audio_asset_id:
        content.append(
            {
                "type": "audio_url",
                "audio_url": {"url": f"asset://{aid}"},
                "role": "reference_audio",
            }
        )
    for url in args.audio_url:
        content.append(
            {
                "type": "audio_url",
                "audio_url": {"url": url},
                "role": "reference_audio",
            }
        )

    payload = {
        "model": args.model,
        "content": content,
        "generate_audio": bool(args.generate_audio),
        "ratio": args.ratio,
        "duration": duration,
        "watermark": not args.no_watermark,
    }

    print(
        f"[segment {n}] model={args.model} audio={audio_sec:.2f}s "
        f"duration={duration}s ratio={args.ratio} "
        f"refs={len(args.asset_id)} image-assets + {len(args.image_url)} image-urls + "
        f"{len(args.audio_asset_id)} audio-assets + {len(args.audio_url)} audio-urls",
        file=sys.stderr,
    )

    create_url = ARK_BASE + TASKS_PATH
    print(f"[segment {n}] POST {create_url}", file=sys.stderr)
    created = http_post_json(create_url, api_key, payload)

    task_id = created.get("id")
    if not task_id:
        print(f"Ark create did not return id: {json.dumps(created, indent=2)}", file=sys.stderr)
        return 2
    print(f"[segment {n}] task_id={task_id}", file=sys.stderr)

    poll_url = f"{create_url}/{task_id}"
    deadline = time.time() + args.max_wait
    last_status = None
    while time.time() < deadline:
        info = http_get_json(poll_url, api_key)
        status = info.get("status")
        if status != last_status:
            print(f"[segment {n}] status={status}", file=sys.stderr)
            last_status = status
        if status == "succeeded":
            video_url = (info.get("content") or {}).get("video_url")
            if not video_url:
                print(
                    f"Ark succeeded but no video_url: {json.dumps(info, indent=2)}",
                    file=sys.stderr,
                )
                return 2
            out_name = args.output_name or f"segment_{n}_seedance.mp4"
            out_path = session / "videos" / out_name
            print(f"[segment {n}] downloading {video_url}", file=sys.stderr)
            http_download(video_url, out_path)
            print(str(out_path))
            return 0
        if status == "failed":
            err = info.get("error") or info
            print(f"Ark task failed: {json.dumps(err, indent=2)}", file=sys.stderr)
            return 2
        time.sleep(args.poll_interval)

    print(f"generate_video_seedance.py: timed out after {args.max_wait}s", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
