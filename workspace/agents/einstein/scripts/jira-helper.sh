#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_DIR="${AGENT_DIR}/.pi"
ASSIGNEE_CACHE="${STATE_DIR}/jira-assignees.json"
FIELD_CACHE="${STATE_DIR}/jira-field-cache.json"
# Usar config dir do projeto; fallback para deploy padrão
OPENCLAW_ROOT="${OPENCLAW_CONFIG_DIR:-$(cd "${SCRIPT_DIR}/../../../.." 2>/dev/null && pwd)}"
[[ -z "$OPENCLAW_ROOT" ]] && OPENCLAW_ROOT="/var/www/openclaw"
ENV_FILE="${OPENCLAW_ROOT}/.env"

AUTH_BASIC=""
JIRA_BASE_URL=""
JIRA_PROJECT_KEY_LOCAL=""

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

die() {
  echo "Erro: $*" >&2
  exit 1
}

lower() {
  printf "%s" "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_alias() {
  local value
  value="$(lower "$1")"
  # shellcheck disable=SC2001
  value="$(echo "$value" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  printf "%s" "$value"
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

is_file_stale() {
  local file="$1"
  local max_age_seconds="$2"
  local now mtime

  [[ -f "$file" ]] || return 0

  now="$(date +%s)"
  mtime="$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0)"
  (( now - mtime > max_age_seconds ))
}

init_state() {
  mkdir -p "$STATE_DIR"

  if [[ ! -f "$ASSIGNEE_CACHE" ]]; then
    cat > "$ASSIGNEE_CACHE" <<'JSON'
{
  "updatedAt": null,
  "aliases": {},
  "usersByAccountId": {}
}
JSON
  fi

  if [[ ! -f "$FIELD_CACHE" ]]; then
    cat > "$FIELD_CACHE" <<'JSON'
{
  "updatedAt": null,
  "fieldIds": {
    "product": "",
    "integration": "",
    "category": "",
    "projectLabel": ""
  }
}
JSON
  fi
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "Arquivo .env nao encontrado em $ENV_FILE"

  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a

  : "${JIRA_BASE_URL:?JIRA_BASE_URL ausente no .env}"
  : "${JIRA_EMAIL:?JIRA_EMAIL ausente no .env}"
  : "${JIRA_API_TOKEN:?JIRA_API_TOKEN ausente no .env}"
  : "${JIRA_PROJECT_KEY:?JIRA_PROJECT_KEY ausente no .env}"

  JIRA_BASE_URL="${JIRA_BASE_URL%/}/"
  JIRA_PROJECT_KEY_LOCAL="${JIRA_PROJECT_KEY}"
  AUTH_BASIC="$(printf "%s:%s" "${JIRA_EMAIL}" "${JIRA_API_TOKEN}" | base64 | tr -d '\n')"
}

jira_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local url http_code tmp_body

  url="${JIRA_BASE_URL}${path}"
  tmp_body="$(mktemp)"

  if [[ -n "$body" ]]; then
    http_code="$(
      curl -sS -o "$tmp_body" -w "%{http_code}" -X "$method" "$url" \
        -H "Authorization: Basic ${AUTH_BASIC}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        --data "$body"
    )"
  else
    http_code="$(
      curl -sS -o "$tmp_body" -w "%{http_code}" -X "$method" "$url" \
        -H "Authorization: Basic ${AUTH_BASIC}" \
        -H "Accept: application/json"
    )"
  fi

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "Jira API error ${http_code} em ${method} ${path}" >&2
    cat "$tmp_body" >&2
    rm -f "$tmp_body"
    return 1
  fi

  cat "$tmp_body"
  rm -f "$tmp_body"
}

jira_get() {
  jira_request "GET" "$1"
}

jira_post() {
  jira_request "POST" "$1" "$2"
}

