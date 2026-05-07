#!/usr/bin/env python3
"""
generate_video_kling.py — generate one UGC video segment via the Kling omni-video API.

Given a session directory laid out by the upstream UGC pipeline:
    <session>/
        frames/segment_<N>/start_frame.png
        frames/segment_<N>/end_frame.png
        frames/segment_<N>/video_prompt.txt   (optional, falls back to default)
        voice_sections_1.2x/section-<NN>.mp3

this script:
  1. Reads the accelerated audio duration of the matching voice section,
     picks the closest supported Kling duration (5 or 10).
  2. Base64-encodes the start and end frames.
  3. Mints a Kling JWT (HS256) from KLING_ACCESS_KEY / KLING_SECRET_KEY.
  4. POSTs to /v1/videos/omni-video with model_name=kling-v3-omni, mode=pro.
  5. Polls task status until success or failure.
  6. Downloads the generated MP4 to <session>/videos/segment_<N>.mp4.

Reads KLING_ACCESS_KEY and KLING_SECRET_KEY from the environment. Source
the project .env first (`set -a; source .env; set +a`) or export them.

Usage:
    scripts/generate_video_kling.py SESSION_DIR SEGMENT_NUM [--prompt TEXT]
                              [--duration {5,10}] [--mode {std,pro}]

Exit codes:
  0 — video written
  1 — bad arguments / missing env / missing input files
  2 — API error or task failure
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

KLING_BASE = "https://api-singapore.klingai.com"
OMNI_PATH = "/v1/videos/omni-video"
I2V_PATH = "/v1/videos/image2video"
DEFAULT_PROMPT = (
    "The person in the frame is naturally talking to the front camera in a "
    "calm, confidential tone. Lips move softly with French phonemes, mouth "
    "opens and closes subtly, micro head shifts of a couple of degrees, "
    "natural breathing, eyes locked on the lens. He finishes with a soft "
    "closed-mouth half-smile. The hand holding the phone is steady with only "
    "a faint natural tremor. The bathroom shelf, mirror, and background "
    "objects stay still. Fixed front-camera framing — no camera movement, no "
    "zoom, no pan, no rotation. Soft natural daylight, no flicker."
)


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def encode_jwt(access_key: str, secret_key: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": access_key, "exp": now + 1800, "nbf": now - 5}
    h = b64url(json.dumps(header, separators=(",", ":")).encode())
    p = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = f"{h}.{p}".encode()
    sig = hmac.new(secret_key.encode(), signing_input, hashlib.sha256).digest()
    return f"{h}.{p}.{b64url(sig)}"


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
    # Kling omni-video supports 5 or 10 second outputs.
    return 5 if audio_seconds <= 7.5 else 10


def encode_image_b64(path: Path) -> str:
    # Kling rejects RFC2397 data: URIs — it wants the raw standard base64
    # payload only (no prefix, no padding stripped, no urlsafe alphabet).
    return base64.b64encode(path.read_bytes()).decode()


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
        raise SystemExit(f"Kling POST {url} failed: HTTP {e.code}\n{err_body}")


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
        raise SystemExit(f"Kling GET {url} failed: HTTP {e.code}\n{err_body}")


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
    ap.add_argument("--prompt", type=str, default=None)
    ap.add_argument("--duration", type=int, choices=[5, 10], default=None)
    ap.add_argument("--mode", choices=["std", "pro"], default="pro")
    ap.add_argument(
        "--model",
        default="kling-v3-omni",
        help="Kling model_name. Names containing 'omni' use the omni-video "
        "endpoint (start+end frames in image_list); others use image2video "
        "(image + image_tail).",
    )
    ap.add_argument(
        "--output-name",
        default=None,
        help="Filename for the saved mp4 under <session>/videos/. "
        "Defaults to segment_<N>.mp4.",
    )
    ap.add_argument(
        "--poll-interval", type=float, default=10.0, help="seconds between polls"
    )
    ap.add_argument(
        "--max-wait", type=float, default=900.0, help="max seconds to wait for task"
    )
    args = ap.parse_args()

    ak = os.environ.get("KLING_ACCESS_KEY")
    sk = os.environ.get("KLING_SECRET_KEY")
    if not ak or not sk:
        print(
            "generate_video_kling.py: KLING_ACCESS_KEY / KLING_SECRET_KEY not set",
            file=sys.stderr,
        )
        return 1

    session = args.session_dir.resolve()
    n = args.segment_num
    seg_dir = session / "frames" / f"segment_{n}"
    start_frame = seg_dir / "start_frame.png"
    end_frame = seg_dir / "end_frame.png"
    voice = session / "voice_sections_1.2x" / f"section-{n:02d}.mp3"

    for p in (start_frame, end_frame, voice):
        if not p.exists():
            print(f"generate_video_kling.py: missing input: {p}", file=sys.stderr)
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

    print(
        f"[segment {n}] model={args.model} audio={audio_sec:.2f}s "
        f"duration={duration}s mode={args.mode}",
        file=sys.stderr,
    )

    is_omni = "omni" in args.model
    if is_omni:
        api_path = OMNI_PATH
        payload = {
            "model_name": args.model,
            "prompt": prompt,
            "image_list": [
                {"image_url": encode_image_b64(start_frame), "type": "first_frame"},
                {"image_url": encode_image_b64(end_frame), "type": "end_frame"},
            ],
            "mode": args.mode,
            "duration": str(duration),
        }
    else:
        api_path = I2V_PATH
        payload = {
            "model_name": args.model,
            "prompt": prompt,
            "image": encode_image_b64(start_frame),
            "image_tail": encode_image_b64(end_frame),
            "mode": args.mode,
            "duration": str(duration),
        }

    token = encode_jwt(ak, sk)
    create_url = KLING_BASE + api_path
    print(f"[segment {n}] POST {create_url}", file=sys.stderr)
    created = http_post_json(create_url, token, payload)

    code = created.get("code")
    if code not in (0, "0"):
        print(f"Kling create failed: {json.dumps(created, indent=2)}", file=sys.stderr)
        return 2

    task_id = created["data"]["task_id"]
    print(f"[segment {n}] task_id={task_id}", file=sys.stderr)

    poll_url = f"{create_url}/{task_id}"
    deadline = time.time() + args.max_wait
    last_status = None
    while time.time() < deadline:
        # Refresh JWT for long polls (they expire in 30 min anyway, but be safe).
        token = encode_jwt(ak, sk)
        info = http_get_json(poll_url, token)
        if info.get("code") not in (0, "0"):
            print(f"Kling poll failed: {json.dumps(info, indent=2)}", file=sys.stderr)
            return 2
        data = info.get("data", {})
        status = data.get("task_status")
        if status != last_status:
            print(f"[segment {n}] status={status}", file=sys.stderr)
            last_status = status
        if status == "succeed":
            videos = data.get("task_result", {}).get("videos", [])
            if not videos:
                print(f"Kling succeed but no videos: {json.dumps(info, indent=2)}", file=sys.stderr)
                return 2
            video_url = videos[0].get("url")
            if not video_url:
                print(f"Kling succeed but no url: {json.dumps(info, indent=2)}", file=sys.stderr)
                return 2
            out_name = args.output_name or f"segment_{n}.mp4"
            out_path = session / "videos" / out_name
            print(f"[segment {n}] downloading {video_url}", file=sys.stderr)
            http_download(video_url, out_path)
            print(str(out_path))
            return 0
        if status == "failed":
            msg = data.get("task_status_msg") or data.get("task_result", {})
            print(f"Kling task failed: {msg}", file=sys.stderr)
            return 2
        time.sleep(args.poll_interval)

    print(f"generate_video_kling.py: timed out after {args.max_wait}s", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
