# Guia de Implementação de Crons OpenClaw

**Versão:** 1.0.0  
**Data:** 2026-02-21  
**Status:** Ativo  
**Aplicável a:** Todos os novos crons OpenClaw

## 📋 Visão Geral

Este guia complementa o `cron-lifecycle.md` com padrões práticos para implementação de crons. Foca em modularidade, reutilização e manutenibilidade.

## 🎯 Princípios de Design

### 1. DRY (Don't Repeat Yourself)
- **Nunca** replicar regras de lifecycle em múltiplos crons
- **Sempre** referenciar contrato central `patterns/cron-lifecycle.md`
- **Centralizar** templates em `patterns/` para reutilização

### 2. Modularidade
- Dividir prompts extensos em módulos reutilizáveis
- Separar configuração, comandos e fluxo em seções distintas
- Usar placeholders para personalização por agente

### 3. Manutenibilidade
- Prompts claros e concisos
- Estrutura consistente entre crons
- Fácil identificação de responsabilidades

## 🏗️ Estrutura de Prompt Modular

### Template Base (3 módulos)
```
[MÓDULO 1: CONFIGURAÇÃO]
Atue como [NOME DO AGENTE] em modo STRICT.

USE EXCLUSIVAMENTE o script /var/www/openclaw/workspace/scripts/notion-helper.sh para TODAS as operações Notion.
NÃO tente curl direto nem 'openclaw notion query'.

DB: [DATABASE_ID]
API KEY VAR: [API_KEY_VAR]

[MÓDULO 2: COMANDOS]
COMANDOS DISPONÍVEIS (via exec):
- Buscar cards: /var/www/openclaw/workspace/scripts/notion-helper.sh query [DB] [API_KEY_VAR] '[AGENTE]'
- Mover status: /var/www/openclaw/workspace/scripts/notion-helper.sh update-status PAGE_ID [API_KEY_VAR] 'Em andamento'
- Comentar: /var/www/openclaw/workspace/scripts/notion-helper.sh comment PAGE_ID [API_KEY_VAR] 'Texto' '[ASSINATURA]'
- Ler página: /var/www/openclaw/workspace/scripts/notion-helper.sh get-page PAGE_ID [API_KEY_VAR]
- Ler blocos: /var/www/openclaw/workspace/scripts/notion-helper.sh get-blocks PAGE_ID [API_KEY_VAR]

[MÓDULO 3: FLUXO PADRÃO]
FLUXO (contrato central: patterns/cron-lifecycle.md):
1. Executar query para buscar cards Priorizado/Em andamento
2. Priorizar retomada: processar primeiro cards já em `Em andamento` (mais antigo sem atividade do agente), depois captar `Priorizado`
3. Para cada card captado de Priorizado: update-status para 'Em andamento' + comment de início (<=300 chars)
4. get-blocks para ler descrição, IMPLEMENTAR o pedido (você é o implementador; não existe "deixar para o Rafael executar").
   Fazer as edições em arquivos, cron/jobs.json, scripts.
   Se tiver permissão de escrita no repo: editar e commitar.
   Se não: comentário final com patch/diff ou conteúdo exato dos arquivos para aplicação sem decisão humana.
   Comentário só com sugestão sem edição = falha.
5. Comments progressivos com passo a passo: Etapa X/N (ex: Etapa 1/4, 2/4...), sempre assinar (4º param '[ASSINATURA]')
6. Se execução longa ou sem atualização por janela operacional (20-30 min), publicar progresso com ETA revisado
7. update-status para 'Concluído' + comment final

Se erro: ler mensagem e ajustar. Nao usar subagente. Nao usar message.send.
Responder total processado e IDs.
```

Checklist obrigatório de implementação:
- aplicar orçamento padrão de 1 card por rodada (quando não houver regra explícita diferente);
- confirmar status pós-write (`update-status` + leitura de verificação);
- se contexto insuficiente, comentar bloqueio e mover para `Impedimento` (não insistir em loop);
- em crons de diretor, executar triagem transacional curta (`Em andamento` -> roteamento -> `Priorizado`).
- em crons de especialista, implementar fatiamento obrigatório para demandas complexas (micro-cards com ETA curto e critério de pronto).
- tornar o fatiamento idempotente (marker no card pai para impedir duplicação entre rodadas).

Regra de atividade real (stale check):
- `last_edited_time` da página pode não refletir a atividade real do agente.
- Para detectar card parado, usar primeiro a última atividade assinada do agente nos comentários.
- Usar `last_edited_time` apenas como fallback.