cache_user_object() {
  local user_json="$1"
  local query_alias="${2:-}"
  local account_id display_name email normalized_display normalized_first normalized_query tmp_file

  account_id="$(jq -r '.accountId // empty' <<<"$user_json")"
  [[ -n "$account_id" ]] || return 0

  display_name="$(jq -r '.displayName // empty' <<<"$user_json")"
  email="$(jq -r '.emailAddress // empty' <<<"$user_json")"
  normalized_display="$(normalize_alias "$display_name")"
  normalized_first="$(normalize_alias "${display_name%% *}")"
  normalized_query="$(normalize_alias "$query_alias")"

  tmp_file="$(mktemp)"
  jq \
    --arg accountId "$account_id" \
    --arg displayName "$display_name" \
    --arg email "$email" \
    --arg now "$(now_iso)" \
    --arg normalizedDisplay "$normalized_display" \
    --arg normalizedFirst "$normalized_first" \
    --arg normalizedQuery "$normalized_query" \
    '
      .updatedAt = $now
      | .usersByAccountId[$accountId] = {
          accountId: $accountId,
          displayName: $displayName,
          emailAddress: $email,
          lastSeenAt: $now
        }
      | if $normalizedDisplay != "" then .aliases[$normalizedDisplay] = $accountId else . end
      | if $normalizedFirst != "" then .aliases[$normalizedFirst] = $accountId else . end
      | if $normalizedQuery != "" then .aliases[$normalizedQuery] = $accountId else . end
      | if $email != "" then .aliases[($email | ascii_downcase)] = $accountId else . end
      | if $email != "" then .aliases[(($email | split("@")[0]) | ascii_downcase)] = $accountId else . end
    ' "$ASSIGNEE_CACHE" > "$tmp_file"

  mv "$tmp_file" "$ASSIGNEE_CACHE"
}

