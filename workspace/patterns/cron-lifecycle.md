# Contrato Central de Lifecycle para Crons OpenClaw

**Versão:** 1.0.0  
**Data:** 2026-02-21  
**Status:** Ativo  
**Aplicável a:** Todos os crons OpenClaw

## 📋 Visão Geral

Este contrato define o padrão centralizado para lifecycle de crons no ecossistema OpenClaw. Todos os crons devem referenciar este documento em vez de replicar regras localmente.

## 🔄 Lifecycle Padrão (FLUXO)

### 1. Busca de Cards (QUERY)
```bash
# Padrão: usar notion-helper.sh com parâmetros apropriados
/var/www/openclaw/workspace/scripts/notion-helper.sh query <DATABASE_ID> <API_KEY_VAR> '<AGENTE>'
```

**Parâmetros obrigatórios:**
- `DATABASE_ID`: ID do banco de dados Notion
- `API_KEY_VAR`: Variável de ambiente da API key
- `AGENTE`: Nome do agente (ex: "Engenheiro de Prompt")

### 2. Transição de Status (UPDATE-STATUS)
```bash
# Priorizado → Em andamento
/var/www/openclaw/workspace/scripts/notion-helper.sh update-status <PAGE_ID> <API_KEY_VAR> 'Em andamento'

# Em andamento → Concluído
/var/www/openclaw/workspace/scripts/notion-helper.sh update-status <PAGE_ID> <API_KEY_VAR> 'Concluído'
```

### 3. Comentários (COMMENT)
```bash
# Template padrão: texto + assinatura
/var/www/openclaw/workspace/scripts/notion-helper.sh comment <PAGE_ID> <API_KEY_VAR> '<TEXTO>' '<ASSINATURA>'
```

**Regras de comentários:**
- **Assinatura obrigatória:** Sempre incluir nome do agente entre parênteses
- **Progresso:** Usar formato "Etapa X/N: descrição"
- **Concisão:** Máximo 300 caracteres por comentário
- **Finalização:** Último comentário deve resumir resultado

### 4. Leitura de Descrição (GET-BLOCKS)
```bash
# Ler descrição do card para execução
/var/www/openclaw/workspace/scripts/notion-helper.sh get-blocks <PAGE_ID> <API_KEY_VAR>
```

## 🎯 Regras de Implementação

### A. Execução de Tarefas
- **Implementador direto:** O cron é o implementador, não "deixa para o Rafael executar"
- **Edição de arquivos:** Se tem permissão de escrita, edita e commita
- **Patch/diff:** Se não tem permissão, fornece conteúdo exato para aplicação
- **Proibido:** Sugestão sem edição = falha

### B. Progresso e Comunicação
- **Etapas progressivas:** Comentários com "Etapa X/N"
- **Assinatura:** Sempre incluir "(<Nome do Agente>)"
- **Finalização:** Mover para Concluído + comentário final
- **Erros:** Ler mensagem e ajustar, não usar subagente

### C. Restrições de Ferramentas
- **Notion exclusivo:** Usar apenas `notion-helper.sh`
- **Proibido:** `curl` direto, `openclaw notion query`
- **Proibido:** `message.send`, subagente
- **Permitido:** `exec` para scripts auxiliares

## 📁 Estrutura de Prompts Modulares

### Módulo 1: Configuração Inicial
```
USE EXCLUSIVAMENTE o script /var/www/openclaw/workspace/scripts/notion-helper.sh para TODAS as operações Notion.
NÃO tente curl direto nem 'openclaw notion query'.

DB: <DATABASE_ID>
API KEY VAR: <API_KEY_VAR>
```

### Módulo 2: Comandos Disponíveis
```
COMANDOS DISPONÍVEIS (via exec):
- Buscar cards: /var/www/openclaw/workspace/scripts/notion-helper.sh query <DB> <API_KEY_VAR> '<AGENTE>'
- Mover status: /var/www/openclaw/workspace/scripts/notion-helper.sh update-status <PAGE_ID> <API_KEY_VAR> 'Em andamento'
- Comentar: /var/www/openclaw/workspace/scripts/notion-helper.sh comment <PAGE_ID> <API_KEY_VAR> 'Texto' '<ASSINATURA>'
- Ler página: /var/www/openclaw/workspace/scripts/notion-helper.sh get-page <PAGE_ID> <API_KEY_VAR>
- Ler blocos: /var/www/openclaw/workspace/scripts/notion-helper.sh get-blocks <PAGE_ID> <API_KEY_VAR>
```

