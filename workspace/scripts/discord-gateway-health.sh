#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/var/www/openclaw}"
WINDOW_MIN="${DISCORD_HEALTH_WINDOW_MIN:-20}"
LOGIN_STALE_MIN="${DISCORD_LOGIN_STALE_MIN:-15}"
ERROR_SCORE_THRESHOLD="${DISCORD_ERROR_SCORE_THRESHOLD:-3}"

[[ "${WINDOW_MIN}" =~ ^[0-9]+$ ]] || WINDOW_MIN=20
[[ "${LOGIN_STALE_MIN}" =~ ^[0-9]+$ ]] || LOGIN_STALE_MIN=15
[[ "${ERROR_SCORE_THRESHOLD}" =~ ^[0-9]+$ ]] || ERROR_SCORE_THRESHOLD=3

RUNTIME_STATUS_JSON="$(openclaw channels status --probe --json 2>/dev/null || echo '{}')"

python3 - "${OPENCLAW_CONFIG_DIR}" "${WINDOW_MIN}" "${LOGIN_STALE_MIN}" "${ERROR_SCORE_THRESHOLD}" "${RUNTIME_STATUS_JSON}" <<'PY'
import datetime as dt
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
window_min = int(sys.argv[2])
login_stale_min = int(sys.argv[3])
score_threshold = int(sys.argv[4])
runtime_raw = sys.argv[5] if len(sys.argv) > 5 else "{}"

try:
    runtime = json.loads(runtime_raw) if runtime_raw else {}
except Exception:
    runtime = {}

runtime_channels = runtime.get("channels") if isinstance(runtime, dict) else {}
runtime_channel_accounts = runtime.get("channelAccounts") if isinstance(runtime, dict) else {}

runtime_discord = {}
if isinstance(runtime_channels, dict):
    runtime_discord = runtime_channels.get("discord") or {}
if not isinstance(runtime_discord, dict):
    runtime_discord = {}

runtime_discord_account = {}
if isinstance(runtime_channel_accounts, dict):
    accounts = runtime_channel_accounts.get("discord") or []
    if isinstance(accounts, list) and accounts:
        candidate = accounts[0]
        if isinstance(candidate, dict):
            runtime_discord_account = candidate

runtime_connected = runtime_discord_account.get("connected")
if runtime_connected is None:
    runtime_connected = runtime_discord.get("connected")
runtime_running = runtime_discord_account.get("running")
if runtime_running is None:
    runtime_running = runtime_discord.get("running")
runtime_last_error = runtime_discord_account.get("lastError") or runtime_discord.get("lastError")
runtime_last_connected_at = runtime_discord_account.get("lastConnectedAt")
runtime_probe = runtime_discord.get("probe") if isinstance(runtime_discord.get("probe"), dict) else {}
runtime_probe_ok = runtime_probe.get("ok")

gateway_log = root / "logs" / "gateway.log"
gateway_err = root / "logs" / "gateway.err.log"

iso_pat = re.compile(r'time":"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)')
clock_pat = re.compile(r'(^|\s)(\d{2}:\d{2}:\d{2})\s+\[')

dns_pat = re.compile(
    r"(getaddrinfo\s+(ENOTFOUND|EAI_AGAIN)|ENOTFOUND\s+gateway|ENOTFOUND.*discord\.gg|discord\.gg.*ENOTFOUND)",
    re.IGNORECASE,
)
max_reconnect_pat = re.compile(r"max reconnect attempts", re.IGNORECASE)
ws_preclose_pat = re.compile(
    r"websocket was closed before the connection was established",
    re.IGNORECASE,
)


def read_tail_lines(path, max_bytes=2_000_000):
    if not path.exists():
        return []
    try:
        raw = path.read_bytes()[-max_bytes:]
    except Exception:
        return []
    return raw.decode("utf-8", errors="ignore").splitlines()


def parse_ts(line, now_local):
    m = iso_pat.search(line)
    if m:
        raw = m.group(1)
        try:
            if raw.endswith("Z"):
                raw = raw[:-1] + "+00:00"
            parsed = dt.datetime.fromisoformat(raw)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=now_local.tzinfo)
            return parsed.timestamp()
        except Exception:
            pass

    m = clock_pat.search(line)
    if m:
        hh, mm, ss = map(int, m.group(2).split(":"))
        parsed = now_local.replace(hour=hh, minute=mm, second=ss, microsecond=0)
        if parsed.timestamp() > now_local.timestamp() + 60:
            parsed = parsed - dt.timedelta(days=1)
        return parsed.timestamp()
    return None


now_local = dt.datetime.now().astimezone()
now_ts = now_local.timestamp()
cutoff_ts = now_ts - (max(1, window_min) * 60)

log_lines = read_tail_lines(gateway_log)
err_lines = read_tail_lines(gateway_err)

