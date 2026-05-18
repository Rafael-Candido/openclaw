#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/.env" 2>/dev/null || true
fi

CMD="${1:-search}"
shift || true

KB_BLOCK_ID="${EINSTEIN_NOTION_KB_BLOCK_ID:-2ed21016bd488033882be7b30727de5c}"
API_KEY="${NOTION_SMARTENVIOS_API_KEY:-}"

if [[ -z "${API_KEY}" ]]; then
  echo '{"error":"NOTION_SMARTENVIOS_API_KEY not set"}'
  exit 1
fi

QUERY="${*:-}"

python3 - "$CMD" "$KB_BLOCK_ID" "$API_KEY" "$QUERY" <<'PY'
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request


def fail(message: str, code: int = 1) -> None:
    print(json.dumps({"error": message}, ensure_ascii=False))
    raise SystemExit(code)


def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKD", value or "")
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = value.lower()
    value = re.sub(r"\s+", " ", value).strip()
    return value


def fetch_children(block_id: str, api_key: str) -> list[dict]:
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
    }
    results: list[dict] = []
    cursor = None
    attempts = 3

    while True:
        url = f"https://api.notion.com/v1/blocks/{urllib.parse.quote(block_id)}/children?page_size=100"
        if cursor:
            url += f"&start_cursor={urllib.parse.quote(cursor)}"

        last_error = None
        payload = None
        for attempt in range(1, attempts + 1):
            req = urllib.request.Request(url, headers=headers, method="GET")
            try:
                with urllib.request.urlopen(req, timeout=30) as resp:
                    payload = json.loads(resp.read().decode("utf-8"))
                    break
            except urllib.error.HTTPError as exc:
                body = exc.read().decode("utf-8", errors="replace")
                last_error = f"HTTP {exc.code}: {body}"
                if exc.code == 429 or exc.code >= 500:
                    time.sleep(attempt)
                    continue
                fail(last_error)
            except Exception as exc:  # pragma: no cover - defensive
                last_error = str(exc)
                time.sleep(attempt)
        if payload is None:
            fail(f"notion request failed: {last_error}")

        results.extend(payload.get("results", []))
        if not payload.get("has_more"):
            return results
        cursor = payload.get("next_cursor")
        if not cursor:
            return results


def block_text(block: dict) -> str:
    block_type = block.get("type", "")
    body = block.get(block_type, {})
    if isinstance(body, dict):
        if "rich_text" in body:
            parts = [item.get("plain_text", "") for item in body.get("rich_text", [])]
            return "".join(parts).strip()
        if "title" in body:
            return str(body.get("title", "")).strip()
        if "caption" in body:
            parts = [item.get("plain_text", "") for item in body.get("caption", [])]
            return "".join(parts).strip()
        if "url" in body:
            return str(body.get("url", "")).strip()
    return ""


def build_entries(blocks: list[dict]) -> list[dict]:
    entries: list[dict] = []
    heading = ""
    current = None

    for block in blocks:
        block_type = block.get("type", "")
        text = block_text(block)
        if not text:
            continue

        if block_type.startswith("heading_"):
            heading = text
            current = None
            continue

        if text.endswith("?"):
            current = {
                "heading": heading,
                "question": text,
                "answer_parts": [],
            }
            entries.append(current)
            continue

        prefix = ""
        if block_type == "bulleted_list_item":
            prefix = "- "
        elif block_type == "numbered_list_item":
            prefix = "1. "

        if current is None:
            entries.append(
                {
                    "heading": heading,
                    "question": "",
                    "answer_parts": [f"{prefix}{text}".strip()],
                }
            )
            continue

        current["answer_parts"].append(f"{prefix}{text}".strip())

    cooked: list[dict] = []
    for entry in entries:
        answer = "\n".join(part for part in entry["answer_parts"] if part).strip()
        cooked.append(
            {
                "heading": entry["heading"],
                "question": entry["question"],
                "answer": answer,
            }
        )
    return cooked


def search_entries(entries: list[dict], query: str) -> list[dict]:
    norm_query = normalize(query)
    terms = [term for term in re.findall(r"[a-z0-9]+", norm_query) if len(term) > 1]
    ranked = []

    for entry in entries:
        heading = normalize(entry["heading"])
        question = normalize(entry["question"])
        answer = normalize(entry["answer"])
        combined = " ".join(part for part in [heading, question, answer] if part)
        score = 0

        if norm_query and norm_query in question:
            score += 120
        if norm_query and norm_query in answer:
            score += 100
        if norm_query and norm_query in heading:
            score += 60

        if terms and all(term in combined for term in terms):
            score += 40

        for term in terms:
            if term in question:
                score += 10
            if term in answer:
                score += 6
            if term in heading:
                score += 4

        if entry["question"] and entry["answer"]:
            score += 5

        if score > 0:
            ranked.append((score, entry))

    ranked.sort(key=lambda item: (-item[0], item[1]["heading"], item[1]["question"]))
    return [{"score": score, **entry} for score, entry in ranked[:5]]


def print_search(matches: list[dict], query: str) -> None:
    if not matches:
        print(f"QUERY: {query}")
        print("MATCHES: 0")
        return

    print(f"QUERY: {query}")
    print(f"MATCHES: {len(matches)}")
    for idx, item in enumerate(matches, start=1):
        print(f"\nMATCH {idx} | score={item['score']}")
        if item["heading"]:
            print(f"Heading: {item['heading']}")
        if item["question"]:
            print(f"Pergunta: {item['question']}")
        if item["answer"]:
            print("Resposta:")
            print(item["answer"])


def print_dump(entries: list[dict]) -> None:
    for idx, item in enumerate(entries, start=1):
        print(f"ENTRY {idx}")
        if item["heading"]:
            print(f"Heading: {item['heading']}")
        if item["question"]:
            print(f"Pergunta: {item['question']}")
        if item["answer"]:
            print("Resposta:")
            print(item["answer"])
        print()


cmd = sys.argv[1]
block_id = sys.argv[2]
api_key = sys.argv[3]
query = sys.argv[4]

blocks = fetch_children(block_id, api_key)
entries = build_entries(blocks)

if cmd == "search":
    if not query.strip():
        fail("query required for search")
    print_search(search_entries(entries, query), query)
elif cmd == "dump":
    print_dump(entries)
else:
    fail(f"unsupported command: {cmd}")
PY
