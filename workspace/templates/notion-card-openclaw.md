# Template Reutilizável — Card OpenClaw

Use este template para evitar repetir propriedades em toda criação manual.

## Propriedades padrão do Presidente/Main

- **Status:** `Aguardando` (diretor promove para `Priorizado`)
- **Tipo:** `OpenClaw`
- **Solicitante:** `Rafael Pereira`
- **Agente:** diretor responsável pela condução

Regra de descrição do Presidente:
- Escrever descrição funcional clara (contexto, objetivo, escopo e critério de sucesso).
- Não detalhar implementação técnica; isso é papel do Diretor.

## Propriedades padrão do Diretor

Ao captar o card, o diretor deve normalizar para:

- **Status:** `Priorizado`
- **Tipo:** `OpenClaw`
- **Solicitante:** `Rafael Pereira`
- **Agente:** especialista responsável pela execução

## Roteamento recomendado (diretor -> especialista)

| Tipo de tarefa | Diretor | Especialista (Agente) |
|---|---|---|
| Código/bugs/features SmartEnvios | `Tech` | `Engenheiro SmartEnvios` |
| MCP (novas ferramentas, endpoints) | `Tech` | `Engenheiro SmartEnvios` |
| Atendimento operacional (central/plataforma/CRM/discord) | `Tech` | `Especialista de Suporte de Software` |
| E-mail profissional | `Tech` | `Mail-Pro` |
| Manutenção OpenClaw (agentes, prompts, docs) | `Diretor Pessoal` | `Engenheiro de Prompt` |
| Enriquecimento base Einstein | `Diretor Pessoal` | `Engenheiro de Prompt` |
| E-mail pessoal | `Diretor Pessoal` | `Mail-Person` |
| Negócios (temporário) | `Diretor Negócios` | `Tech` |

## Corpo padrão (copiar/colar)

```md
## Contexto
[Origem da demanda e objetivo]

## O que fazer (passos)
1. ...
2. ...
3. ...

## Critérios de conclusão
- ...

## Recursos/API
- MCP SmartEnvios: usar API (auth_login + session_token)
- Zendesk: usar MCP (API); painel da base de conhecimento apenas para consulta visual quando necessário

## Regra de execução
- API-first obrigatório
- Não usar fluxo manual se houver endpoint/tool disponível
```

## Comentário padrão do especialista (resumo de execução)

Usar assinatura via `notion-helper.sh comment PAGE_ID API_KEY 'texto' 'ASSINATURA'`.

```md
## Resultado executivo
- Status: Sucesso | Sucesso parcial | Falha
- Caixa analisada: [email/escopo]
- Janela/consulta usada: [comando/query]

## Métricas
- Não lidos encontrados: N
- E-mails lidos com histórico: N
- Triados: N (Importante=X, Aguardando=Y, BaixoValor=Z)
- Labels reaproveitadas: [lista]
- Labels criadas: [lista]
- E-mails marcados como lidos: N
- Arquivados: N
- Rascunhos criados: N

## Evidências
- [messageId/assunto 1]
- [messageId/assunto 2]

## Decisões e próximos passos
- [critérios aplicados]
- [pendências]
```

Padrão completo: `workspace/templates/agent-behavior-patterns.md`.