if not log_lines and not err_lines and runtime_connected is not True:
    print(
        json.dumps(
            {
                "ok": False,
                "status": "logs-missing",
                "issue": True,
                "reason": "logs-missing",
                "windowMin": window_min,
                "loginStaleMin": login_stale_min,
                "threshold": score_threshold,
                "errorScore": 0,
                "dnsErrors": 0,
                "maxReconnectErrors": 0,
                "websocketPrecloseErrors": 0,
                "lastDiscordLoginAgeMin": -1,
                "lastDiscordLoginIso": "",
                "runtimeConnected": runtime_connected,
                "runtimeRunning": runtime_running,
                "runtimeProbeOk": runtime_probe_ok,
                "runtimeLastConnectedAt": runtime_last_connected_at,
                "runtimeLastError": runtime_last_error,
            },
            ensure_ascii=False,
        )
    )
    raise SystemExit(0)

error_events = []
for line in err_lines:
    ts = parse_ts(line, now_local)
    if ts is not None and ts < cutoff_ts:
        continue
    if dns_pat.search(line):
        error_events.append((ts, "dns"))
    if max_reconnect_pat.search(line):
        error_events.append((ts, "reconnect"))
    if ws_preclose_pat.search(line):
        error_events.append((ts, "ws_preclose"))

last_login_ts = None
for line in log_lines:
    if "[discord] logged in to discord as" not in line:
        continue
    ts = parse_ts(line, now_local)
    if ts is None:
        continue
    if last_login_ts is None or ts > last_login_ts:
        last_login_ts = ts

if last_login_ts is None and runtime_last_connected_at:
    try:
        last_login_ts = int(runtime_last_connected_at) / 1000.0
    except (ValueError, TypeError):
        pass

if last_login_ts is None:
    last_login_age_min = -1
    last_login_iso = ""
else:
    last_login_age_min = int(max(0, (now_ts - last_login_ts) // 60))
    last_login_iso = dt.datetime.fromtimestamp(last_login_ts, tz=now_local.tzinfo).isoformat(timespec="seconds")

recent_login = last_login_age_min >= 0 and last_login_age_min <= login_stale_min

def count_events(events, from_ts=None):
    dns = 0
    reconnect = 0
    ws_preclose = 0
    for ts, kind in events:
        if from_ts is not None and ts is not None and ts < from_ts:
            continue
        if kind == "dns":
            dns += 1
        elif kind == "reconnect":
            reconnect += 1
        elif kind == "ws_preclose":
            ws_preclose += 1
    return dns, reconnect, ws_preclose


dns_errors, max_reconnect_errors, ws_preclose_errors = count_events(error_events, None)

# Se houve login recente, só consideramos erro ocorrido após esse login.
# Isso evita falso positivo quando a conexão já recuperou e os erros ficaram no histórico.
if recent_login and last_login_ts is not None:
    post_dns, post_reconnect, post_ws_preclose = count_events(error_events, last_login_ts)
    if (post_dns + post_reconnect + post_ws_preclose) == 0:
        dns_errors = 0
        max_reconnect_errors = 0
        ws_preclose_errors = 0
    else:
        dns_errors = post_dns
        max_reconnect_errors = post_reconnect
        ws_preclose_errors = post_ws_preclose

error_score = (dns_errors * 2) + max_reconnect_errors + ws_preclose_errors

issue = False
reason = "stable"

stale_login_threshold_min = max(login_stale_min * 3, 60)
login_very_stale = last_login_age_min >= stale_login_threshold_min or last_login_age_min < 0

# Fonte primária: runtime do gateway.
# Se o runtime já reporta conexão ativa, tratamos como saudável mesmo com ruído de log histórico.
if runtime_connected is True:
    issue = False
    reason = "runtime-connected"
elif runtime_running is True and runtime_connected is False:
    issue = True
    reason = "runtime-disconnected"
elif error_score >= score_threshold:
    issue = True
    reason = "error-score"
elif error_score > 0 and not recent_login:
    issue = True
    reason = "errors-without-recent-login"
elif login_very_stale and runtime_connected is not True:
    issue = True
    reason = "login-stale-no-runtime"

status = "alert" if issue else "healthy"
result = {
    "ok": True,
    "status": status,
    "issue": issue,
    "reason": reason,
    "windowMin": window_min,
    "loginStaleMin": login_stale_min,
    "staleLoginThresholdMin": stale_login_threshold_min,
    "loginVeryStale": login_very_stale,
    "threshold": score_threshold,
    "errorScore": error_score,
    "dnsErrors": dns_errors,
    "maxReconnectErrors": max_reconnect_errors,
    "websocketPrecloseErrors": ws_preclose_errors,
    "lastDiscordLoginAgeMin": last_login_age_min,
    "lastDiscordLoginIso": last_login_iso,
    "runtimeConnected": runtime_connected,
    "runtimeRunning": runtime_running,
    "runtimeProbeOk": runtime_probe_ok,
    "runtimeLastConnectedAt": runtime_last_connected_at,
    "runtimeLastError": runtime_last_error,
}
print(json.dumps(result, ensure_ascii=False))
PY
