#!/usr/bin/env bash
set -euo pipefail
ROOT="${OPENCLAW_CONFIG_DIR:-/private/var/www/openclaw}"
REPORT_JSON="${1:-}"
if [[ -z "$REPORT_JSON" ]]; then
  REPORT_JSON=$(ls -1t "$ROOT"/workspace/reports/ecosystem-300-tests-*.json 2>/dev/null | head -n1 || true)
fi
if [[ -z "$REPORT_JSON" || ! -f "$REPORT_JSON" ]]; then
  echo "usage: $0 <report.json>" >&2
  exit 1
fi
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/workspace/reports/ecosystem-demands-auto-$TS.md"
python3 - "$REPORT_JSON" "$OUT" <<'PY'
import json,sys
src,out=sys.argv[1:3]
data=json.load(open(src,'r',encoding='utf-8'))
critical=data.get('critical',[])
warning=data.get('warning',[])

mapping={
  'c408ba92-a26a-420d-844f-64448f983d93':'Governança',
  '59c24991-af6c-4df2-95fe-bbf012cd73c0':'Otimizador',
  '985165be-59eb-46e7-8715-17571c8e8227':'Presidente',
  '99de71d1-97b0-48d0-933e-7fcacfda2184':'Mail-Pro',
  'e4cd9635-efdd-4588-8ecc-523a4a50ea20':'Mail-Person',
  '6bdd82c7-081d-486b-9700-0572b9fce72e':'Engenheiro de Prompt',
  'a7b8c9d0-e1f2-3456-7890-abcdef123401':'Engenheiro SmartEnvios',
  '79672496-e2c8-4851-9f19-98b5efafa2ff':'Engenheiro de Automação',
  '7fba5b1f-2ee9-4b1e-aae0-bd211c32b925':'Diretor Tech',
  'a71c2958-e52f-4f37-9876-bedf6dcb9434':'Diretor Pessoal',
  'cf343b94-0816-42e5-b3dc-d40ecf12786e':'Diretor Negócios',
  '0633c77a-4e3f-47fa-82be-35767e806836':'Main',
}

lines=[]
lines.append('# Demandas automáticas de melhoria do ecossistema\n')
lines.append(f'- Fonte: `{src}`\n')
lines.append('## Críticas\n')
if not critical:
  lines.append('- Nenhuma crítica detectada.\n')
else:
  for c in critical:
    aid=mapping.get(c['jobId'],c['jobId'])
    lines.append(f"- [{aid}] Corrigir gargalo de execução (okRate={c['okRate']}%, p95={c['p95Ms']/1000:.1f}s, max={c['maxMs']/1000:.1f}s).")
    lines.append('  Ação: revisar timeout, agenda e evidência de erro; aplicar micro-batches e validação pós-execução.\n')

lines.append('## Alertas\n')
if not warning:
  lines.append('- Nenhum alerta detectado.\n')
else:
  for c in warning:
    aid=mapping.get(c['jobId'],c['jobId'])
    lines.append(f"- [{aid}] Melhorar estabilidade (okRate={c['okRate']}%, p95={c['p95Ms']/1000:.1f}s).\n")

open(out,'w',encoding='utf-8').write('\n'.join(lines))
print(out)
PY
