#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_CONFIG_DIR:-/private/var/www/openclaw}"
RUNS_DIR="$ROOT/cron/runs"
OUT_DIR="$ROOT/workspace/reports"
mkdir -p "$OUT_DIR"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_JSON="$OUT_DIR/ecosystem-300-tests-$TS.json"
OUT_MD="$OUT_DIR/ecosystem-300-tests-$TS.md"

# 300 tests = 12 jobs * últimas 25 execuções finished
python3 - "$RUNS_DIR" "$OUT_JSON" "$OUT_MD" <<'PY'
import json,glob,os,sys,statistics,re
from collections import defaultdict,Counter

runs_dir,out_json,out_md=sys.argv[1:4]
files=sorted(glob.glob(os.path.join(runs_dir,'*.jsonl')))
per_job=25
rows=[]
error_samples=defaultdict(list)
for fp in files:
    job=os.path.basename(fp)[:-6]
    items=[]
    with open(fp,'r',encoding='utf-8',errors='ignore') as f:
        for ln in f:
            ln=ln.strip()
            if not ln: continue
            try:
                j=json.loads(ln)
            except Exception:
                continue
            if j.get('action')=='finished':
                items.append(j)
    items=items[-per_job:]
    for j in items:
        st=j.get('status','unknown')
        dur=int(j.get('durationMs') or 0)
        err=str(j.get('error') or '')
        if st!='ok' and err:
            error_samples[job].append(err[:300])
        cause='ok'
        low=(err or '').lower()
        if st!='ok':
            if 'timeout' in low: cause='timeout'
            elif 'gateway' in low: cause='gateway'
            elif 'rate limit' in low: cause='rate_limit'
            elif 'token' in low or 'unauthorized' in low: cause='token_auth'
            elif 'delivery' in low: cause='delivery'
            else: cause='other_error'
        rows.append({'jobId':job,'status':st,'durationMs':dur,'cause':cause,'error':err})

# ensure exactly 300 checks target (sample/cap)
rows=rows[:300]
by=defaultdict(list)
for r in rows:
    by[r['jobId']].append(r)

job_stats=[]
cause_counter=Counter(r['cause'] for r in rows)
for job,it in sorted(by.items()):
    d=[x['durationMs'] for x in it]
    ok=sum(1 for x in it if x['status']=='ok')
    fail=len(it)-ok
    p95=sorted(d)[max(0,min(len(d)-1,(len(d)*95+99)//100-1))] if d else 0
    job_stats.append({
        'jobId':job,'tests':len(it),'ok':ok,'fail':fail,
        'okRate':round((ok/len(it))*100,2) if it else 0.0,
        'avgMs':round(sum(d)/len(d),2) if d else 0,
        'p95Ms':p95,'maxMs':max(d) if d else 0,
        'topCauses':Counter(x['cause'] for x in it if x['cause']!='ok').most_common(3),
        'sampleErrors':error_samples.get(job,[])[:3],
    })

crit=[x for x in job_stats if x['okRate']<90 or x['p95Ms']>120000]
warn=[x for x in job_stats if 90<=x['okRate']<97 or x['p95Ms']>60000]

obj={
    'summary':{
        'tests':len(rows),
        'jobs':len(job_stats),
        'overallOkRate':round((sum(1 for r in rows if r['status']=='ok')/len(rows))*100,2) if rows else 0,
        'causes':dict(cause_counter),
    },
    'critical':crit,
    'warning':warn,
    'jobs':job_stats,
}

with open(out_json,'w',encoding='utf-8') as f:
    json.dump(obj,f,ensure_ascii=False,indent=2)

with open(out_md,'w',encoding='utf-8') as f:
    f.write(f"# Ecosystem 300 Tests ({len(rows)} checks)\n\n")
    f.write(f"- Overall OK rate: {obj['summary']['overallOkRate']}%\n")
    f.write(f"- Causes: {obj['summary']['causes']}\n\n")
    f.write("## Critical\n")
    if not crit:
        f.write("- none\n")
    else:
        for c in crit:
            f.write(f"- {c['jobId']}: okRate={c['okRate']}% p95={c['p95Ms']/1000:.1f}s max={c['maxMs']/1000:.1f}s causes={c['topCauses']}\n")
    f.write("\n## Warning\n")
    if not warn:
        f.write("- none\n")
    else:
        for c in warn:
            f.write(f"- {c['jobId']}: okRate={c['okRate']}% p95={c['p95Ms']/1000:.1f}s max={c['maxMs']/1000:.1f}s causes={c['topCauses']}\n")

print(out_json)
print(out_md)
print(json.dumps(obj['summary'],ensure_ascii=False))
PY
