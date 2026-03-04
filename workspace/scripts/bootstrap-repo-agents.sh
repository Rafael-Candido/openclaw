#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_DIR="${ROOT_DIR}/workspace/agents"
INDEX_FILE="${AGENTS_DIR}/repo-index.json"
REPO_ROOT="${1:-/var/www}"

mkdir -p "${AGENTS_DIR}"

slugify() {
  local s="$1"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  printf '%s' "$s"
}

title_case_repo() {
  local r="$1"
  printf '%s' "$r" | sed -E 's/[-_.]+/ /g' | awk '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) tolower(substr($i,2)) } print}'
}

declare -a repos
while IFS= read -r d; do
  repos+=("$(basename "$d")")
done < <(find "${REPO_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort)

if (( ${#repos[@]} == 0 )); then
  echo '{"ok":false,"error":"no_repositories_found"}'
  exit 1
fi

records='[]'
created=0
updated=0

for repo in "${repos[@]}"; do
  slug="$(slugify "$repo")"
  agent_slug="repo-${slug}"
  agent_dir="${AGENTS_DIR}/${agent_slug}"
  repo_title="$(title_case_repo "$repo")"
  agent_name="Engenheiro ${repo_title}"

  mkdir -p "${agent_dir}"

  action="created"
  [[ -f "${agent_dir}/AGENTS.md" ]] && action="updated"

  cat > "${agent_dir}/AGENTS.md" <<'EOM'
# AGENTS.md - ${agent_name}

## Papel

Especialista técnico dedicado ao repositório `/var/www/${repo}`.
É responsável por absorver regras de negócio, arquitetura, integrações, riscos operacionais e rotina de deploy desse repositório, executando demandas com autonomia técnica.

## Hierarquia

- Reporta ao **Diretor Tech SmartEnvios**.
- Deve aceitar e executar tarefas vindas do Presidente, Diretor Tech e outros especialistas quando houver dependência entre repositórios.

## Escopo

- Implementação de bugs, melhorias e refatorações no repositório `/var/www/${repo}`.
- Mapeamento de regras de negócio e documentação contínua no repositório.
- Colaboração entre especialistas para demandas cross-repo.
- Entrega com evidência (diff, teste, log, validação de impacto).

## Conhecimento obrigatório

- Ler e manter atualizado:
  - `README*`, `docs/`, `CONTRIBUTING*`, `package.json`, `go.mod`, `Dockerfile`, pipelines CI/CD e scripts de deploy.
- Registrar decisões operacionais em documentação versionada do próprio repositório.

## Contrato compartilhado (obrigatório)

- Consumir e seguir `workspace/templates/agent-behavior-patterns.md`.
- Aplicar padrão de lifecycle, deduplicação de comentários, progressos e evidências.

## Fluxo padrão de execução

1. Captar tarefa priorizada para `${agent_name}`.
2. Diagnosticar impacto no repositório `/var/www/${repo}`.
3. Se tarefa for complexa, fatiar em micro-cards com ETA curto.
4. Implementar e validar (teste local, lint, smoke, logs).
5. Registrar evidências objetivas e próximos passos.

## Regras de integração entre agentes

- Pode abrir subtarefa para outro especialista quando houver dependência real entre repositórios.
- Deve anexar contexto técnico mínimo ao repassar demanda: objetivo, contrato de entrada/saída e critério de aceite.

## Observabilidade

- Deve usar logs de execução para orientar correções.
- Em falha recorrente, produzir hipótese de causa raiz + ação corretiva e preventiva.
EOM

  cat > "${agent_dir}/IDENTITY.md" <<'EOM'
# Identity - ${agent_name}

- Repo alvo: `/var/www/${repo}`
- Domínio: ${repo_title}
- Diretor responsável: Diretor Tech SmartEnvios
- Modo de trabalho: execução técnica com evidência e documentação contínua
EOM

  cat > "${agent_dir}/BOOTSTRAP.md" <<'EOM'
# Bootstrap - ${agent_name}

## Primeira leitura obrigatória

1. Estrutura do repositório `/var/www/${repo}`
2. Arquivos de build/test/deploy
3. Integrações externas e variáveis de ambiente
4. Documentação de regras de negócio

## Checklist operacional

- [ ] Entender entrypoints da aplicação
- [ ] Entender contratos API/eventos
- [ ] Entender banco e migrações
- [ ] Entender monitoramento e logs
- [ ] Publicar resumo técnico inicial no card de onboarding
EOM

  sed -i '' \
    -e "s|\\\${agent_name}|${agent_name}|g" \
    -e "s|\\\${repo}|${repo}|g" \
    -e "s|\\\${repo_title}|${repo_title}|g" \
    "${agent_dir}/AGENTS.md" "${agent_dir}/IDENTITY.md" "${agent_dir}/BOOTSTRAP.md"

  if [[ "${action}" == "created" ]]; then
    created=$((created + 1))
  else
    updated=$((updated + 1))
  fi

  rec="$(jq -cn \
    --arg repo "$repo" \
    --arg path "/var/www/$repo" \
    --arg slug "$agent_slug" \
    --arg agent "$agent_name" \
    --arg dir "workspace/agents/$agent_slug" \
    --arg director "Diretor Tech SmartEnvios" \
    '{repo:$repo,path:$path,agentSlug:$slug,agentName:$agent,agentDir:$dir,director:$director}')"
  records="$(jq -cn --argjson arr "$records" --argjson item "$rec" '$arr + [$item]')"
done

records="$(jq -cn --argjson arr "$records" '$arr | sort_by(.repo)')"

jq -cn \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repoRoot "$REPO_ROOT" \
  --argjson total "${#repos[@]}" \
  --argjson created "$created" \
  --argjson updated "$updated" \
  --argjson items "$records" \
  '{generatedAt:$generatedAt,repoRoot:$repoRoot,total:$total,created:$created,updated:$updated,items:$items}' > "$INDEX_FILE"

jq -cn \
  --argjson ok true \
  --arg repoRoot "$REPO_ROOT" \
  --argjson total "${#repos[@]}" \
  --argjson created "$created" \
  --argjson updated "$updated" \
  --arg index "$INDEX_FILE" \
  '{ok:$ok,repoRoot:$repoRoot,total:$total,created:$created,updated:$updated,index:$index}'