### Módulos Específicos por Domínio

#### A. Engenheiros (Implementação Técnica)
```
[DOMÍNIO ESPECÍFICO]
Regras: [código/bugs/features SmartEnvios, MCP SmartEnvios, scripts, config].
Implementar = fazer as mudanças técnicas, não só analisar.

APROVAÇÃO OBRIGATÓRIA:
(1) Dados sensíveis (banco, nome de cliente): NUNCA alterar direto em produção.
    Criar script de migração/update ou card no Notion descrevendo a mudança e aguardar comentário "Aprovado" ou "aprovado" no card.
    Só executar após isso.
(2) Código: implementar em branch, abrir PR, criar ou atualizar card no Notion com link do PR.
    Deploy/merge só após comentário de aprovação no card ("Aprovado" ou "aprovado").
    Convenção: considera-se aprovado quando houver comentário do solicitante ou Rafael no card com a palavra "aprovado" ou "Aprovado".
```

#### B. Diretores (Triagem)
```
[DOMÍNIO ESPECÍFICO]
Objetivo: varredura generalista de tarefas do domínio [DOMÍNIO].

Função padrão:
- Captar cards OpenClaw em Aguardando.
- Normalizar: Status='Priorizado', Tipo='OpenClaw', Agente=especialista adequado.
- Escrever descrição técnica/funcional completa.
- Comentário de triagem OBRIGATÓRIO ao priorizar (resumo + agente destino).

Roteamento: [regras de roteamento específicas]

DEDUPLICAÇÃO: Antes de mover Aguardando->Priorizado, consultar Priorizado.
Se existir card com MESMO título E MESMO Agente, ESPERAR.

RESILIÊNCIA: Se query Notion falhar com validation_error, ajustar tipo de filtro e retentar.
```

#### C. Especialistas (Execução Operacional)
```
[DOMÍNIO ESPECÍFICO]
Execute exatamente este comando:
/var/www/openclaw/workspace/scripts/[script-especialista].sh [parâmetros]

Não use nenhum outro comando. Não use process/list/poll.
Sua resposta final deve ser SOMENTE o stdout literal do comando, sem explicações adicionais.
```

## 🔧 Templates de Comentários Padronizados

### Template 1: Início de Execução
```
Iniciando [descrição da tarefa]. ([ASSINATURA])
```

### Template 2: Progresso (Etapa X/N)
```
Etapa X/N: [descrição do progresso]. ([ASSINATURA])
```

### Template 3: Conclusão
```
[Resumo da execução]. Card movido para Concluído. ([ASSINATURA])
```

### Template 4: Triagem (Diretores)
```
Card priorizado para [ESPECIALISTA]. [Resumo da decisão]. ([ASSINATURA])
```

## 📁 Estrutura de Diretórios

```
workspace/patterns/
├── cron-lifecycle.md          # Contrato central (obrigatório)
├── cron-implementation-guide.md # Este guia
├── templates/
│   ├── prompt-base.md         # Template base (3 módulos)
│   ├── prompt-engineer.md     # Template para engenheiros
│   ├── prompt-director.md     # Template para diretores
│   └── prompt-specialist.md   # Template para especialistas
└── examples/
    ├── eng-smartenvios.json   # Exemplo completo
    └── director-tech.json     # Exemplo completo
```

## 🛠️ Processo de Criação de Novo Cron

### Passo 1: Escolher Template
```bash
# 1. Engenheiro (implementação técnica)
cp patterns/templates/prompt-engineer.md /tmp/new-cron-prompt.md

# 2. Diretor (triagem)
cp patterns/templates/prompt-director.md /tmp/new-cron-prompt.md

# 3. Especialista (execução operacional)
cp patterns/templates/prompt-specialist.md /tmp/new-cron-prompt.md
```

### Passo 2: Personalizar
```bash
# Substituir placeholders
sed -i '' 's/\[NOME DO AGENTE\]/Engenheiro SmartEnvios/g' /tmp/new-cron-prompt.md
sed -i '' 's/\[DATABASE_ID\]/adec12e735dc41a3bb7c274b287f3a10/g' /tmp/new-cron-prompt.md
sed -i '' 's/\[API_KEY_VAR\]/NOTION_SMARTENVIOS_API_KEY/g' /tmp/new-cron-prompt.md
sed -i '' 's/\[ASSINATURA\]/Engenheiro SmartEnvios/g' /tmp/new-cron-prompt.md
```

