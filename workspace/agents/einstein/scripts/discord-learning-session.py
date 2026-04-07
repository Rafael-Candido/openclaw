#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple

DEFAULT_GUILD_ID = "690598219146723358"
DEFAULT_BOT_ID = "1439351480514646087"
ALLOWED_CHANNEL_TYPES = {0, 5, 10, 11, 12, 15}

REQUEST_RE = re.compile(
    r"\?|(?:\b(?:pode|poderia|consegue|conseguiria|ajuda|favor|por favor|please|"
    r"crie|criar|abra|abrir|gere|gerar|registre|registrar|verifique|verifica|"
    r"analise|analisa|analisar|cotar|cota|consulta|consulte|responda|responde|"
    r"preciso|precisamos|apague|apagar|deletar|delete|investigar|corrigir|ajustar)\b)",
    re.I,
)
LOW_VALUE_RE = re.compile(
    r"^(oi|ola|ol[áa]|bom dia|boa tarde|boa noite|valeu|obrigad[oa]|kk+|rs+|haha+|"
    r"cri\s*cri|mimiu|sextou)[\s!,.?]*$",
    re.I,
)
HUMOR_RE = re.compile(r"\b(kkk+|haha+|rs+|sextou|mimiu|cri\s*cri)\b|[😄😂🤣😅😉]", re.I)
EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF]")
INTERNAL_TRACE_RE = re.compile(
    r"(<exec\s+command=|smartenvios-mcp\.sh|tool[_\s-]?call|^action:\s*(read|create|update|call)\b|^⚠️\s*agent failed\b|^i have retrieved\b|^reasoning:)",
    re.I,
)


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_json_output(raw: str) -> Dict:
    text = (raw or "").strip()
    if not text:
        raise ValueError("saida vazia")
    try:
        return json.loads(text)
    except Exception:
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            return json.loads(text[start : end + 1])
        raise


def run_openclaw_json(cmd: List[str], retries: int = 3) -> Dict:
    last_err = None
    for attempt in range(1, retries + 1):
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            last_err = RuntimeError(
                f"comando falhou ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr.strip()}"
            )
            if attempt < retries:
                time.sleep(0.2 * attempt)
                continue
            raise last_err
        payload = proc.stdout.strip() or proc.stderr.strip()
        try:
            return parse_json_output(payload)
        except Exception as exc:
            last_err = exc
            # Fallback: grava em arquivo e parseia do disco (mais estável para payload grande).
            try:
                with tempfile.NamedTemporaryFile(prefix="openclaw-json-", suffix=".tmp", delete=False) as fh:
                    tmp_path = fh.name
                with open(tmp_path, "w", encoding="utf-8") as out:
                    proc2 = subprocess.run(cmd, stdout=out, stderr=subprocess.PIPE, text=True)
                if proc2.returncode == 0:
                    raw = Path(tmp_path).read_text(encoding="utf-8", errors="replace")
                    try:
                        return parse_json_output(raw)
                    except Exception as exc2:
                        last_err = exc2
            finally:
                if "tmp_path" in locals() and tmp_path and os.path.exists(tmp_path):
                    os.unlink(tmp_path)
            if attempt < retries:
                time.sleep(0.2 * attempt)
                continue
    raise RuntimeError(f"falha ao parsear JSON em {' '.join(cmd)}: {last_err}")


