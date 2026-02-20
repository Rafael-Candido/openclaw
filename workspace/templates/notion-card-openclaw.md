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

```md
🚀 UPGRADE: [Título da entrega] ([AAAA-MM-DD HH:mm GMT-3])

Novo sistema de análise automática:
✅ [Melhoria 1]
✅ [Melhoria 2]
✅ [Melhoria 3]

📊 Capacidades:
- [Capacidade 1]
- [Capacidade 2]

🎯 Ações por score:
- draft (50+): Criar rascunho contextualizado
- review (20-49): Revisar e decidir
- label (0-19): Apenas labelar
- ignore (<0): Auto-reply, arquivar

Documentação: [arquivo(s)]
Commits: [hash1], [hash2]
```
