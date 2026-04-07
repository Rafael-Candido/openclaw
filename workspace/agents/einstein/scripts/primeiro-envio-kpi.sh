#!/usr/bin/env bash
set -euo pipefail

CHANNEL_ID="${PRIMEIRO_ENVIO_CHANNEL_ID:-1338557426861084825}"
TIMEZONE="${TIMEZONE:-America/Sao_Paulo}"
LIMIT="${LIMIT:-25}"
MAX_PAGES="${MAX_PAGES:-200}"
START_DATE=""
END_DATE=""
OUTPUT="json"
INCLUDE_ENTRIES="false"

usage() {
  cat <<'EOF'
Uso:
  primeiro-envio-kpi.sh [opcoes]

Opcoes:
  --channel-id <id>         ID do canal Discord (default: #primeiro-envio)
  --start-date <YYYY-MM-DD> Data inicial (inclusive)
  --end-date <YYYY-MM-DD>   Data final (inclusive)
  --timezone <tz>           Timezone IANA (default: America/Sao_Paulo)
  --limit <n>               Limite por pagina (default: 25, max: 100)
  --max-pages <n>           Maximo de paginas para varrer (default: 200)
  --output <json|text>      Formato de saida (default: json)
  --include-entries         Inclui lista resumida de eventos na saida JSON
  --help                    Mostra esta ajuda

Sem datas explicitas, usa a semana atual no padrao domingo-sabado.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel-id)
      CHANNEL_ID="${2:-}"
      shift 2
      ;;
    --start-date)
      START_DATE="${2:-}"
      shift 2
      ;;
    --end-date)
      END_DATE="${2:-}"
      shift 2
      ;;
    --timezone)
      TIMEZONE="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --max-pages)
      MAX_PAGES="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --include-entries)
      INCLUDE_ENTRIES="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Argumento invalido: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "${CHANNEL_ID}" ]] || { echo "Erro: --channel-id vazio" >&2; exit 1; }
[[ "${LIMIT}" =~ ^[0-9]+$ ]] || { echo "Erro: --limit invalido" >&2; exit 1; }
[[ "${MAX_PAGES}" =~ ^[0-9]+$ ]] || { echo "Erro: --max-pages invalido" >&2; exit 1; }
(( LIMIT >= 1 && LIMIT <= 100 )) || { echo "Erro: --limit deve estar entre 1 e 100" >&2; exit 1; }
(( MAX_PAGES >= 1 )) || { echo "Erro: --max-pages deve ser >= 1" >&2; exit 1; }
[[ "${OUTPUT}" == "json" || "${OUTPUT}" == "text" ]] || { echo "Erro: --output deve ser json ou text" >&2; exit 1; }

range_json="$(python3 - <<'PY' "${START_DATE}" "${END_DATE}" "${TIMEZONE}"
import datetime as dt
import json
import sys
from zoneinfo import ZoneInfo

start_arg = (sys.argv[1] or "").strip()
end_arg = (sys.argv[2] or "").strip()
tz_name = (sys.argv[3] or "").strip() or "America/Sao_Paulo"

try:
    tz = ZoneInfo(tz_name)
except Exception:
    print(json.dumps({"error": f"timezone invalida: {tz_name}"}))
    raise SystemExit(1)

if bool(start_arg) ^ bool(end_arg):
    print(json.dumps({"error": "forneca start-date e end-date juntos"}))
    raise SystemExit(1)

if start_arg and end_arg:
    try:
        start_date = dt.date.fromisoformat(start_arg)
        end_date = dt.date.fromisoformat(end_arg)
    except Exception:
        print(json.dumps({"error": "datas invalidas (formato esperado: YYYY-MM-DD)"}))
        raise SystemExit(1)
else:
    now_local = dt.datetime.now(tz)
    today = now_local.date()
    # padrao operacional: semana domingo-sabado
    days_since_sunday = (today.weekday() + 1) % 7
    start_date = today - dt.timedelta(days=days_since_sunday)
    end_date = start_date + dt.timedelta(days=6)

