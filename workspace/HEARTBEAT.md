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

## Checklist mínima por rodada (~30min)
1. Verificar crons via `ocw_cron_list_json 12`.
2. Se falhar, fallback com timeout curto.
3. Se tudo estável e sem mudança relevante -> `HEARTBEAT_OK`.
4. Só enviar `ALERTA` quando houver mudança real de estado.