### Módulo 3: Fluxo Padrão
```
FLUXO:
1. Executar query para buscar cards Priorizado/Em andamento
2. Priorizar retomada: processar primeiro cards já em `Em andamento` (mais antigo sem atividade do agente), depois captar `Priorizado`
3. Para cada card captado de Priorizado: update-status para 'Em andamento' + comment de início (<=300 chars)
4. get-blocks para ler descrição, IMPLEMENTAR o pedido (você é o implementador; não existe "deixar para o Rafael executar").
   Fazer as edições em arquivos, cron/jobs.json, scripts.
   Se tiver permissão de escrita no repo: editar e commitar.
   Se não: comentário final com patch/diff ou conteúdo exato dos arquivos para aplicação sem decisão humana.
   Comentário só com sugestão sem edição = falha.
5. Comments progressivos com passo a passo: Etapa X/N (ex: Etapa 1/4, 2/4...), sempre assinar (4º param '<ASSINATURA>')
6. Se execução longa ou sem atualização por janela operacional (20-30 min), publicar progresso com ETA revisado
7. update-status para 'Concluído' + comment final

Se erro: ler mensagem e ajustar. Nao usar subagente. Nao usar message.send.
Responder total processado e IDs.
```

Regras transversais adicionais:
- orçamento padrão: 1 card por rodada por cron/agente (salvo exceção explícita);
- após `update-status`, sempre validar estado final no Notion antes de seguir;
- se contexto do card for insuficiente para execução real, comentar motivo e mover para `Impedimento` (evitar loop);
- para triagem de diretor, usar lock curto em `Em andamento`, definir agente e retornar para `Priorizado`.
- para tarefas complexas, especialista deve criar micro-cards antes de executar; cada micro-card com ETA alvo curto (`<=30s`) e critério de pronto explícito.
- microplanejamento deve ser idempotente (marcador no card pai + sem recriação duplicada em novas rodadas).

Regra de atividade real (stale check):
- `last_edited_time` da página pode não refletir a atividade real do agente.
- Para detectar card parado, usar primeiro a última atividade assinada do agente nos comentários.
- Usar `last_edited_time` apenas como fallback.

## 🔧 Templates de Comentários

### Início de Execução
```
Iniciando [descrição da tarefa]. (<ASSINATURA>)
```

### Progresso (Etapa X/N)
```
Etapa X/N: [descrição do progresso]. (<ASSINATURA>)
```

### Conclusão
```
[Resumo da execução]. Card movido para Concluído. (<ASSINATURA>)
```

## 📊 Métricas e Monitoramento

### Indicadores de Qualidade
- **Taxa de conclusão:** % de cards Priorizado → Concluído
- **Tempo médio:** Duração por card (início → conclusão)
- **Qualidade de comentários:** Assinatura presente, progresso claro
- **Conformidade:** Adesão ao contrato central

### Logs e Rastreamento
- **Request IDs:** Registrar IDs de requisição Notion
- **Timestamps:** Incluir timestamps em comentários
- **IDs processados:** Reportar IDs no final da execução

## 🔄 Atualização e Manutenção

### Versões
- **1.0.0 (2026-02-21):** Contrato inicial baseado em auditoria de patterns

### Processo de Atualização
1. Identificar necessidade de mudança
2. Propor alteração via card "Governança"
3. Revisar impacto em todos os crons
4. Atualizar contrato central
5. Notificar e atualizar crons afetados

## 📚 Referências

### Crons Atuais (7 identificados)
1. Engenheiro SmartEnvios - varredura 30min
2. Engenheiro de Prompt - varredura 1h
3. Diretor Tech - varredura 30min
4. Diretor Pessoal - varredura 30min
5. Diretor Negócios - varredura 30min
6. Presidente - criar demandas e-mail (Pro+Person)
7. Governança - health check 10min

### Documentação Relacionada
- `AGENTS.md` - Regras gerais de agentes
- `TOOLS.md` - Ferramentas disponíveis
- `FLUXO_AGENTES.md` - Fluxo Notion completo
- `scripts/notion-helper.sh` - Script principal

---

**Aplicação:** Todos os novos crons devem seguir este contrato. Crons existentes devem ser atualizados para referenciar este documento central.
