#!/usr/bin/env python3
"""
Export sent emails (pro + personal) to a JSON file for style/context extraction.
Uses existing gmail.sh (list in:sent, get-full per message).
Run from repo root with .env loaded so Gmail credentials are available.

Usage:
  cd /var/www/openclaw && . .env 2>/dev/null; python3 workspace/scripts/gmail/export-sent-samples.py [--max 20] [--out workspace/docs/email-samples-sent.json]
"""

import argparse
import base64
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

OPENCLAW_CONFIG_DIR = os.environ.get("OPENCLAW_CONFIG_DIR", "/var/www/openclaw")
SCRIPT_DIR = Path(__file__).resolve().parent
GMAIL_SH = SCRIPT_DIR / "gmail.sh"


def run_gmail(profile: str, action: str, *args) -> str:
    cmd = [str(GMAIL_SH), profile, action] + list(args)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError(f"gmail.sh failed: {result.stderr or result.stdout}")
    return result.stdout


def list_sent(profile: str, max_results: int = 20) -> list[str]:
    out = run_gmail(profile, "list", "in:sent", str(max_results))
    data = json.loads(out)
    ids = [m["id"] for m in data.get("messages", [])]
    return ids


def get_headers(payload: dict) -> dict:
    headers = {}
    for h in payload.get("headers", []):
        name = (h.get("name") or "").lower()
        if name in ("from", "to", "subject", "date"):
            headers[name] = h.get("value", "")
    return headers


def get_body(payload: dict) -> str:
    if payload.get("body", {}).get("size", 0) > 0 and payload.get("body", {}).get("data"):
        raw = payload["body"]["data"]
        try:
            return base64.urlsafe_b64decode(raw).decode("utf-8", errors="replace")
        except Exception:
            return ""
    for part in payload.get("parts", []):
        if (part.get("mimeType") or "").startswith("text/plain") and part.get("body", {}).get("data"):
            raw = part["body"]["data"]
            try:
                return base64.urlsafe_b64decode(raw).decode("utf-8", errors="replace")
            except Exception:
                pass
    for part in payload.get("parts", []):
        if (part.get("mimeType") or "").startswith("text/html") and part.get("body", {}).get("data"):
            raw = part["body"]["data"]
            try:
                return base64.urlsafe_b64decode(raw).decode("utf-8", errors="replace")
            except Exception:
                pass
    return ""


def fetch_full(profile: str, msg_id: str) -> Optional[dict]:
    out = run_gmail(profile, "get-full", msg_id)
    data = json.loads(out)
    payload = data.get("payload") or {}
    headers = get_headers(payload)
    body = get_body(payload)
    return {
        "id": msg_id,
        "profile": profile,
        "from": headers.get("from", ""),
        "to": headers.get("to", ""),
        "subject": headers.get("subject", ""),
        "date": headers.get("date", ""),
        "body": body.strip()[:15000],
    }


def main():
    parser = argparse.ArgumentParser(description="Export sent emails for style extraction")
    parser.add_argument("--max", type=int, default=20, help="Max sent emails per profile (default 20)")
    parser.add_argument("--out", type=str, default=None, help="Output JSON path (default: workspace/docs/email-samples-sent.json)")
    args = parser.parse_args()

    out_path = args.out
    if not out_path:
        root = Path(OPENCLAW_CONFIG_DIR)
        out_path = root / "workspace" / "docs" / "email-samples-sent.json"
    out_path = Path(out_path)

    samples = []
    for profile in ("pro", "personal"):
        try:
            ids = list_sent(profile, args.max)
        except Exception as e:
            print(f"Warning: could not list sent for {profile}: {e}", file=sys.stderr)
            continue
        for i, msg_id in enumerate(ids):
            try:
                msg = fetch_full(profile, msg_id)
                if msg and msg.get("body"):
                    samples.append(msg)
            except Exception as e:
                print(f"Warning: could not fetch {profile} {msg_id}: {e}", file=sys.stderr)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(samples, f, ensure_ascii=False, indent=2)

    print(f"Exported {len(samples)} sent emails to {out_path}", file=sys.stderr)
    print(out_path)


if __name__ == "__main__":
    main()
