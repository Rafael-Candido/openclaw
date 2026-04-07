# HEARTBEAT.md — Main/Presidente

## Saída obrigatória (CRÍTICO)
- Conversa em português -> resposta em **pt-BR**.
- Saída permitida:
  1. `HEARTBEAT_OK`
  2. Bloco `ALERTA` com **máximo 5 linhas**:
     - `ALERTA`
     - `- Problema: ...`
     - `- Impacto: ...`
     - `- Ação executada: ...`
     - `- Próximo passo: ... (ETA: ...min)`
- Qualquer texto fora desse contrato é erro.
- **Proibido inglês**.
- **Proibido raciocínio interno** (ex.: "I need to", "cannot proceed", "vou aguardar").
- **Proibido repetição** do mesmo alerta sem ação nova.
- **Proibido checklist narrativo** (ex.: "1. Learnings extraction...", "2. Status checks...").
- **Proibido explicar o processo de checagem**; retornar somente saída final do contrato.

## Checklist mínima por rodada (~30min)
1. Verificar crons via `ocw_cron_list_json 12`.
2. Verificar Discord do Einstein via `./scripts/discord-gateway-health.sh` (se `issue=true`, não pode responder `HEARTBEAT_OK`).
3. Se `ocw_cron_list_json` falhar, usar fallback com timeout curto.
4. Se tudo estável e sem mudança relevante -> `HEARTBEAT_OK`.
5. Só enviar `ALERTA` quando houver mudança real de estado.
