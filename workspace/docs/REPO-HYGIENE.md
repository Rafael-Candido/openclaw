# Higiene e Organizacao do Repositorio OpenClaw

## Fonte versionada

Conteudo que pode ficar no Git:
- contratos executaveis e espelhos humanos em `workspace/docs/`;
- configuracao runtime sem segredo literal, como `openclaw.json` e `cron/jobs.json`;
- scripts operacionais em `workspace/scripts/`;
- `AGENTS.md`, `TOOLS.md`, templates e documentacao viva;
- agentes oficiais definidos em `workspace/docs/OPENCLAW-OPERATING-CONTRACT.json`.

Regra:
- se o arquivo contem historico de execucao, sessao, cache, token, fila, midia recebida, lock, banco SQLite runtime ou log, ele nao e fonte versionada.

## Runtime local ignorado

Diretorios e arquivos tratados como runtime local:
- `logs/`
- `backups/`
- `agents/*/sessions/`
- `cron/runs/`
- `tasks/`
- `flows/`
- `media/`
- `delivery-queue/`
- `.cache/`, `.pycache/`, `.ruff_cache/`
- `workspace/tmp/`
- `workspace/.state/`
- `workspace/reports/`
- `workspace/agents/*/.pi/`
- `devices/`, `identity/`, `subagents/`

Esses itens podem existir localmente, mas nao devem voltar ao indice do Git.

## Arquivo historico

Documentos e agentes substituidos devem sair da arvore operacional ativa.

Destino padrao:
- `workspace/docs/archive/YYYY-MM-DD/`

Regras:
- preservar apenas resumo util e decisao duravel;
- nao manter amostras brutas com e-mails, tokens, payloads ou logs completos;
- nao manter pastas `workspace/agents/repo-*` como camada oficial de delegacao;
- demandas de repositorios SmartEnvios devem ser roteadas para `Engenheiro SmartEnvios`.

## Politica de retencao

Automacao oficial:
- `workspace/scripts/openclaw-hygiene.sh`

Politica aplicada por `--apply`:
- backup: manter exatamente `backups/daily/openclaw-latest.tar.gz`;
- sessoes: manter no maximo 20 `.jsonl` recentes por agente;
- `cron/runs`: manter no maximo 500 linhas por arquivo;
- logs ativos: capar `gateway.log` em 20 MB e `gateway.err.log` em 10 MB;
- reports/tmp: manter somente artefatos do dia;
- media/fila: apagar itens antigos sem referencia nas sessoes mantidas.

Uso seguro:
```bash
workspace/scripts/openclaw-hygiene.sh --dry-run --json
workspace/scripts/openclaw-hygiene.sh --apply --json
```

## Criterio de aceite

Depois da higiene:
- `openclaw config validate` deve continuar valido;
- runtime deve aparecer apenas como ignored/untracked local, nao como arquivo versionavel;
- `git ls-files` nao deve listar sessoes, logs, SQLite runtime, `.state`, `.pi`, `workspace/reports`, `devices`, `identity`, `subagents`, `flows` ou `tasks`;
- `backups/` deve ficar reduzido ao backup diario atual.