### Passo 3: Adicionar Domínio Específico
```bash
# Adicionar seção de domínio
cat patterns/templates/domain-smartenvios.md >> /tmp/new-cron-prompt.md
```

### Passo 4: Criar Cron
```bash
# Usar openclaw cron add
openclaw cron add \
  --name "Novo Cron" \
  --schedule '{"kind":"every","everyMs":1800000}' \
  --payload "{\"kind\":\"agentTurn\",\"message\":\"$(cat /tmp/new-cron-prompt.md)\"}" \
  --session-target isolated \
  --model deepseek/deepseek-chat
```

## 🔄 Atualização de Crons Existentes

### Crons Identificados para Atualização (7)
1. **Engenheiro SmartEnvios - varredura 30min** (ID: a7b8c9d0-e1f2-3456-7890-abcdef123401)
2. **Engenheiro de Prompt - varredura 1h** (ID: 6bdd82c7-081d-486b-9700-0572b9fce72e)
3. **Diretor Tech - varredura 30min** (ID: 9da1331a-2c84-4191-9e7d-87552039d8f1)
4. **Diretor Pessoal - varredura 30min** (ID: dd8959b6-0346-487f-8281-591249c8dc31)
5. **Diretor Negócios - varredura 30min** (ID: 12c33196-2e0e-4ce9-b616-98652b7db3ac)
6. **Presidente - criar demandas e-mail (Pro+Person)** (ID: 8c232f9a-b4aa-485f-83c8-99d348bb3176)
7. **Governança - health check 10min** (ID: e5bb7978-cd99-4e8d-924a-b4d42a140c1e)

### Passos de Atualização
```bash
# 1. Extrair prompt atual
openclaw cron get <ID> --json | jq -r '.payload.message' > /tmp/current-prompt.md

# 2. Modularizar (separar em 3 módulos)
# 3. Adicionar referência ao contrato central
# 4. Atualizar cron
openclaw cron edit <ID> --payload "{\"kind\":\"agentTurn\",\"message\":\"$(cat /tmp/new-modular-prompt.md)\"}"
```

## 📊 Métricas de Qualidade

### Indicadores de Conformidade
- **Referência ao contrato:** Presença de "contrato central: patterns/cron-lifecycle.md"
- **Modularidade:** Separação clara em 3 módulos
- **Assinatura:** Presença de assinatura em todos os comentários
- **Concisão:** Prompt <= 2000 tokens (ideal)

### Monitoramento
```bash
# Verificar conformidade
grep -c "contrato central" /Users/rafaelcanper/.openclaw/cron/jobs.json
grep -c "patterns/cron-lifecycle.md" /Users/rafaelcanper/.openclaw/cron/jobs.json
```

## 🚀 Melhores Práticas

### 1. Token Efficiency
- **Evitar:** Repetição de instruções idênticas
- **Prefira:** Referência a documento central
- **Ideal:** Prompt <= 1500 tokens para execução rápida

### 2. Error Handling
- **Resiliência:** Retry automático para erros de API
- **Fallback:** Scripts alternativos quando primário falha
- **Logging:** Registrar erros com contexto suficiente

### 3. Performance
- **Timeout:** Ajustar baseado na complexidade (ex: 300s para engenheiros, 120s para diretores)
- **Stagger:** Distribuir execuções para evitar picos
- **Session:** Usar `isolated` para crons pesados, `main` para leves

### 4. Security
- **API Keys:** Nunca hardcoded, sempre variáveis de ambiente
- **Paths:** Usar caminhos relativos ou variáveis (`OPENCLAW_CONFIG_DIR`)
- **Permissions:** Aplicar princípio do menor privilégio

## 📚 Referências

### Documentação Principal
- `AGENTS.md` - Regras gerais de agentes
- `TOOLS.md` - Ferramentas disponíveis
- `FLUXO_AGENTES.md` - Fluxo Notion completo

### Scripts Principais
- `scripts/notion-helper.sh` - Wrapper Notion API
- `scripts/gmail/process-notion-cards.sh` - Especialista Mail-Pro/Person
- `scripts/governance-check.sh` - Governança

### Contratos Relacionados
- `patterns/cron-lifecycle.md` - Contrato central de lifecycle
- `templates/agent-behavior-patterns.md` - Padrões de comportamento

---

**Aplicação:** Todos os novos crons devem seguir este guia. Crons existentes devem ser atualizados para conformidade até 2026-03-01.