if end_date < start_date:
    print(json.dumps({"error": "end-date menor que start-date"}))
    raise SystemExit(1)

start_dt = dt.datetime.combine(start_date, dt.time.min, tzinfo=tz)
end_dt = dt.datetime.combine(end_date, dt.time.max, tzinfo=tz)

payload = {
    "timezone": tz_name,
    "start_date": start_date.isoformat(),
    "end_date": end_date.isoformat(),
    "start_ms": int(start_dt.timestamp() * 1000),
    "end_ms": int(end_dt.timestamp() * 1000),
    "label_ptbr": f"{start_date.strftime('%d/%m/%Y')} a {end_date.strftime('%d/%m/%Y')}",
}
print(json.dumps(payload, ensure_ascii=False))
PY
)"

if jq -e '.error' >/dev/null 2>&1 <<<"${range_json}"; then
  jq -r '.error' <<<"${range_json}" >&2
  exit 1
fi

start_ms="$(jq -r '.start_ms' <<<"${range_json}")"
end_ms="$(jq -r '.end_ms' <<<"${range_json}")"

tmp_msgs="$(mktemp)"
trap 'rm -f "${tmp_msgs}"' EXIT

before_id=""
pages_fetched=0
messages_scanned=0
partial="false"

while (( pages_fetched < MAX_PAGES )); do
  current_limit="${LIMIT}"
  msgs_json=""
  page_out=""
  while :; do
    if [[ -n "${before_id}" ]]; then
      cmd=(openclaw message read --channel discord --target "channel:${CHANNEL_ID}" --limit "${current_limit}" --before "${before_id}" --json)
    else
      cmd=(openclaw message read --channel discord --target "channel:${CHANNEL_ID}" --limit "${current_limit}" --json)
    fi

    page_out="$("${cmd[@]}")"
    if msgs_json="$(jq -c '.payload.messages // []' <<<"${page_out}" 2>/dev/null)"; then
      break
    fi

    # Workaround: o CLI pode retornar JSON quebrado em paginas maiores.
    # Rebaixa o page-size e retenta automaticamente.
    if (( current_limit > 25 )); then
      current_limit=25
      continue
    fi
    if (( current_limit > 10 )); then
      current_limit=10
      continue
    fi
    echo "Erro: nao foi possivel parsear resposta JSON de openclaw message read" >&2
    exit 1
  done

  page_count="$(jq -r 'length' <<<"${msgs_json}")"

  (( pages_fetched += 1 ))

  if (( page_count == 0 )); then
    break
  fi

  jq -c '.[]' <<<"${msgs_json}" >>"${tmp_msgs}"
  (( messages_scanned += page_count ))

  oldest_ms="$(jq -r '.[-1].timestampMs // 0' <<<"${msgs_json}")"
  oldest_id="$(jq -r '.[-1].id // empty' <<<"${msgs_json}")"
  if [[ -z "${oldest_id}" ]]; then
    break
  fi

  # Como a pagina ja veio ordenada do mais novo para o mais antigo,
  # se o mais antigo da pagina for anterior ao inicio da janela, nao
  # precisamos buscar paginas ainda mais antigas.
  if [[ "${oldest_ms}" =~ ^[0-9]+$ ]] && (( oldest_ms < start_ms )); then
    break
  fi

  before_id="${oldest_id}"
done

if (( pages_fetched >= MAX_PAGES )); then
  partial="true"
fi

summary_json="$(python3 - <<'PY' "${tmp_msgs}" "${start_ms}" "${end_ms}" "${range_json}" "${CHANNEL_ID}" "${messages_scanned}" "${pages_fetched}" "${partial}" "${INCLUDE_ENTRIES}"
import datetime as dt
import json
import re
import sys
from pathlib import Path

msgs_path = Path(sys.argv[1])
start_ms = int(sys.argv[2])
end_ms = int(sys.argv[3])
range_json = json.loads(sys.argv[4])
channel_id = sys.argv[5]
messages_scanned = int(sys.argv[6])
pages_fetched = int(sys.argv[7])
partial = (sys.argv[8] == "true")
include_entries = (sys.argv[9] == "true")

