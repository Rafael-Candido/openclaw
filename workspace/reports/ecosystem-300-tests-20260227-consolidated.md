# Ecosystem 300 Tests - Consolidado (2026-02-27)

## Escopo
- Testes históricos: 286 checks (últimas execuções `finished` em 12 crons)
- Testes ao vivo: 14 checks (crons críticos)
- Total: **300 checks**

## Resultado Geral
- OK: 275
- Falha: 25
- Taxa de sucesso: **91.67%**

## Achados principais
1. Gargalo dominante: instabilidade de gateway sob carga (`1006`, `1012`, timeout).
2. Ruído crítico: rajada de `token_mismatch` de cliente local (`OpenClaw/9039 ui/node`) contra gateway.
3. Cauda longa de execução em crons operacionais:
- `Governança` (picos altos)
- `Mail-Person`
- `Presidente`
- `Eng. SmartEnvios`
- `Main relatório WhatsApp`
4. Alto índice de `already-running` em testes ao vivo, indicando sobreposição de agenda/ciclo.

## Evidência (testes ao vivo)
- 12/14 retornaram `already-running` (não falha lógica, mas saturação/overlap)
- 2/14 falharam por `gateway timeout after 12000ms`

## Causa-raiz técnica
- LaunchAgent do gateway em estado não confiável (PATH/Node via nvm + service drift)
- Cliente desktop local tentando handshake com token diferente em loop
- Excesso de concorrência entre rodadas manuais + agendadas

## Correções aplicadas nesta rodada
1. Limpeza de processos pendurados de observabilidade (`tail -f` órfão).
2. Bateria automatizada de 300 checks com relatório persistido.
3. Mitigação imediata: subir gateway em modo direto (`openclaw gateway run`) para recuperação operacional.
4. Captura de baseline de gargalos via `analyze-cron-logs.sh` e consolidação de evidências.

## Correção definitiva pendente (prioridade P0)
1. Padronizar gateway em **um único modo de execução** (serviço ou direto, não híbrido).
2. Remover origem do `token_mismatch` (cliente desktop local com token antigo).
3. Reinstalar serviço do gateway com Node estável e PATH limpo.
4. Validar com smoke de 20 rodadas após fix: sucesso >= 97% e p95 < 45s nos crons críticos.
