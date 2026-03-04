#!/usr/bin/env python3
import json
import os
import urllib.request
import urllib.parse

ENV_PATH = '/private/var/www/openclaw/.env'


def read_env(key: str, default: str = '') -> str:
    if key in os.environ and os.environ[key]:
        return os.environ[key]
    try:
        with open(ENV_PATH, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                k, v = line.split('=', 1)
                if k.strip() == key:
                    v = v.strip().strip('"').strip("'")
                    return v
    except FileNotFoundError:
        pass
    return default

BASE = read_env('N8N_API_BASE_URL', 'https://n8n.smartenvios.tec.br/api/v1').rstrip('/')
KEY = read_env('N8N_SALES_API_KEY')
PIPEDRIVE_TOKEN = read_env('PIPEDRIVE_API_TOKEN', 'e86b1f242ceb1e28328e075a09cd0b078f0910a4')

if not KEY:
    raise SystemExit('N8N_SALES_API_KEY missing')


def req(method: str, path: str, data=None):
    url = f"{BASE}{path}"
    headers = {
        'X-N8N-API-KEY': KEY,
        'Content-Type': 'application/json',
    }
    payload = None
    if data is not None:
        payload = json.dumps(data).encode('utf-8')
    r = urllib.request.Request(url, method=method, headers=headers, data=payload)
    with urllib.request.urlopen(r, timeout=60) as resp:
        raw = resp.read().decode('utf-8')
        return json.loads(raw) if raw else {}


def list_workflows():
    out = []
    cursor = None
    while True:
        q = '/workflows?limit=250'
        if cursor:
            q += '&cursor=' + urllib.parse.quote(cursor)
        data = req('GET', q)
        out.extend(data.get('data', []))
        cursor = data.get('nextCursor')
        if not cursor:
            break
    return out


def upsert_workflow(name: str, nodes, connections, settings=None):
    settings = settings or {"executionOrder": "v1"}
    all_wf = list_workflows()
    found = next((w for w in all_wf if (w.get('name') or '').strip() == name.strip()), None)
    payload = {
        'name': name,
        'nodes': nodes,
        'connections': connections,
        'settings': settings,
    }
    if found:
        wid = found['id']
        req('PUT', f'/workflows/{wid}', payload)
        return wid, 'updated'
    created = req('POST', '/workflows', payload)
    return created.get('id', ''), 'created'


# 1) Shared subworkflow: Pipedrive activity creator
sub_pipe_name = 'CadencyShared - Create Pipedrive Activity v1'
sub_pipe_nodes = [
    {
        'id': 'exec-trigger',
        'name': 'Execute Workflow Trigger',
        'type': 'n8n-nodes-base.executeWorkflowTrigger',
        'typeVersion': 1,
        'position': [240, 240],
        'parameters': {},
    },
    {
        'id': 'http-create-activity',
        'name': 'Create Pipedrive Activity',
        'type': 'n8n-nodes-base.httpRequest',
        'typeVersion': 4.2,
        'position': [540, 240],
        'parameters': {
            'method': 'POST',
            'url': f'https://smartenvios.pipedrive.com/v1/activities?api_token={PIPEDRIVE_TOKEN}',
            'sendBody': True,
            'contentType': 'json',
            'specifyBody': 'json',
            'jsonBody': '={{ { "subject": $json.subject, "type": $json.type || "task", "due_date": $json.due_date, "due_time": $json.due_time, "lead_id": $json.lead_id, "person_id": $json.person_id, "note": $json.note || "Cadency automation" } }}',
            'options': {'response': {'response': {'neverError': True}}},
        },
    },
]
sub_pipe_conn = {
    'Execute Workflow Trigger': {
        'main': [[{'node': 'Create Pipedrive Activity', 'type': 'main', 'index': 0}]]
    }
}

sub_pipe_id, sub_pipe_action = upsert_workflow(sub_pipe_name, sub_pipe_nodes, sub_pipe_conn)

# 2) Shared subworkflow: CRM activity creator
sub_crm_name = 'CadencyShared - Create CRM Activity v1'
sub_crm_nodes = [
    {
        'id': 'exec-trigger',
        'name': 'Execute Workflow Trigger',
        'type': 'n8n-nodes-base.executeWorkflowTrigger',
        'typeVersion': 1,
        'position': [240, 240],
        'parameters': {},
    },
    {
        'id': 'http-create-crm-activity',
        'name': 'Create CRM Activity',
        'type': 'n8n-nodes-base.httpRequest',
        'typeVersion': 4.2,
        'position': [560, 240],
        'parameters': {
            'method': 'POST',
            'url': '={{($env.CRM_API_BASE_URL || "https://api.smartenvios.tec.br/crm") + "/api/v1/activities"}}',
            'sendHeaders': True,
            'headerParameters': {
                'parameters': [
                    {'name': 'Authorization', 'value': '={{$json.auth_header || ("Bearer " + ($env.CRM_BEARER_TOKEN || ""))}}'},
                    {'name': 'Content-Type', 'value': 'application/json'},
                ]
            },
            'sendBody': True,
            'contentType': 'json',
            'specifyBody': 'json',
            'jsonBody': '={{ { "lead_id": $json.lead_id, "type": $json.type || "call", "scheduled_date": $json.scheduled_date, "scheduled_time": $json.scheduled_time, "title": $json.title, "comment": $json.comment || "Cadency CRM automation", "person_id": $json.person_id } }}',
            'options': {'response': {'response': {'neverError': True}}},
        },
    },
]
sub_crm_conn = {
    'Execute Workflow Trigger': {
        'main': [[{'node': 'Create CRM Activity', 'type': 'main', 'index': 0}]]
    }
}
sub_crm_id, sub_crm_action = upsert_workflow(sub_crm_name, sub_crm_nodes, sub_crm_conn)

# 3) Unified cadency (Pipedrive legacy optimized)
unified_pipe_name = 'CadencyUnified - Pipedrive v2'
unified_pipe_nodes = [
    {
        'id': 'schedule',
        'name': 'Schedule Trigger',
        'type': 'n8n-nodes-base.scheduleTrigger',
        'typeVersion': 1.2,
        'position': [180, 300],
        'parameters': {
            'rule': {
                'interval': [
                    {'field': 'minutes', 'minutesInterval': 15}
                ]
            }
        },
    },
    {
        'id': 'profiles',
        'name': 'Build Cadency Profiles',
        'type': 'n8n-nodes-base.code',
        'typeVersion': 2,
        'position': [420, 300],
        'parameters': {
            'jsCode': 'return [\n  { json: { cadency_name: "Inbound", max_items: 100 } },\n  { json: { cadency_name: "Outbound", max_items: 100 } },\n  { json: { cadency_name: "Evento", max_items: 100 } },\n  { json: { cadency_name: "Influenciador", max_items: 100 } },\n  { json: { cadency_name: "Estagnado", max_items: 100 } },\n];'
        },
    },
    {
        'id': 'split-profiles',
        'name': 'Loop Profiles',
        'type': 'n8n-nodes-base.splitInBatches',
        'typeVersion': 3,
        'position': [650, 300],
        'parameters': {'batchSize': 1},
    },
    {
        'id': 'select-pending',
        'name': 'Select Pending from Cadency Table',
        'type': 'n8n-nodes-base.postgres',
        'typeVersion': 2.6,
        'position': [900, 300],
        'parameters': {
            'operation': 'executeQuery',
            'query': 'SELECT * FROM public.lead_pipedrive_cadency lpc WHERE lpc.cadency_name = \'{{$json.cadency_name}}\' AND COALESCE(lpc.status,\'new\') <> \'done\' ORDER BY lpc.created_at ASC LIMIT {{$json.max_items}};'
        },
        'credentials': {'postgres': {'id': '60gGhjWDWvC4IvZw', 'name': 'N8N comercial DB n8n'}},
    },
    {
        'id': 'loop-leads',
        'name': 'Loop Leads',
        'type': 'n8n-nodes-base.splitInBatches',
        'typeVersion': 3,
        'position': [1140, 300],
        'parameters': {'batchSize': 1},
    },
    {
        'id': 'build-pipedrive-payload',
        'name': 'Build Pipedrive Activity Payload',
        'type': 'n8n-nodes-base.code',
        'typeVersion': 2,
        'position': [1380, 300],
        'parameters': {
            'jsCode': 'const row = $json;\nconst now = new Date();\nconst yyyy = now.getFullYear();\nconst mm = String(now.getMonth()+1).padStart(2,\'0\');\nconst dd = String(now.getDate()).padStart(2,\'0\');\nreturn [{ json: {\n  id: row.id,\n  cadency_name: row.cadency_name,\n  pipedrive_id: row.pipedrive_id,\n  person_id: row.person_id || null,\n  lead_id: row.pipedrive_id,\n  due_date: `${yyyy}-${mm}-${dd}`,\n  due_time: row.due_time || "10:00",\n  type: "task",\n  subject: `[Cadency ${row.cadency_name}] Follow-up automático`,\n  note: `Cadency v2 (unified) - registro ${row.id}`\n}}];'
        },
    },
    {
        'id': 'call-shared-pipedrive',
        'name': 'Call Shared Pipedrive Activity',
        'type': 'n8n-nodes-base.executeWorkflow',
        'typeVersion': 1.2,
        'position': [1620, 300],
        'parameters': {
            'workflowId': {
                '__rl': True,
                'value': sub_pipe_id,
                'mode': 'list',
            },
            'mode': 'each',
            'options': {'waitForSubWorkflow': True}
        },
    },
    {
        'id': 'mark-processed',
        'name': 'Mark Cadency Row Processed',
        'type': 'n8n-nodes-base.postgres',
        'typeVersion': 2.6,
        'position': [1860, 300],
        'parameters': {
            'operation': 'executeQuery',
            'query': "UPDATE public.lead_pipedrive_cadency SET status = 'processing', updated_at = NOW() WHERE id = '{{ $('Build Pipedrive Activity Payload').item.json.id }}';"
        },
        'credentials': {'postgres': {'id': '60gGhjWDWvC4IvZw', 'name': 'N8N comercial DB n8n'}},
    },
]

unified_pipe_conn = {
    'Schedule Trigger': {'main': [[{'node': 'Build Cadency Profiles', 'type': 'main', 'index': 0}]]},
    'Build Cadency Profiles': {'main': [[{'node': 'Loop Profiles', 'type': 'main', 'index': 0}]]},
    'Loop Profiles': {'main': [[{'node': 'Select Pending from Cadency Table', 'type': 'main', 'index': 0}], [{'node': 'Loop Profiles', 'type': 'main', 'index': 0}]]},
    'Select Pending from Cadency Table': {'main': [[{'node': 'Loop Leads', 'type': 'main', 'index': 0}]]},
    'Loop Leads': {'main': [[{'node': 'Build Pipedrive Activity Payload', 'type': 'main', 'index': 0}], [{'node': 'Loop Leads', 'type': 'main', 'index': 0}]]},
    'Build Pipedrive Activity Payload': {'main': [[{'node': 'Call Shared Pipedrive Activity', 'type': 'main', 'index': 0}]]},
    'Call Shared Pipedrive Activity': {'main': [[{'node': 'Mark Cadency Row Processed', 'type': 'main', 'index': 0}]]},
}

unified_pipe_id, unified_pipe_action = upsert_workflow(unified_pipe_name, unified_pipe_nodes, unified_pipe_conn)

# 4) Unified cadency version based on new CRM API
unified_crm_name = 'CadencyUnified - CRM v1'
unified_crm_nodes = [
    {
        'id': 'schedule',
        'name': 'Schedule Trigger',
        'type': 'n8n-nodes-base.scheduleTrigger',
        'typeVersion': 1.2,
        'position': [180, 300],
        'parameters': {
            'rule': {
                'interval': [
                    {'field': 'minutes', 'minutesInterval': 15}
                ]
            }
        },
    },
    {
        'id': 'fetch-leads',
        'name': 'Fetch Leads from CRM',
        'type': 'n8n-nodes-base.httpRequest',
        'typeVersion': 4.2,
        'position': [430, 300],
        'parameters': {
            'method': 'GET',
            'url': '={{($env.CRM_API_BASE_URL || "https://api.smartenvios.tec.br/crm") + "/api/v1/leads?page=1&limit=100"}}',
            'sendHeaders': True,
            'headerParameters': {
                'parameters': [
                    {'name': 'Authorization', 'value': '={{"Bearer " + ($env.CRM_BEARER_TOKEN || "")}}'}
                ]
            },
            'options': {'response': {'response': {'neverError': True}}},
        },
    },
    {
        'id': 'prepare-cadency-activities',
        'name': 'Prepare Cadency Activities',
        'type': 'n8n-nodes-base.code',
        'typeVersion': 2,
        'position': [700, 300],
        'parameters': {
            'jsCode': 'const payload = $json;\nconst leads = (payload.data || payload.result?.data || []);\nconst out = [];\nconst now = new Date();\nconst yyyy = now.getFullYear();\nconst mm = String(now.getMonth()+1).padStart(2,\'0\');\nconst dd = String(now.getDate()).padStart(2,\'0\');\nfor (const lead of leads) {\n  if (!lead?.id) continue;\n  const stage = (lead.stage || lead.status || "").toString().toLowerCase();\n  let title = "Follow-up comercial";\n  if (stage.includes("inbound")) title = "Follow-up Inbound";\n  else if (stage.includes("outbound")) title = "Follow-up Outbound";\n  else if (stage.includes("evento") || stage.includes("event")) title = "Follow-up Evento";\n  out.push({ json: {\n    lead_id: lead.id,\n    person_id: lead.person_id || null,\n    type: "call",\n    scheduled_date: `${yyyy}-${mm}-${dd}`,\n    scheduled_time: "10:00",\n    title,\n    comment: `Cadency CRM v1 - auto activity for lead ${lead.id}`\n  }});\n}\nreturn out.slice(0, 100);'
        },
    },
    {
        'id': 'loop-activities',
        'name': 'Loop Activities',
        'type': 'n8n-nodes-base.splitInBatches',
        'typeVersion': 3,
        'position': [980, 300],
        'parameters': {'batchSize': 1},
    },
    {
        'id': 'call-shared-crm',
        'name': 'Call Shared CRM Activity',
        'type': 'n8n-nodes-base.executeWorkflow',
        'typeVersion': 1.2,
        'position': [1240, 300],
        'parameters': {
            'workflowId': {
                '__rl': True,
                'value': sub_crm_id,
                'mode': 'list',
            },
            'mode': 'each',
            'options': {'waitForSubWorkflow': True}
        },
    },
]

unified_crm_conn = {
    'Schedule Trigger': {'main': [[{'node': 'Fetch Leads from CRM', 'type': 'main', 'index': 0}]]},
    'Fetch Leads from CRM': {'main': [[{'node': 'Prepare Cadency Activities', 'type': 'main', 'index': 0}]]},
    'Prepare Cadency Activities': {'main': [[{'node': 'Loop Activities', 'type': 'main', 'index': 0}]]},
    'Loop Activities': {'main': [[{'node': 'Call Shared CRM Activity', 'type': 'main', 'index': 0}], [{'node': 'Loop Activities', 'type': 'main', 'index': 0}]]},
}

unified_crm_id, unified_crm_action = upsert_workflow(unified_crm_name, unified_crm_nodes, unified_crm_conn)

print(json.dumps({
    'ok': True,
    'base': BASE,
    'workflows': [
        {'name': sub_pipe_name, 'id': sub_pipe_id, 'action': sub_pipe_action},
        {'name': sub_crm_name, 'id': sub_crm_id, 'action': sub_crm_action},
        {'name': unified_pipe_name, 'id': unified_pipe_id, 'action': unified_pipe_action},
        {'name': unified_crm_name, 'id': unified_crm_id, 'action': unified_crm_action},
    ]
}, ensure_ascii=False, indent=2))