def load_json(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def load_seen_question_ids(qa_file: Path) -> set:
    seen = set()
    if not qa_file.exists():
        return seen
    with qa_file.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            qid = str(obj.get("questionMessageId") or "").strip()
            if qid:
                seen.add(qid)
    return seen


def normalize_text(text: str) -> str:
    value = (text or "").strip()
    value = re.sub(r"<@!?[0-9]+>", " ", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def is_internal_trace_message(text: str) -> bool:
    content = (text or "").strip()
    if not content:
        return False
    if INTERNAL_TRACE_RE.search(content):
        return True
    # Heuristica: payload de comando/ferramenta em markdown ou XML-like.
    if content.startswith("<exec ") or content.startswith("</exec>"):
        return True
    return False


def author_name(msg: Dict) -> str:
    author = msg.get("author") or {}
    return str(author.get("global_name") or author.get("username") or "usuario")


def compact_message(msg: Dict) -> Dict:
    author = msg.get("author") or {}
    mentions = msg.get("mentions") or []
    mention_ids = []
    if isinstance(mentions, list):
        for m in mentions:
            if isinstance(m, dict):
                mid = str(m.get("id") or "")
                if mid:
                    mention_ids.append(mid)
    return {
        "id": str(msg.get("id") or ""),
        "timestampMs": int(msg.get("timestampMs") or 0),
        "content": str(msg.get("content") or ""),
        "authorId": str(author.get("id") or ""),
        "authorName": str(author.get("global_name") or author.get("username") or ""),
        "mentions": mention_ids,
    }


def is_bot_message(msg: Dict, bot_id: str) -> bool:
    return str(msg.get("authorId") or "") == bot_id


def has_bot_mention(msg: Dict, bot_id: str) -> bool:
    mentions = msg.get("mentions") or []
    if bot_id in mentions:
        return True
    content = str(msg.get("content") or "")
    return f"<@{bot_id}>" in content or f"<@!{bot_id}>" in content


def is_question_candidate(msg: Dict, bot_id: str) -> bool:
    if is_bot_message(msg, bot_id):
        return False
    if not has_bot_mention(msg, bot_id):
        return False
    norm = normalize_text(str(msg.get("content") or ""))
    if not norm:
        return False
    if LOW_VALUE_RE.search(norm):
        return False
    return bool(REQUEST_RE.search(norm) or norm.endswith("?") or len(norm.split()) >= 5)


def is_meaningful_answer(msg: Dict) -> bool:
    content = normalize_text(str(msg.get("content") or ""))
    if not content:
        return False
    if LOW_VALUE_RE.search(content):
        return False
    if is_internal_trace_message(content):
        return False
    return True


def extract_pairs(
    combined_msgs: List[Dict],
    current_msg_ids: set,
    bot_id: str,
    channel_id: str,
    channel_name: str,
    seen_question_ids: set,
    max_follow_messages: int,
    max_follow_minutes: int,
) -> List[Dict]:
    out = []
    max_delta_ms = max_follow_minutes * 60 * 1000
    for idx, msg in enumerate(combined_msgs):
        qid = str(msg.get("id") or "")
        if qid not in current_msg_ids:
            continue
        if qid in seen_question_ids:
            continue
        if not is_question_candidate(msg, bot_id):
            continue

        q_ts = int(msg.get("timestampMs") or 0)
        answer = None
        for nxt in combined_msgs[idx + 1 : idx + 1 + max_follow_messages]:
            nts = int(nxt.get("timestampMs") or 0)
            if nts > 0 and q_ts > 0 and (nts - q_ts) > max_delta_ms:
                break
            if not is_bot_message(nxt, bot_id):
                continue
            if not is_meaningful_answer(nxt):
                continue
            answer = nxt
            break

        if not answer:
            continue

        record = {
            "capturedAt": now_iso(),
            "channelId": channel_id,
            "channelName": channel_name,
            "questionMessageId": qid,
            "answerMessageId": str(answer.get("id") or ""),
            "questionTimestampMs": q_ts,
            "answerTimestampMs": int(answer.get("timestampMs") or 0),
            "questionAuthorId": str(msg.get("authorId") or ""),
            "questionAuthorName": str(msg.get("authorName") or ""),
            "question": normalize_text(str(msg.get("content") or "")),
            "answer": normalize_text(str(answer.get("content") or "")),
            "answerHasJira": bool(re.search(r"\bKey:\s*[A-Z]+-\d+\b", str(answer.get("content") or ""))),
            "answerHasLink": ("http://" in str(answer.get("content") or "") or "https://" in str(answer.get("content") or "")),
        }
        out.append(record)
        seen_question_ids.add(qid)
    return out


def update_profile(profile: Dict, bot_messages: List[Dict], qa_pairs: List[Dict], channel_id: str, channel_name: str) -> None:
    totals = profile.setdefault(
        "totals",
        {
            "botMessages": 0,
            "totalChars": 0,
            "totalWords": 0,
            "messagesWithMention": 0,
            "messagesWithLink": 0,
            "messagesWithJira": 0,
            "messagesWithEmoji": 0,
            "messagesWithHumor": 0,
            "messagesWithQuestion": 0,
            "qaPairs": 0,
        },
    )
    openers = profile.setdefault("openers", {})
    channels = profile.setdefault("channels", {})
    ch = channels.setdefault(channel_id, {"name": channel_name, "botMessages": 0, "qaPairs": 0})
    ch["name"] = channel_name

    for msg in bot_messages:
        content = str(msg.get("content") or "")
        norm = normalize_text(content)
        if not norm:
            continue
        if is_internal_trace_message(norm):
            continue
        totals["botMessages"] += 1
        ch["botMessages"] += 1
        totals["totalChars"] += len(norm)
        totals["totalWords"] += len(norm.split())
        if re.search(r"^\s*<@!?\d+>", content):
            totals["messagesWithMention"] += 1
        if "http://" in content or "https://" in content:
            totals["messagesWithLink"] += 1
        if re.search(r"\bKey:\s*[A-Z]+-\d+\b", content) and "Link:" in content:
            totals["messagesWithJira"] += 1
        if EMOJI_RE.search(content):
            totals["messagesWithEmoji"] += 1
        if HUMOR_RE.search(content):
            totals["messagesWithHumor"] += 1
        if "?" in content:
            totals["messagesWithQuestion"] += 1

        clean = re.sub(r"^\s*<@!?\d+>\s*", "", norm)
        opener = " ".join(clean.lower().split()[:3]).strip()
        if opener:
            openers[opener] = int(openers.get(opener, 0)) + 1

    totals["qaPairs"] += len(qa_pairs)
    ch["qaPairs"] += len(qa_pairs)


def summarize_profile(profile: Dict) -> None:
    openers = profile.get("openers") or {}
    channels = profile.get("channels") or {}
    clean_openers = {k: v for k, v in openers.items() if not is_internal_trace_message(k)}
    profile["openers"] = clean_openers
    top_openers = sorted(clean_openers.items(), key=lambda kv: kv[1], reverse=True)[:20]
    top_channels = sorted(channels.items(), key=lambda kv: kv[1].get("botMessages", 0), reverse=True)[:20]
    profile["topOpeners"] = [{"opener": k, "count": v} for k, v in top_openers]
    profile["topChannels"] = [
        {
            "channelId": cid,
            "channelName": c.get("name", ""),
            "botMessages": int(c.get("botMessages", 0)),
            "qaPairs": int(c.get("qaPairs", 0)),
        }
        for cid, c in top_channels
    ]


def fetch_channels(guild_id: str) -> List[Dict]:
    def normalize_channels(raw_channels):
        out = []
        for ch in raw_channels:
            if not isinstance(ch, dict):
                continue
            raw_type = ch.get("type")
            try:
                ctype = int(raw_type) if raw_type is not None else -1
            except Exception:
                ctype = -1
            if ctype not in ALLOWED_CHANNEL_TYPES:
                continue
            out.append(
                {
                    "id": str(ch.get("id") or ""),
                    "name": str(ch.get("name") or ""),
                    "type": ctype,
                    "position": int(ch.get("position") or 0),
                }
            )
        out = [c for c in out if c["id"]]
        out.sort(key=lambda c: (c["position"], c["id"]))
        return out

    def load_discord_token():
        token = str(os.environ.get("DISCORD_BOT_TOKEN") or "").strip()
        if token:
            return token
        env_file = Path("/var/www/openclaw/.env")
        if env_file.exists():
            for line in env_file.read_text(encoding="utf-8", errors="ignore").splitlines():
                if not line.startswith("DISCORD_BOT_TOKEN="):
                    continue
                token = line.split("=", 1)[1].strip().strip('"').strip("'")
                if token:
                    return token
        return ""

    out = []
    openclaw_err = None
    try:
        data = run_openclaw_json(
            [
                "openclaw",
                "message",
                "channel",
                "list",
                "--channel",
                "discord",
                "--guild-id",
                guild_id,
                "--json",
            ]
        )
        out = normalize_channels((data.get("payload") or {}).get("channels") or [])
    except Exception as exc:
        openclaw_err = exc

    # Fallback: quando o retorno vier quebrado/parcial, consulta API oficial do Discord.
    if len(out) >= 10:
        return out

    token = load_discord_token()
    if not token:
        if out:
            return out
        raise RuntimeError(f"nao foi possivel listar canais: {openclaw_err}")

    url = f"https://discord.com/api/v10/guilds/{guild_id}/channels"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bot {token}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read().decode("utf-8", errors="replace"))
        api_channels = payload if isinstance(payload, list) else []
        fallback = normalize_channels(api_channels)
        if fallback:
            return fallback
    except urllib.error.URLError:
        pass
    except Exception:
        pass

    if out:
        return out
    raise RuntimeError(f"nao foi possivel listar canais (openclaw e fallback discord): {openclaw_err}")


def read_messages_page(channel_id: str, limit: int, before_id: str) -> List[Dict]:
    candidates = []
    seen = set()
    for cand in (limit, 50, 25, 10):
        cand = max(1, min(100, int(cand)))
        if cand in seen:
            continue
        seen.add(cand)
        candidates.append(cand)

    last_err = None
    for cand_limit in candidates:
        cmd = [
            "openclaw",
            "message",
            "read",
            "--channel",
            "discord",
            "--target",
            f"channel:{channel_id}",
            "--limit",
            str(cand_limit),
            "--json",
        ]
        if before_id:
            cmd.extend(["--before", before_id])
        try:
            data = run_openclaw_json(cmd)
            messages = (data.get("payload") or {}).get("messages") or []
            return [m for m in messages if isinstance(m, dict)]
        except Exception as exc:
            last_err = exc
            continue
    raise RuntimeError(f"falha ao ler mensagens do canal {channel_id}: {last_err}")


def pick_channels_to_process(order: List[str], channels_state: Dict[str, Dict], start_idx: int, max_channels: int) -> Tuple[List[str], int]:
    if not order:
        return [], 0
    selected = []
    picked = set()
    idx = start_idx % len(order)
    scanned = 0
    target_scan = len(order) * 2
    while len(selected) < max_channels and scanned < target_scan:
        cid = order[idx]
        st = channels_state.get(cid) or {}
        if (cid not in picked) and (not bool(st.get("completed"))):
            selected.append(cid)
            picked.add(cid)
        idx = (idx + 1) % len(order)
        scanned += 1
    return selected, idx


def main() -> int:
    parser = argparse.ArgumentParser(description="Aprendizado incremental do Einstein com historico do Discord em sessoes.")
    parser.add_argument("--guild-id", default=DEFAULT_GUILD_ID)
    parser.add_argument("--bot-id", default=DEFAULT_BOT_ID)
    parser.add_argument("--max-channels", type=int, default=6)
    parser.add_argument("--max-pages-per-channel", type=int, default=12)
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--max-follow-messages", type=int, default=12)
    parser.add_argument("--max-follow-minutes", type=int, default=45)
    parser.add_argument("--context-window", type=int, default=40)
    parser.add_argument(
        "--state-file",
        default="/var/www/openclaw/workspace/agents/einstein/.pi/discord-learning-state.json",
    )
    parser.add_argument(
        "--qa-file",
        default="/var/www/openclaw/workspace/agents/einstein/.pi/discord-learning-qa.jsonl",
    )
    parser.add_argument(
        "--profile-file",
        default="/var/www/openclaw/workspace/agents/einstein/.pi/discord-learning-profile.json",
    )
    parser.add_argument(
        "--sessions-dir",
        default="/var/www/openclaw/workspace/agents/einstein/.pi/discord-learning-sessions",
    )
    parser.add_argument("--reset", action="store_true")
    parser.add_argument("--output", choices=["json", "text"], default="json")
    args = parser.parse_args()

    if args.max_channels < 1 or args.max_pages_per_channel < 1 or args.limit < 1 or args.limit > 100:
        raise SystemExit("parametros invalidos: max-channels>=1, max-pages-per-channel>=1, limit entre 1 e 100")

    state_path = Path(args.state_file)
    qa_path = Path(args.qa_file)
    profile_path = Path(args.profile_file)
    sessions_dir = Path(args.sessions_dir)
    sessions_dir.mkdir(parents=True, exist_ok=True)

    if args.reset:
        state = {}
    else:
        state = load_json(state_path, {})

    channels = fetch_channels(args.guild_id)
    channel_order = [c["id"] for c in channels]

    channels_state = state.get("channels") if isinstance(state.get("channels"), dict) else {}
    for ch in channels:
        st = channels_state.get(ch["id"], {})
        channels_state[ch["id"]] = {
            "name": ch["name"],
            "type": ch["type"],
            "beforeId": str(st.get("beforeId") or ""),
            "completed": bool(st.get("completed")),
            "processedPages": int(st.get("processedPages") or 0),
            "processedMessages": int(st.get("processedMessages") or 0),
            "newerContext": st.get("newerContext") if isinstance(st.get("newerContext"), list) else [],
            "lastSessionAt": str(st.get("lastSessionAt") or ""),
        }

    state.setdefault("totals", {})
    totals = state["totals"]
    totals.setdefault("sessions", 0)
    totals.setdefault("messagesScanned", 0)
    totals.setdefault("qaPairs", 0)
    totals.setdefault("channelsCompleted", 0)

    start_idx = int(state.get("nextChannelIndex") or 0)
    selected_channels, next_idx = pick_channels_to_process(channel_order, channels_state, start_idx, args.max_channels)

    seen_question_ids = load_seen_question_ids(qa_path)
    profile = load_json(profile_path, {"createdAt": now_iso()})

    session_qa = []
    session_bot_messages = 0
    session_messages_scanned = 0
    session_pages_fetched = 0
    completed_now = []
    processed_channel_rows = []

    for cid in selected_channels:
        ch_state = channels_state[cid]
        before_id = str(ch_state.get("beforeId") or "")
        fetched_pages = 0
        fetched_msgs = []

        for _ in range(args.max_pages_per_channel):
            page = read_messages_page(cid, args.limit, before_id)
            fetched_pages += 1
            session_pages_fetched += 1
            if not page:
                ch_state["completed"] = True
                completed_now.append(cid)
                break

            fetched_msgs.extend(page)
            oldest_id = str((page[-1] or {}).get("id") or "")
            if not oldest_id:
                break
            before_id = oldest_id

        if fetched_msgs:
            compact_chunk = [compact_message(m) for m in fetched_msgs]
            compact_chunk = [m for m in compact_chunk if m.get("id") and int(m.get("timestampMs") or 0) > 0]
            compact_chunk.sort(key=lambda m: int(m.get("timestampMs") or 0))

            current_ids = {m["id"] for m in compact_chunk}
            context_msgs = [m for m in (ch_state.get("newerContext") or []) if isinstance(m, dict)]
            context_msgs = [m for m in context_msgs if m.get("id") and int(m.get("timestampMs") or 0) > 0]

            merged = {m["id"]: m for m in context_msgs}
            for m in compact_chunk:
                merged[m["id"]] = m
            combined = sorted(merged.values(), key=lambda m: int(m.get("timestampMs") or 0))

            pairs = extract_pairs(
                combined,
                current_ids,
                args.bot_id,
                cid,
                ch_state.get("name", ""),
                seen_question_ids,
                args.max_follow_messages,
                args.max_follow_minutes,
            )
            session_qa.extend(pairs)

            bot_msgs = [m for m in compact_chunk if is_bot_message(m, args.bot_id)]
            session_bot_messages += len(bot_msgs)
            update_profile(profile, bot_msgs, pairs, cid, ch_state.get("name", ""))

            boundary_context = compact_chunk[: max(1, args.context_window)]
            ch_state["newerContext"] = boundary_context
            ch_state["beforeId"] = str(compact_chunk[0]["id"])
            ch_state["processedMessages"] = int(ch_state.get("processedMessages") or 0) + len(compact_chunk)
            ch_state["processedPages"] = int(ch_state.get("processedPages") or 0) + fetched_pages
            ch_state["lastSessionAt"] = now_iso()

            session_messages_scanned += len(compact_chunk)
            processed_channel_rows.append(
                {
                    "channelId": cid,
                    "channelName": ch_state.get("name", ""),
                    "messages": len(compact_chunk),
                    "pages": fetched_pages,
                    "qaPairs": len(pairs),
                    "completed": bool(ch_state.get("completed")),
                }
            )
        else:
            ch_state["processedPages"] = int(ch_state.get("processedPages") or 0) + fetched_pages
            ch_state["lastSessionAt"] = now_iso()
            processed_channel_rows.append(
                {
                    "channelId": cid,
                    "channelName": ch_state.get("name", ""),
                    "messages": 0,
                    "pages": fetched_pages,
                    "qaPairs": 0,
                    "completed": bool(ch_state.get("completed")),
                }
            )

    if session_qa:
        qa_path.parent.mkdir(parents=True, exist_ok=True)
        with qa_path.open("a", encoding="utf-8") as fh:
            for item in session_qa:
                fh.write(json.dumps(item, ensure_ascii=False) + "\n")

    summarize_profile(profile)
    profile["updatedAt"] = now_iso()
    profile["guildId"] = args.guild_id
    profile["botId"] = args.bot_id
    save_json(profile_path, profile)

    state["guildId"] = args.guild_id
    state["botId"] = args.bot_id
    state["channelOrder"] = channel_order
    state["channels"] = channels_state
    state["nextChannelIndex"] = next_idx
    state["updatedAt"] = now_iso()

    totals["sessions"] = int(totals.get("sessions") or 0) + 1
    totals["messagesScanned"] = int(totals.get("messagesScanned") or 0) + session_messages_scanned
    totals["qaPairs"] = int(totals.get("qaPairs") or 0) + len(session_qa)
    totals["channelsCompleted"] = sum(1 for cid in channel_order if bool((channels_state.get(cid) or {}).get("completed")))

    save_json(state_path, state)

    pending_channels = sum(1 for cid in channel_order if not bool((channels_state.get(cid) or {}).get("completed")))
    summary = {
        "sessionAt": now_iso(),
        "guildId": args.guild_id,
        "botId": args.bot_id,
        "channelsAvailable": len(channel_order),
        "channelsProcessed": len(processed_channel_rows),
        "channelsCompletedNow": len(set(completed_now)),
        "channelsPending": pending_channels,
        "messagesScanned": session_messages_scanned,
        "pagesFetched": session_pages_fetched,
        "botMessagesSeen": session_bot_messages,
        "qaPairsAdded": len(session_qa),
        "qaFile": str(qa_path),
        "profileFile": str(profile_path),
        "stateFile": str(state_path),
        "processedChannels": processed_channel_rows,
        "nextChannelIndex": next_idx,
    }

    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    save_json(sessions_dir / f"session-{ts}.json", summary)

    if args.output == "text":
        print(f"Sessao concluida: canais={summary['channelsProcessed']} mensagens={summary['messagesScanned']} qa={summary['qaPairsAdded']} pendentes={summary['channelsPending']}")
    else:
        print(json.dumps(summary, ensure_ascii=False, indent=2))

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("interrompido", file=sys.stderr)
        raise SystemExit(130)