marker_pat = re.compile(r"fez\s+o\s+primeiro\s+envio", re.IGNORECASE)
name_pat = re.compile(r"##\s*(.*?)\s*Fez o Primeiro Envio", re.IGNORECASE)
value_pat = re.compile(r"Proje[çc][aã]o de faturamento:\*+\s*([^\n\r]+)", re.IGNORECASE)
digits_pat = re.compile(r"[^0-9,.\-]")

def parse_brl_number(raw: str):
    text = (raw or "").strip()
    if not text:
        return None
    text = digits_pat.sub("", text)
    if not text:
        return None
    # Regras para pt-BR e entradas simples
    if "," in text and "." in text:
        text = text.replace(".", "").replace(",", ".")
    elif "," in text:
        text = text.replace(".", "").replace(",", ".")
    else:
        # se houver varios pontos, assume pontos de milhar
        if text.count(".") > 1:
            text = text.replace(".", "")
    try:
        return float(text)
    except Exception:
        return None

def format_brl(value: float) -> str:
    s = f"{value:,.2f}"
    s = s.replace(",", "X").replace(".", ",").replace("X", ".")
    return f"R$ {s}"

total = 0.0
count = 0
events = []
entries = []

if msgs_path.exists():
    for line in msgs_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue

        ts_ms = msg.get("timestampMs")
        if not isinstance(ts_ms, int):
            continue
        if ts_ms < start_ms or ts_ms > end_ms:
            continue

        content = msg.get("content") or ""
        if not marker_pat.search(content):
            continue

        count += 1
        value = 0.0
        raw_value = ""
        m_value = value_pat.search(content)
        if m_value:
            raw_value = m_value.group(1).strip()
            parsed = parse_brl_number(raw_value)
            if parsed is not None:
                value = parsed

        total += value

        m_name = name_pat.search(content)
        name = (m_name.group(1).strip() if m_name else "")

        ts_utc = dt.datetime.fromtimestamp(ts_ms / 1000.0, tz=dt.timezone.utc)
        events.append(
            {
                "id": msg.get("id"),
                "timestampMs": ts_ms,
                "timestampUtc": ts_utc.isoformat(timespec="seconds").replace("+00:00", "Z"),
                "name": name,
                "value": value,
                "rawValue": raw_value,
            }
        )

events.sort(key=lambda e: e["timestampMs"])

if include_entries:
    entries = [
        {
            "name": e["name"],
            "value": e["value"],
            "valueBrl": format_brl(e["value"]),
            "timestampUtc": e["timestampUtc"],
        }
        for e in events
    ]

result = {
    "ok": True,
    "metric": "primeiro_envio_semana",
    "channel_id": channel_id,
    "period": {
        "timezone": range_json["timezone"],
        "start_date": range_json["start_date"],
        "end_date": range_json["end_date"],
        "label_ptbr": range_json["label_ptbr"],
    },
    "first_shipments_count": count,
    "total_opportunity_value": round(total, 2),
    "total_opportunity_value_brl": format_brl(total),
    "messages_scanned": messages_scanned,
    "pages_fetched": pages_fetched,
    "partial": partial,
}

if include_entries:
    result["entries"] = entries

print(json.dumps(result, ensure_ascii=False))
PY
)"

if [[ "${OUTPUT}" == "json" ]]; then
  printf '%s\n' "${summary_json}"
  exit 0
fi

python3 - <<'PY' "${summary_json}"
import json
import sys

obj = json.loads(sys.argv[1])
count = obj.get("first_shipments_count", 0)
total_brl = obj.get("total_opportunity_value_brl", "R$ 0,00")
period = ((obj.get("period") or {}).get("label_ptbr")) or ""
partial = obj.get("partial")

lines = [
    f"Tivemos {count} primeiros envios na semana ({period}).",
    f"Valor total de oportunidade: {total_brl}.",
]

if partial:
    lines.append("Observação: leitura parcial (limite de páginas atingido).")

print("\n".join(lines))
PY
