# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is

This is a **configuration workspace** for the OpenClaw Gateway, a proprietary AI agent orchestration runtime. It contains JSON configs, bash/python operational scripts, markdown documentation, and an HTML canvas page. There is **no traditional build step, no package manager dependencies, and no test framework**.

### System dependencies

The scripts require `bash`, `python3`, `curl`, and `jq` (all pre-installed on Ubuntu).

### Validation commands

- **JSON configs**: `python3 -c "import json; json.load(open('openclaw.json'))"`
- **Shell script syntax**: `bash -n <script.sh>` for any `.sh` file
- **Python syntax**: `python3 -m py_compile workspace/scripts/notion_export_recursive.py`
- **Logging policy check**: `bash workspace/scripts/check-logging.sh workspace/`
- **Canvas UI**: Serve with `python3 -m http.server 8080` from `canvas/` directory, then open `http://localhost:8080/`

### Key paths

- `openclaw.json` — Gateway configuration (agents, channels, skills, logging)
- `cron/jobs.json` — Scheduled jobs for all agents
- `workspace/scripts/` — Operational bash/python scripts (Gmail, Notion export, governance, MCP)
- `canvas/index.html` — Interactive test page for OpenClaw node canvas
- `workspace/AGENTS.md` — Agent behavior rules (for the OpenClaw agents, not Cursor)
- `workspace/SETUP_COMPLETO.md` — Full system setup documentation

### Important caveats

- The `openclaw` CLI binary is **not included** in this repo; it's a proprietary external tool. Scripts like `governance-check.sh` and `ops-dashboard.sh` depend on it and will fail without it installed.
- The `.env` file (with API keys for OpenAI, Anthropic, Notion, Discord, Gmail, etc.) is gitignored. Scripts that call external APIs will fail without it.
- All scripts expect the workspace to be at `/var/www/openclaw/workspace` (hardcoded macOS paths use `/private/var/www/openclaw/`). In the Cloud VM, scripts run from the repo root at `/workspace/`.
- The `check-logging.sh` script is the only script that runs fully without external dependencies.