resolve_assignee() {
  local query="$1"
  local normalized_query account_id cached_user uri search_results selected

  normalized_query="$(normalize_alias "$query")"
  account_id="$(jq -r --arg alias "$normalized_query" '.aliases[$alias] // empty' "$ASSIGNEE_CACHE")"

  if [[ -n "$account_id" ]]; then
    cached_user="$(jq -c --arg id "$account_id" '.usersByAccountId[$id] // {}' "$ASSIGNEE_CACHE")"
    if [[ "$cached_user" != "{}" ]]; then
      jq -c '. + {source: "cache"}' <<<"$cached_user"
      return 0
    fi
  fi

  uri="$(urlencode "$query")"
  search_results="$(jira_get "rest/api/3/user/search?query=${uri}&maxResults=50")"

  while IFS= read -r user_line; do
    cache_user_object "$user_line" "$query"
  done < <(jq -c '.[]' <<<"$search_results")

  selected="$(jq -c --arg q "$normalized_query" '
    def norm: ascii_downcase;
    if (type != "array" or length == 0) then
      null
    else
      (
        map(select(
          ((.displayName // "" | norm) == $q)
          or ((.emailAddress // "" | norm) == $q)
          or ((((.emailAddress // "") | split("@")[0]) | norm) == $q)
        ))[0]
        // map(select(
          ((.displayName // "" | norm) | contains($q))
          or ((.emailAddress // "" | norm) | contains($q))
        ))[0]
        // .[0]
      )
    end
  ' <<<"$search_results")"

  [[ "$selected" != "null" && -n "$selected" ]] || return 1

  cache_user_object "$selected" "$query"
  jq -c '. + {source: "api"}' <<<"$selected"
}

resolve_assignee_from_cache_only() {
  local query="$1"
  local normalized_query account_id cached_user

  normalized_query="$(normalize_alias "$query")"
  account_id="$(jq -r --arg alias "$normalized_query" '.aliases[$alias] // empty' "$ASSIGNEE_CACHE")"
  [[ -n "$account_id" ]] || return 1

  cached_user="$(jq -c --arg id "$account_id" '.usersByAccountId[$id] // {}' "$ASSIGNEE_CACHE")"
  [[ "$cached_user" != "{}" ]] || return 1

  jq -c '. + {source: "cache"}' <<<"$cached_user"
}

sync_field_ids() {
  local fields_json product_id integration_id category_id project_label_id tmp_file

  fields_json="$(jira_get "rest/api/3/field")"

  product_id="$(jq -r '
    map(select(.custom == true and ((.name // "" | ascii_downcase) | test("produto|product"))))
    | .[0].id // ""
  ' <<<"$fields_json")"

  integration_id="$(jq -r '
    map(select(.custom == true and ((.name // "" | ascii_downcase) | test("integra|integration|transportadora|carrier"))))
    | .[0].id // ""
  ' <<<"$fields_json")"

  category_id="$(jq -r '
    map(select(.custom == true and ((.name // "" | ascii_downcase) | test("categoria|category"))))
    | .[0].id // ""
  ' <<<"$fields_json")"

  project_label_id="$(jq -r '
    map(select(.custom == true and ((.name // "" | ascii_downcase) | test("projeto|project"))))
    | .[0].id // ""
  ' <<<"$fields_json")"

  tmp_file="$(mktemp)"
  jq -n \
    --arg updatedAt "$(now_iso)" \
    --arg product "$product_id" \
    --arg integration "$integration_id" \
    --arg category "$category_id" \
    --arg projectLabel "$project_label_id" \
    '{
      updatedAt: $updatedAt,
      fieldIds: {
        product: $product,
        integration: $integration,
        category: $category,
        projectLabel: $projectLabel
      }
    }' > "$tmp_file"

  mv "$tmp_file" "$FIELD_CACHE"
}

maybe_sync_field_ids() {
  if is_file_stale "$FIELD_CACHE" 86400; then
    sync_field_ids
  fi
}

infer_issue_type() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ bug|erro|falha|defeito|nao\ atualiza|nao\ funciona|incidente|quebra|trava ]]; then
    echo "Bug"
    return
  fi

  if [[ "$text" =~ melhoria|melhorar|aprimorar|evolu|feature|otimiz ]]; then
    echo "Story"
    return
  fi

  echo "Task"
}

infer_integration() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ dhl ]]; then echo "DHL"; return; fi
  if [[ "$text" =~ correios ]]; then echo "Correios"; return; fi
  if [[ "$text" =~ jadlog ]]; then echo "Jadlog"; return; fi
  if [[ "$text" =~ loggi ]]; then echo "Loggi"; return; fi
  if [[ "$text" =~ azul ]]; then echo "Azul Cargo"; return; fi
  if [[ "$text" =~ melhor\ envio ]]; then echo "Melhor Envio"; return; fi
  echo ""
}

infer_category() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ tracking|rastreio|rastreamento ]]; then echo "Tracking"; return; fi
  if [[ "$text" =~ etiqueta|label ]]; then echo "Etiqueta"; return; fi
  if [[ "$text" =~ cotacao|cotacao|frete|quote ]]; then echo "Cotacao"; return; fi
  if [[ "$text" =~ integracao|integration|webhook ]]; then echo "Integracao"; return; fi
  if [[ "$text" =~ financeiro|fatura|cobranca ]]; then echo "Financeiro"; return; fi
  if [[ "$text" =~ login|acesso|senha ]]; then echo "Acesso"; return; fi
  echo "Operacao"
}

infer_product() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ app|aplicativo ]]; then echo "APP"; return; fi
  if [[ "$text" =~ tracking|rastreio|rastreamento ]]; then echo "APP"; return; fi
  if [[ "$text" =~ api ]]; then echo "API"; return; fi
  if [[ "$text" =~ portal ]]; then echo "Portal"; return; fi
  if [[ "$text" =~ dashboard|painel ]]; then echo "Dashboard"; return; fi
  echo "APP"
}

infer_project_label() {
  local text
  text="$(normalize_alias "$1")"

  if [[ "$text" =~ smartenvios|sme ]]; then
    echo "SME project"
    return
  fi
  echo "SME project"
}

candidate_values_for_kind() {
  local kind="$1"
  local value="$2"

  local normalized
  normalized="$(normalize_alias "$value")"

  if [[ -n "$value" ]]; then
    echo "$value"
  fi

  case "$kind" in
    category)
      if [[ "$normalized" == "tracking" || "$normalized" == "rastreamento" || "$normalized" == "rastreio" ]]; then
        echo "Tracking"
        echo "Rastreamento"
        echo "Rastreio"
      fi
      if [[ "$normalized" == "integracao" || "$normalized" == "integration" ]]; then
        echo "Integracao"
        echo "Integração"
        echo "Integration"
      fi
      if [[ "$normalized" == "operacao" ]]; then
        echo "Operacao"
        echo "Operação"
      fi
      ;;
    product)
      if [[ "$normalized" == "app" || "$normalized" == "aplicativo" ]]; then
        echo "APP"
        echo "Aplicativo"
      fi
      if [[ "$normalized" == "portal" ]]; then
        echo "Portal"
      fi
      if [[ "$normalized" == "api" ]]; then
        echo "API"
      fi
      ;;
    projectLabel)
      if [[ "$normalized" == "sme project" || "$normalized" == "sme" || "$normalized" == "smartenvios" ]]; then
        echo "SME project"
        echo "SME"
        echo "SmartEnvios"
      fi
      ;;
  esac
}

pick_allowed_value() {
  local kind="$1"
  local desired="$2"
  local allowed_json="$3"
  local required="$4"
  local chosen=""
  local candidate allowed candidate_l allowed_l

  mapfile -t allowed_values < <(jq -r '.[] | .value // .name // empty' <<<"$allowed_json")

  if [[ "${#allowed_values[@]}" -eq 0 ]]; then
    echo "$desired"
    return
  fi

  mapfile -t candidates < <(candidate_values_for_kind "$kind" "$desired" | awk 'NF' | awk '!seen[$0]++')

  for candidate in "${candidates[@]}"; do
    candidate_l="$(normalize_alias "$candidate")"
    [[ -n "$candidate_l" ]] || continue
    for allowed in "${allowed_values[@]}"; do
      allowed_l="$(normalize_alias "$allowed")"
      if [[ "$allowed_l" == "$candidate_l" || "$allowed_l" == *"$candidate_l"* || "$candidate_l" == *"$allowed_l"* ]]; then
        chosen="$allowed"
        break 2
      fi
    done
  done

  if [[ -z "$chosen" && "$required" == "true" ]]; then
    chosen="${allowed_values[0]}"
  fi

  echo "$chosen"
}

field_spec_from_meta() {
  local createmeta_json="$1"
  local issue_type="$2"
  local field_id="$3"

  jq -c \
    --arg issueType "$issue_type" \
    --arg fieldId "$field_id" \
    '
      (.projects[0].issuetypes // []) as $issueTypes
      | ($issueTypes | map(select((.name // "" | ascii_downcase) == ($issueType | ascii_downcase)))[0] // $issueTypes[0]) as $selected
      | if ($selected == null) then
          {required: false, allowed: []}
        else
          {
            required: ($selected.fields[$fieldId].required // false),
            allowed: ($selected.fields[$fieldId].allowedValues // [])
          }
        end
    ' <<<"$createmeta_json"
}

ensure_todo_status() {
  local issue_key="$1"
  local transitions_json target_transition_id

  transitions_json="$(jira_get "rest/api/3/issue/${issue_key}/transitions")"
  target_transition_id="$(jq -r '
    [
      .transitions[]
      | select(
          ((.to.name // "" | ascii_downcase) == "to do")
          or ((.to.name // "" | ascii_downcase) == "tarefas pendentes")
          or ((.to.name // "" | ascii_downcase) == "pendente")
          or ((.to.name // "" | ascii_downcase) == "pending")
          or ((.to.name // "" | ascii_downcase) == "backlog")
        )
    ][0].id // empty
  ' <<<"$transitions_json")"

  if [[ -n "$target_transition_id" ]]; then
    jira_post "rest/api/3/issue/${issue_key}/transitions" \
      "$(jq -n --arg id "$target_transition_id" '{transition: {id: $id}}')" >/dev/null
    echo "true"
    return
  fi

  echo "false"
}

cmd_assignee_resolve() {
  local query="${1:-}"
  [[ -n "$query" ]] || die "Uso: $0 assignee-resolve \"Nome\""

  load_env
  init_state

  resolve_assignee "$query" \
    || die "Nao foi possivel resolver assignee para \"$query\""
}

cmd_assignee_list() {
  init_state
  jq -c '.usersByAccountId' "$ASSIGNEE_CACHE"
}

cmd_sync_fields() {
  load_env
  init_state
  sync_field_ids
  jq -c '.' "$FIELD_CACHE"
}

cmd_create() {
  local summary=""
  local description=""
  local assignee_name=""
  local reason=""
  local product=""
  local integration=""
  local category=""
  local project_label=""
  local priority="Highest"
  local project_key=""
  local dry_run="false"
  local force_sync_fields="false"
  local issue_type=""
  local assignee_json="{}"
  local assignee_account_id=""
  local assignee_display_name=""
  local context_text=""
  local createmeta_json="{}"
  local custom_fields_json="{}"
  local issue_response issue_key issue_id issue_url status_name transitioned_to_todo
  local product_field integration_field category_field project_label_field
  local product_spec integration_spec category_spec project_label_spec
  local product_required integration_required category_required project_label_required
  local product_allowed integration_allowed category_allowed project_label_allowed
  local selected_product selected_integration selected_category selected_project_label
  local description_text description_doc payload
  local links=()

  load_env
  init_state

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --summary)
        summary="${2:-}"
        shift 2
        ;;
      --description)
        description="${2:-}"
        shift 2
        ;;
      --assignee)
        assignee_name="${2:-}"
        shift 2
        ;;
      --reason)
        reason="${2:-}"
        shift 2
        ;;
      --product)
        product="${2:-}"
        shift 2
        ;;
      --integration)
        integration="${2:-}"
        shift 2
        ;;
      --category|--categoria)
        category="${2:-}"
        shift 2
        ;;
      --project-label)
        project_label="${2:-}"
        shift 2
        ;;
      --priority)
        priority="${2:-}"
        shift 2
        ;;
      --project-key)
        project_key="${2:-}"
        shift 2
        ;;
      --link)
        links+=("${2:-}")
        shift 2
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      --sync-fields)
        force_sync_fields="true"
        shift
        ;;
      *)
        die "Argumento desconhecido: $1"
        ;;
    esac
  done

  [[ -n "$summary" ]] || die "Parametro obrigatorio ausente: --summary"

  if [[ -z "$project_key" ]]; then
    project_key="$JIRA_PROJECT_KEY_LOCAL"
  fi

  context_text="$summary"$'\n'"$description"$'\n'"$reason"$'\n'"${links[*]}"

  if [[ -z "$reason" ]]; then
    reason="tarefa"
  fi

  issue_type="$(infer_issue_type "$reason $context_text")"
  [[ -n "$product" ]] || product="$(infer_product "$context_text")"
  [[ -n "$integration" ]] || integration="$(infer_integration "$context_text")"
  [[ -n "$category" ]] || category="$(infer_category "$context_text")"
  [[ -n "$project_label" ]] || project_label="$(infer_project_label "$context_text")"

  if [[ -n "$assignee_name" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      assignee_json="$(resolve_assignee_from_cache_only "$assignee_name" || true)"
    else
      assignee_json="$(resolve_assignee "$assignee_name" || true)"
    fi

    if [[ -n "$assignee_json" && "$assignee_json" != "{}" ]]; then
      assignee_account_id="$(jq -r '.accountId // empty' <<<"$assignee_json")"
      assignee_display_name="$(jq -r '.displayName // empty' <<<"$assignee_json")"
    fi
  fi

  if [[ "$dry_run" != "true" ]]; then
    if [[ "$force_sync_fields" == "true" ]]; then
      sync_field_ids
    else
      maybe_sync_field_ids
    fi
  fi

  product_field="$(jq -r '.fieldIds.product // empty' "$FIELD_CACHE")"
  integration_field="$(jq -r '.fieldIds.integration // empty' "$FIELD_CACHE")"
  category_field="$(jq -r '.fieldIds.category // empty' "$FIELD_CACHE")"
  project_label_field="$(jq -r '.fieldIds.projectLabel // empty' "$FIELD_CACHE")"

  if [[ "$dry_run" != "true" ]]; then
    createmeta_json="$(jira_get "rest/api/3/issue/createmeta?projectKeys=$(urlencode "$project_key")&expand=projects.issuetypes.fields" || echo '{}')"
  fi

  if [[ -n "$product_field" ]]; then
    product_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$product_field")"
    product_required="$(jq -r '.required // false' <<<"$product_spec")"
    product_allowed="$(jq -c '.allowed // []' <<<"$product_spec")"
    selected_product="$(pick_allowed_value "product" "$product" "$product_allowed" "$product_required")"
    if [[ -n "$selected_product" ]]; then
      custom_fields_json="$(jq --arg field "$product_field" --arg value "$selected_product" '. + {($field): {value: $value}}' <<<"$custom_fields_json")"
      product="$selected_product"
    fi
  fi

  if [[ -n "$integration_field" ]]; then
    integration_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$integration_field")"
    integration_required="$(jq -r '.required // false' <<<"$integration_spec")"
    integration_allowed="$(jq -c '.allowed // []' <<<"$integration_spec")"
    selected_integration="$(pick_allowed_value "integration" "$integration" "$integration_allowed" "$integration_required")"
    if [[ -n "$selected_integration" ]]; then
      custom_fields_json="$(jq --arg field "$integration_field" --arg value "$selected_integration" '. + {($field): {value: $value}}' <<<"$custom_fields_json")"
      integration="$selected_integration"
    fi
  fi

  if [[ -n "$category_field" ]]; then
    category_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$category_field")"
    category_required="$(jq -r '.required // false' <<<"$category_spec")"
    category_allowed="$(jq -c '.allowed // []' <<<"$category_spec")"
    selected_category="$(pick_allowed_value "category" "$category" "$category_allowed" "$category_required")"
    if [[ -n "$selected_category" ]]; then
      custom_fields_json="$(jq --arg field "$category_field" --arg value "$selected_category" '. + {($field): {value: $value}}' <<<"$custom_fields_json")"
      category="$selected_category"
    fi
  fi

  if [[ -n "$project_label_field" ]]; then
    project_label_spec="$(field_spec_from_meta "$createmeta_json" "$issue_type" "$project_label_field")"
    project_label_required="$(jq -r '.required // false' <<<"$project_label_spec")"
    project_label_allowed="$(jq -c '.allowed // []' <<<"$project_label_spec")"
    selected_project_label="$(pick_allowed_value "projectLabel" "$project_label" "$project_label_allowed" "$project_label_required")"
    if [[ -n "$selected_project_label" ]]; then
      custom_fields_json="$(jq --arg field "$project_label_field" --arg value "$selected_project_label" '. + {($field): {value: $value}}' <<<"$custom_fields_json")"
      project_label="$selected_project_label"
    fi
  fi

  description_text=""
  if [[ -n "$description" ]]; then
    description_text+="$description"$'\n\n'
  fi

  if [[ "${#links[@]}" -gt 0 ]]; then
    description_text+="Links relevantes:"$'\n'
    for link in "${links[@]}"; do
      [[ -n "$link" ]] || continue
      description_text+="- $link"$'\n'
    done
    description_text+=$'\n'
  fi

  description_text+="Classificacao aplicada automaticamente:"$'\n'
  description_text+="- Motivo: ${reason}"$'\n'
  description_text+="- Tipo Jira: ${issue_type}"$'\n'
  description_text+="- Produto: ${product}"$'\n'
  description_text+="- Projeto: ${project_label}"$'\n'
  description_text+="- Integracao: ${integration:-N/A}"$'\n'
  description_text+="- Categoria: ${category}"$'\n'
  description_text+="- Prioridade: ${priority}"$'\n'
  if [[ -n "$assignee_display_name" ]]; then
    description_text+="- Assignee: ${assignee_display_name}"$'\n'
  elif [[ -n "$assignee_name" ]]; then
    description_text+="- Assignee solicitado: ${assignee_name}"$'\n'
  fi

  description_doc="$(jq -n --arg txt "$description_text" '
    {
      type: "doc",
      version: 1,
      content: (
        $txt
        | split("\n")
        | map(select(length > 0) | {type: "paragraph", content: [{type: "text", text: .}]})
      )
    }
  ')"

  payload="$(jq -n \
    --arg projectKey "$project_key" \
    --arg summary "$summary" \
    --arg issueType "$issue_type" \
    --arg priority "$priority" \
    --arg accountId "$assignee_account_id" \
    --argjson desc "$description_doc" \
    '{
      fields: {
        project: {key: $projectKey},
        summary: $summary,
        issuetype: {name: $issueType},
        priority: {name: $priority},
        description: $desc
      }
    }
    | if $accountId != "" then .fields.assignee = {accountId: $accountId} else . end
  ')"

  payload="$(jq --argjson custom "$custom_fields_json" '.fields += $custom' <<<"$payload")"

  if [[ "$dry_run" == "true" ]]; then
    jq -n \
      --arg summary "$summary" \
      --arg projectKey "$project_key" \
      --arg issueType "$issue_type" \
      --arg priority "$priority" \
      --arg assignee "$assignee_display_name" \
      --arg accountId "$assignee_account_id" \
      --arg product "$product" \
      --arg projectLabel "$project_label" \
      --arg integration "${integration:-}" \
      --arg category "$category" \
      --argjson payload "$payload" \
      '{
        dryRun: true,
        classification: {
          summary: $summary,
          projectKey: $projectKey,
          issueType: $issueType,
          priority: $priority,
          assignee: $assignee,
          accountId: $accountId,
          product: $product,
          projectLabel: $projectLabel,
          integration: $integration,
          category: $category
        },
        payload: $payload
      }'
    return 0
  fi

  issue_response="$(jira_post "rest/api/3/issue" "$payload")"
  issue_key="$(jq -r '.key // empty' <<<"$issue_response")"
  issue_id="$(jq -r '.id // empty' <<<"$issue_response")"

  [[ -n "$issue_key" ]] || die "Falha ao criar issue no Jira: resposta sem key"

  transitioned_to_todo="$(ensure_todo_status "$issue_key")"
  status_name="$(jira_get "rest/api/3/issue/${issue_key}?fields=status" | jq -r '.fields.status.name // empty')"
  issue_url="${JIRA_BASE_URL}browse/${issue_key}"

  jq -n \
    --arg issueKey "$issue_key" \
    --arg issueId "$issue_id" \
    --arg issueUrl "$issue_url" \
    --arg status "$status_name" \
    --arg transitioned "$transitioned_to_todo" \
    --arg projectKey "$project_key" \
    --arg issueType "$issue_type" \
    --arg priority "$priority" \
    --arg assigneeName "$assignee_display_name" \
    --arg assigneeAccountId "$assignee_account_id" \
    --arg product "$product" \
    --arg projectLabel "$project_label" \
    --arg integration "${integration:-}" \
    --arg category "$category" \
    '{
      ok: true,
      issue: {
        key: $issueKey,
        id: $issueId,
        url: $issueUrl,
        status: $status
      },
      classification: {
        projectKey: $projectKey,
        issueType: $issueType,
        priority: $priority,
        assigneeName: $assigneeName,
        assigneeAccountId: $assigneeAccountId,
        product: $product,
        projectLabel: $projectLabel,
        integration: $integration,
        category: $category
      },
      transitionedToPending: ($transitioned == "true")
    }'
}

print_help() {
  cat <<'EOF'
Uso:
  jira-helper.sh assignee-resolve "Nome"
  jira-helper.sh assignee-list
  jira-helper.sh sync-fields
  jira-helper.sh create --summary "..." [opcoes]

Comando create:
  --summary "Titulo da tarefa"                (obrigatorio)
  --description "Descricao detalhada"
  --assignee "Nome da pessoa"
  --reason "bug|melhoria|tarefa|..."
  --product "APP|Portal|API|..."
  --project-label "SME project|..."
  --integration "DHL|Correios|..."
  --category "Tracking|Operacao|..."
  --priority "Highest|High|..."
  --project-key "SME"
  --link "https://..."
  --sync-fields                                (forca refresh do cache de campos)
  --dry-run                                    (gera payload sem criar issue)
EOF
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    assignee-resolve)
      cmd_assignee_resolve "$@"
      ;;
    assignee-list)
      cmd_assignee_list
      ;;
    sync-fields)
      cmd_sync_fields
      ;;
    create)
      cmd_create "$@"
      ;;
    help|-h|--help)
      print_help
      ;;
    *)
      print_help
      die "Comando invalido: $cmd"
      ;;
  esac
}

main "$@"
