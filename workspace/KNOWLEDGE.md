# KNOWLEDGE.md - Historical Knowledge & Patterns

Este arquivo documenta padrões, descobertas e soluções que funcionaram bem para referência futura.

**⚠️ IMPORTANTE: Este arquivo deve ser atualizado sempre que aprendermos algo novo!**

Toda vez que descobrirmos um padrão, resolvermos um problema, ou configurarmos algo novo, devemos documentar aqui para referência futura. Este é o conhecimento histórico acumulado que permite replicar soluções e evitar erros já conhecidos.

## 2026-02-20 – Regra de Resiliência para Automação (atualizada 13:23)

**Princípio fundamental: TENTAR PRIMEIRO, FALHAR DEPOIS, NUNCA ASSUMIR**

### Regras obrigatórias para todos os especialistas

1. **Sempre executar scripts/APIs antes de declarar bloqueio:**
   - NUNCA assumir que credenciais estão vazias sem tentar
   - NUNCA declarar "sem token" sem executar o comando de autenticação
   - Se um script falhou ontem, TENTAR NOVAMENTE hoje (pode ter sido corrigido)

2. **Evidência concreta de erro:**
   - Copiar o output completo do comando que falhou
   - Registrar no card Notion: comando executado + erro retornado
   - Só então declarar bloqueio técnico

3. **Buscar identificadores via API quando necessário:**
   - Ex.: `GET /v1/users` no Notion para achar `Solicitante`
   - Documentar a tentativa concreta quando registrar pendência

4. **Aplicar a todos os agentes:**
   - Main, diretores, especialistas, Einstein

### Caso real: "Bloqueio de e-mail" falso (2026-02-20)

**Problema:** Especialistas Mail-Pro e Mail-Person declararam "sem GMAIL_PROFESSIONAL_REFRESH_TOKEN" em múltiplos runs, movendo cards para Concluído sem execução.

**Causa raiz:** Tokens EXISTIAM no .env e scripts gmail.sh FUNCIONAVAM perfeitamente, mas especialistas assumiram erro sem executar `./gmail.sh <profile> auth`.

**Fix aplicado:** 
- Prompts atualizados: "Só declarar bloqueio de credencial após teste real de Gmail API no run"
- Documentado em KNOWLEDGE.md como padrão obrigatório
- Regra: se script falhou antes, TENTAR DE NOVO (ambiente pode ter sido corrigido)

## 2026-02-20 – Discord Gateway Instável (issue conhecido)

**Sintoma:** Centenas de logs "Attempting resume with backoff" + "connection stalled: no HELLO received within 30000ms" durante horas.

**Causa raiz:** Discord.js não recupera gracefully de timeouts de rede. Issue conhecido da biblioteca discord.js, não há fix fácil no OpenClaw.

**Impacto:** Conexão Discord pode ficar instável por períodos longos (observado: 15h-16h em 2026-02-19), mas geralmente se recupera sozinha.

**Mitigação:**
- Se instabilidade persistir por >2h, considerar restart do gateway: `openclaw gateway restart`
- Monitorar logs em `/Users/rafaelcanper/.openclaw/logs/gateway.log`
- Se virar padrão diário, escalar para Rafael avaliar se vale trocar de biblioteca Discord

**Status:** Tolerável por enquanto — instabilidade não impede operação principal (WhatsApp, WebChat, Notion, Gmail funcionam independentemente).

---

## Como o OpenClaw Acessa Arquivos e Configurações

### Acesso a Arquivos do Sistema

O assistente do OpenClaw pode ler arquivos usando caminhos absolutos:

**Exemplo que funcionou:**
```
Read from /var/www/openclaw/.env
```

**Padrão identificado:**
- O assistente tem acesso ao sistema de arquivos completo
- Pode ler arquivos fora do workspace usando caminhos absolutos
- O workspace padrão é `/var/www/openclaw/workspace`
- Arquivos de configuração estão em `/var/www/openclaw/`

### Variáveis de Ambiente

**Como funciona:**
1. Variáveis são definidas no arquivo `.env` em `/var/www/openclaw/.env`
2. O OpenClaw lê automaticamente essas variáveis quando usa a sintaxe `${VAR_NAME}` no `openclaw.json`
3. O assistente pode ler o `.env` diretamente para verificar valores

**Padrão de configuração:**
```json
{
  "skills": {
    "entries": {
      "notion": {
        "apiKey": "${NOTION_SMARTENVIOS_API_KEY}"
      }
    }
  }
}
```

### Como o Assistente Descobriu os Notions

**Sequência de ações que funcionou:**

1. **Leitura direta do .env:**
   ```
   Read from /var/www/openclaw/.env
   ```
   - O assistente conseguiu ler o arquivo mesmo estando fora do workspace
   - Identificou todas as variáveis `NOTION_*_API_KEY`

2. **Leitura de documentação:**
   ```
   Read from /var/www/openclaw/workspace/NOTION.md
   ```
   - O arquivo `NOTION.md` foi criado previamente com informações sobre os workspaces
   - O assistente conseguiu correlacionar as informações

3. **Correlação de informações:**
   - Combinou dados do `.env` (tokens e database IDs)
   - Com informações do `NOTION.md` (nomes e descrições)
   - Para entender quais workspaces estão disponíveis

## Padrões de Documentação que Funcionam

### 1. Arquivos de Referência no Workspace

**Estrutura recomendada:**
- `NOTION.md` - Documentação específica de integrações
- `TOOLS.md` - Lista de tools e skills disponíveis
- `KNOWLEDGE.md` - Este arquivo (padrões e soluções)

**Como garantir que sejam lidos:**
- Adicionar referências no `AGENTS.md` na seção "Before doing anything else"
- O assistente segue essas instruções automaticamente

### 2. Documentação de Configurações

**Formato que funciona:**
```markdown
## Nome da Integração

- **Skill ID**: `skill-name`
- **API Key**: `${ENV_VAR_NAME}`
- **Database ID**: `id-aqui` (disponível no `.env`)
- **Status**: ✅ Ativo
```

### 3. Caminhos Absolutos vs Relativos

**Quando usar caminhos absolutos:**
- Arquivos de configuração fora do workspace (`/var/www/openclaw/.env`)
- Arquivos do sistema que o assistente precisa acessar

**Quando usar caminhos relativos:**
- Arquivos dentro do workspace (`workspace/NOTION.md`)
- O assistente entende o contexto do workspace

## Lições Aprendidas

### ✅ O que Funcionou Bem

1. **Criar múltiplas instâncias de skills:**
   - `notion`, `notion-personal`, `notion-canper`
   - Cada uma com sua própria API key do `.env`

2. **Documentar no workspace:**
   - Arquivos `.md` no workspace são facilmente acessíveis
   - O assistente lê automaticamente se referenciados no `AGENTS.md`

3. **Usar variáveis de ambiente:**
   - Sintaxe `${VAR_NAME}` no `openclaw.json`
   - Todas as chaves sensíveis no `.env`

4. **Leitura direta do .env:**
   - O assistente pode ler `/var/www/openclaw/.env` diretamente
   - Útil para verificar configurações ou debugar

### ❌ O que Não Funcionou

1. **Chaves não suportadas nas skills:**
   - `databaseId` e `alias` não são reconhecidos pela skill notion
   - Apenas `apiKey` é necessário na configuração

2. **Seção models.providers incorreta:**
   - Tentativa de criar `models.providers` com `baseUrl` e `models` arrays
   - O OpenClaw lê API keys automaticamente das variáveis de ambiente

## Como Replicar no Futuro

### Para Adicionar Nova Integração:

1. **Adicionar variáveis no `.env`:**
   ```bash
   NOVA_INTEGRACAO_API_KEY=chave-aqui
   NOVA_INTEGRACAO_DATABASE_ID=id-aqui
   ```

2. **Configurar no `openclaw.json`:**
   ```json
   "skills": {
     "entries": {
       "nova-integracao": {
         "apiKey": "${NOVA_INTEGRACAO_API_KEY}"
       }
     }
   }
   ```

3. **Documentar no workspace:**
   - Criar `NOVA_INTEGRACAO.md` ou adicionar em `TOOLS.md`
   - Incluir referência no `AGENTS.md` se necessário

4. **Testar:**
   - Pedir ao assistente para listar integrações disponíveis
   - Verificar se ele consegue ler o `.env` e documentação

### Para Debugar Problemas:

1. **Verificar se o assistente pode ler o arquivo:**
   ```
   Read from /caminho/absoluto/arquivo
   ```

2. **Verificar variáveis de ambiente:**
   ```
   Read from /var/www/openclaw/.env
   ```

3. **Verificar configuração:**
   ```
   Read from /var/www/openclaw/openclaw.json
   ```

## Estrutura de Arquivos Recomendada

```
/var/www/openclaw/
├── .env                          # Variáveis de ambiente (todos os tokens)
├── openclaw.json                 # Configuração principal
└── workspace/
    ├── AGENTS.md                 # Instruções de inicialização
    ├── SOUL.md                   # Personalidade do assistente
    ├── USER.md                   # Informações sobre o usuário
    ├── TOOLS.md                  # Lista de tools disponíveis
    ├── NOTION.md                 # Documentação específica do Notion
    ├── KNOWLEDGE.md              # Este arquivo (padrões históricos)
    └── memory/                   # Memórias diárias
        └── YYYY-MM-DD.md
```

## Comandos Úteis para o Assistente

**Verificar configurações:**
- `Read from /var/www/openclaw/.env`
- `Read from /var/www/openclaw/openclaw.json`

**Verificar documentação:**
- `Read from /var/www/openclaw/workspace/TOOLS.md`
- `Read from /var/www/openclaw/workspace/NOTION.md`

**Listar arquivos:**
- `Exec: ls -la /var/www/openclaw/`
- `Exec: ls -la /var/www/openclaw/workspace/`

---

## Sessão de Configuração Inicial - 2026-02-19

### O que foi feito nesta sessão:

#### 1. Migração do Diretório OpenClaw

**Problema inicial:**
- OpenClaw instalado em `~/.openclaw` (diretório home do usuário)
- Necessidade de mover para `/var/www/openclaw`

**Solução implementada:**
1. Criado script `move-openclaw.sh` para copiar arquivos com `rsync`
2. Corrigido script para macOS (usar `--extended-attributes` ao invés de `-X`)
3. Criado link simbólico: `~/.openclaw` → `/var/www/openclaw`
4. Atualizado `openclaw.json` para usar novo caminho do workspace

**Comandos usados:**
```bash
# Script de migração
sudo rsync -av --extended-attributes ~/.openclaw/ /var/www/openclaw/
sudo ln -s /var/www/openclaw ~/.openclaw
```

**Resultado:**
- Todos os arquivos migrados com sucesso
- Link simbólico mantém compatibilidade
- Workspace configurado em `/var/www/openclaw/workspace`

#### 2. Configuração de Skills com Variáveis de Ambiente

**Padrão estabelecido:**
- Todas as API keys devem estar no arquivo `.env`
- Skills usam sintaxe `${VAR_NAME}` no `openclaw.json`
- Nunca hardcodar chaves diretamente no JSON

**Skills configuradas:**
- `nano-banana-pro`: `${GEMINI_API_KEY}`
- `notion`: `${NOTION_SMARTENVIOS_API_KEY}`
- `notion-personal`: `${NOTION_PERSONAL_API_KEY}`
- `notion-canper`: `${NOTION_CANPER_API_KEY}`
- `sag`: `${SAG_API_KEY}`

#### 3. Configuração de Múltiplos Modelos de IA

**Modelos adicionados como opções (15 total):**

**OpenAI (4):**
- `openai/gpt-5.1-codex` (primário)
- `openai/gpt-4-turbo`
- `openai/gpt-4`
- `openai/gpt-3.5-turbo`

**Anthropic (5):**
- `anthropic/claude-3.7-sonnet`
- `anthropic/claude-3.5-sonnet`
- `anthropic/claude-3-opus`
- `anthropic/claude-3-sonnet`
- `anthropic/claude-3-haiku`

**Google/Gemini (4):**
- `google/gemini-1.5-pro`
- `google/gemini-1.5-flash`
- `google/gemini-pro`
- `google/gemini-ultra`

**X.AI/Grok (2):**
- `xai/grok-beta`
- `xai/grok-2`

**Importante:** API keys são lidas automaticamente das variáveis de ambiente:
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`
- `GROK_API_KEY`

#### 4. Configuração de Múltiplas Instâncias do Notion

**Problema:**
- 3 workspaces do Notion configurados no `.env`
- Skill notion só aceitava uma API key

**Solução:**
- Criar 3 instâncias separadas da skill:
  - `notion` (SmartEnvios - padrão)
  - `notion-personal` (Personal)
  - `notion-canper` (Canper)

**Erros encontrados e corrigidos:**
1. Tentativa de usar `databaseId` e `alias` → não suportado pela skill
2. Tentativa de criar `models.providers` → estrutura incorreta
3. Solução: apenas `apiKey` é necessário na configuração

#### 5. Estrutura de Documentação Criada

**Arquivos criados no workspace:**
- `NOTION.md` - Documentação dos 3 workspaces do Notion
- `TOOLS.md` - Lista de todas as skills e tools disponíveis
- `KNOWLEDGE.md` - Este arquivo (padrões históricos)

**Atualização no AGENTS.md:**
- Adicionadas referências para leitura automática de:
  - `NOTION.md`
  - `TOOLS.md`
  - `KNOWLEDGE.md` (quando necessário para debug)

#### 6. Descoberta: Como o Assistente Acessa Arquivos

**Padrão identificado:**
- O assistente pode ler arquivos usando caminhos absolutos
- Exemplo: `Read from /var/www/openclaw/.env`
- Tem acesso completo ao sistema de arquivos
- Pode correlacionar informações de múltiplas fontes

**Sequência que funcionou:**
1. Assistente leu `.env` diretamente
2. Identificou variáveis `NOTION_*_API_KEY`
3. Leu `NOTION.md` para contexto
4. Correlacionou informações automaticamente

### Estrutura Final de Configuração

```
/var/www/openclaw/
├── .env                          # Todas as variáveis de ambiente
│   ├── OPENAI_API_KEY
│   ├── ANTHROPIC_API_KEY
│   ├── GEMINI_API_KEY
│   ├── GROK_API_KEY
│   ├── NOTION_PERSONAL_API_KEY
│   ├── NOTION_SMARTENVIOS_API_KEY
│   ├── NOTION_CANPER_API_KEY
│   └── (outras variáveis...)
├── openclaw.json                 # Configuração principal
│   ├── agents.defaults.models    # 15 modelos configurados
│   ├── skills.entries            # 5 skills configuradas
│   └── workspace                 # /var/www/openclaw/workspace
└── workspace/
    ├── AGENTS.md                 # Instruções de inicialização
    ├── SOUL.md                   # Personalidade
    ├── USER.md                   # Informações do usuário
    ├── TOOLS.md                  # Skills e tools disponíveis
    ├── NOTION.md                 # Documentação Notion
    ├── KNOWLEDGE.md              # Este arquivo
    └── memory/                   # Memórias diárias
```

### Comandos Úteis Descobertos

**Para verificar configurações:**
```bash
# Verificar JSON
cat /var/www/openclaw/openclaw.json | python3 -m json.tool

# Verificar variáveis
grep NOTION /var/www/openclaw/.env

# Verificar link simbólico
readlink ~/.openclaw
```

**Para o assistente usar:**
- `Read from /var/www/openclaw/.env` - Ver variáveis
- `Read from /var/www/openclaw/openclaw.json` - Ver configuração
- `Read from /var/www/openclaw/workspace/NOTION.md` - Ver documentação

### Lições Críticas desta Sessão

1. **Sempre usar variáveis de ambiente** - Nunca hardcodar chaves
2. **Testar JSON após mudanças** - Validar antes de reiniciar gateway
3. **Documentar no workspace** - Arquivos `.md` são facilmente acessíveis
4. **Múltiplas instâncias funcionam** - Criar skills separadas para diferentes credenciais
5. **O assistente é inteligente** - Consegue ler `.env` e correlacionar informações
6. **Link simbólico mantém compatibilidade** - `~/.openclaw` → `/var/www/openclaw`

### Próximos Passos Identificados

- [x] Configurar logging detalhado para monitoramento completo
- [ ] Configurar agentes específicos para cada workspace do Notion
- [ ] Testar operações com cada skill do Notion
- [ ] Configurar rotas de agentes baseadas em contexto

---

**Última atualização:** 2026-02-19 16:50
**Sessão:** Configuração inicial completa - migração, skills, modelos, documentação e logging detalhado

---

## Problema Device Token Mismatch - Resolução Completa

### Situação Encontrada:

Após executar `openclaw doctor --fix`, o problema de "device token mismatch" persistiu porque:
- O doctor atualizou o arquivo de configuração
- Criou backup em `openclaw.json.bak`
- Mas o gateway ainda estava rodando com o token antigo
- O CLI não conseguia conectar devido ao token desatualizado

### Solução Completa:

**Passo a passo para resolver:**

1. **Parar o gateway completamente:**
   ```bash
   openclaw gateway stop
   ```

2. **Aguardar alguns segundos para garantir que parou:**
   ```bash
   sleep 3
   ```

3. **Verificar se realmente parou:**
   ```bash
   openclaw gateway status
   ```

4. **Se ainda estiver rodando, forçar parada:**
   ```bash
   launchctl bootout gui/$UID/ai.openclaw.gateway
   ```

5. **Reinstalar o gateway para sincronizar token:**
   ```bash
   openclaw gateway install --force
   ```

6. **Reiniciar o gateway:**
   ```bash
   openclaw gateway restart
   ```

7. **Verificar se está funcionando:**
   ```bash
   openclaw gateway status
   openclaw logs --follow
   ```

### O que o Doctor Faz:

- Atualiza configuração (`openclaw.json`)
- Cria backup automático (`openclaw.json.bak`)
- Reinstala LaunchAgent se necessário
- Mas **não reinicia o gateway automaticamente**

### Lição Aprendida:

**Sempre após `openclaw doctor --fix`:**
1. Verificar se o gateway precisa ser reiniciado
2. Parar completamente o gateway
3. Reiniciar o gateway
4. Verificar logs para confirmar que está funcionando

### Comandos de Verificação:

```bash
# Ver status do gateway
openclaw gateway status

# Ver se porta está em uso
lsof -i :18789

# Ver processos do gateway
ps aux | grep openclaw

# Ver logs em tempo real
openclaw logs --follow
```

---

## Observações sobre Logs - 2026-02-19

### Logs Funcionando Corretamente ✅

**Confirmação:**
- Logs estão sendo gerados em formato JSONL (JSON Lines)
- Cada linha é um objeto JSON completo com metadados detalhados
- Arquivo: `/var/www/openclaw/logs/gateway.log`
- Formato inclui: timestamp, nível de log, arquivo origem, linha, método, etc.

**Estrutura de um log JSONL:**
```json
{
  "0": "mensagem do log",
  "_meta": {
    "runtime": "node",
    "runtimeVersion": "22.22.0",
    "logLevelName": "ERROR|WARN|INFO|DEBUG",
    "path": {
      "fullFilePath": "caminho/completo/arquivo.js",
      "fileName": "arquivo.js",
      "fileLine": "123",
      "fileColumn": "45",
      "method": "nomeDoMetodo"
    },
    "date": "2026-02-19T16:42:02.673Z"
  },
  "time": "2026-02-19T16:42:02.674Z"
}
```

### Problema Encontrado: Device Token Mismatch

**Erro observado:**
```
gateway connect failed: Error: unauthorized: device token mismatch (rotate/reissue device token)
```

**Causa:**
- Após migrar o diretório de `~/.openclaw` para `/var/www/openclaw`
- O token do dispositivo pode ter ficado desatualizado
- O gateway precisa sincronizar o token com o serviço

**Solução:**
```bash
# Opção 1: Executar doctor para corrigir automaticamente
openclaw doctor --fix

# Opção 2: Forçar reinstalação do gateway para sincronizar token
openclaw gateway install --force

# Depois reiniciar
openclaw gateway restart
```

**Prevenção:**
- Sempre executar `openclaw doctor` após mudanças significativas
- Verificar logs após reiniciar o gateway
- Se aparecer "device token mismatch", executar `openclaw gateway install --force`

**Observação importante:**
- O `openclaw doctor --fix` atualiza o arquivo de configuração e cria backup
- Após o doctor, é necessário reiniciar o gateway para aplicar mudanças
- O problema de "device token mismatch" pode persistir até o gateway ser reiniciado corretamente
- O gateway pode estar rodando mas o CLI não consegue conectar devido ao token desatualizado

**Sequência completa para resolver:**

**Opção 1: Rotacionar device token (recomendado)**
```bash
# Listar dispositivos
openclaw devices list

# Rotacionar token do dispositivo
openclaw devices rotate --device <deviceId> --role operator

# Reiniciar gateway
openclaw gateway restart
```

**Opção 2: Reinstalar gateway completamente**
```bash
# 1. Parar gateway
openclaw gateway stop

# 2. Remover arquivo de device-auth para forçar regeneração
rm /var/www/openclaw/identity/device-auth.json

# 3. Reinstalar gateway
openclaw gateway install --force

# 4. Reiniciar
openclaw gateway restart

# 5. Verificar
openclaw gateway status
```

**Opção 3: Sincronizar tokens manualmente**
```bash
# 1. Verificar token no openclaw.json
grep '"token"' /var/www/openclaw/openclaw.json

# 2. Verificar token no LaunchAgent
grep OPENCLAW_GATEWAY_TOKEN ~/Library/LaunchAgents/ai.openclaw.gateway.plist

# 3. Se diferentes, editar plist e sincronizar
# 4. Recarregar LaunchAgent
launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist
launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist
```

**Nota importante:**
- O "device token" é diferente do "gateway token"
- Device token: usado para autenticação de dispositivos (CLI, nodes, etc.)
- Gateway token: usado para autenticação do gateway em si
- O erro "device token mismatch" indica problema com device token, não gateway token

**Diagnóstico do problema encontrado:**
- `device-auth.json` estava com `tokens: {}` vazio
- Isso indica que o device token não foi gerado ou foi perdido
- Após migração do diretório, pode ser necessário regenerar

**Solução mais direta (quando device-auth.json está vazio):**
```bash
# 1. Parar gateway
openclaw gateway stop

# 2. Remover device-auth.json para forçar regeneração
rm /var/www/openclaw/identity/device-auth.json

# 3. Reinstalar gateway (vai regenerar o token)
openclaw gateway install --force

# 4. Reiniciar
openclaw gateway restart

# 5. Verificar
openclaw gateway status
openclaw logs --follow
```

**Se o problema persistir:**
- Verificar se o gateway está realmente rodando: `openclaw gateway status`
- Se o RPC probe está ok, o gateway funciona mas o CLI não conecta
- Pode ser necessário fazer pairing novamente do dispositivo CLI

### Análise de Logs JSONL

**Para processar logs JSONL:**
```bash
# Ver logs formatados com jq
tail -f /var/www/openclaw/logs/gateway.log | jq

# Filtrar apenas erros
grep '"logLevelName":"ERROR"' /var/www/openclaw/logs/gateway.log | jq

# Filtrar por subsistema
grep '"subsystem":"gateway/ws"' /var/www/openclaw/logs/gateway.log | jq

# Extrair apenas mensagens
cat /var/www/openclaw/logs/gateway.log | jq -r '.["0"]'
```

**Campos importantes nos logs:**
- `["0"]` - Mensagem principal do log
- `_meta.logLevelName` - Nível (ERROR, WARN, INFO, DEBUG)
- `_meta.path.fileName` - Arquivo origem
- `_meta.path.fileLine` - Linha do código
- `time` - Timestamp ISO 8601

---

## Configuração de Logging Detalhado - 2026-02-19

**Dois âmbitos:** O que está abaixo descreve o **logging operacional** (gateway, ficheiros, níveis). Para regras do que logar **dentro do código** (subsistemas, erros com requestId/errorCode, redacção), ver [PLANO_PROJETO.md](PLANO_PROJETO.md) e [docs/development/LOGGING_AND_RULES.md](docs/development/LOGGING_AND_RULES.md).

### O que foi configurado:

**Logging completo habilitado no `openclaw.json`:**

```json
{
  "logging": {
    "level": "debug",
    "consoleLevel": "debug",
    "consoleStyle": "pretty",
    "file": "/var/www/openclaw/logs/gateway.log"
  },
  "diagnostics": {
    "flags": [
      "gateway.*",
      "whatsapp.*",
      "notion.*",
      "agent.*",
      "session.*",
      "skill.*",
      "channel.*",
      "ws.*"
    ]
  }
}
```

### Níveis de Log Disponíveis:

- **`info`** - Informações gerais (padrão)
- **`debug`** - Logs detalhados de debug
- **`trace`** - Logs extremamente verbosos (cuidado com volume)

### Configurações Explicadas:

1. **`logging.level`**: Nível de log para arquivo (JSONL)
   - `debug` = logs detalhados de todas as operações

2. **`logging.consoleLevel`**: Nível de log para console
   - `debug` = mostra tudo no terminal também

3. **`logging.consoleStyle`**: Formato de saída no console
   - `pretty` = formato legível com cores e timestamps
   - `compact` = formato mais compacto
   - `json` = formato JSON por linha (para processadores de log)

4. **`logging.file`**: Caminho do arquivo de log
   - `/var/www/openclaw/logs/gateway.log` = logs persistentes

5. **`diagnostics.flags`**: Flags de diagnóstico específicos
   - `gateway.*` = todos os logs do gateway
   - `whatsapp.*` = logs do WhatsApp
   - `notion.*` = logs das skills do Notion
   - `agent.*` = logs dos agentes
   - `session.*` = logs de sessões
   - `skill.*` = logs de skills
   - `channel.*` = logs de canais
   - `ws.*` = logs de WebSocket

### Como Monitorar os Logs:

**1. Ver logs em tempo real:**
```bash
openclaw logs --follow
```

**2. Ver logs de canal específico:**
```bash
openclaw channels logs --channel whatsapp
```

**3. Ver arquivo de log diretamente:**
```bash
tail -f /var/www/openclaw/logs/gateway.log
```

**4. Ver logs de erro:**
```bash
tail -f /var/www/openclaw/logs/gateway.err.log
```

**5. Ver logs no Control UI:**
- Acessar a aba "Logs" no dashboard web

### Estrutura de Logs:

```
/var/www/openclaw/logs/
├── gateway.log              # Log principal (JSONL)
├── gateway.err.log          # Log de erros
└── config-audit.jsonl       # Auditoria de configuração
```

### Flags de Diagnóstico Disponíveis:

Você pode adicionar flags específicos para debugar subsistemas:

- `gateway.*` - Gateway e WebSocket
- `whatsapp.*` - WhatsApp provider
- `telegram.*` - Telegram provider
- `notion.*` - Notion skills
- `agent.*` - Agentes e loops
- `session.*` - Sessões e memória
- `skill.*` - Skills e tools
- `channel.*` - Canais e mensagens
- `ws.*` - WebSocket connections

**Exemplo para debug específico:**
```json
{
  "diagnostics": {
    "flags": ["whatsapp.http", "notion.api"]
  }
}
```

### Ajustando Nível de Verbosidade:

**Para produção (menos verboso):**
```json
{
  "logging": {
    "level": "info",
    "consoleLevel": "info"
  }
}
```

**Para desenvolvimento (muito verboso):**
```json
{
  "logging": {
    "level": "trace",
    "consoleLevel": "debug"
  }
}
```

**Para monitoramento detalhado (recomendado):**
```json
{
  "logging": {
    "level": "debug",
    "consoleLevel": "info"
  }
}
```

### Rotação de Logs:

O OpenClaw cria logs diários automaticamente:
- `/tmp/openclaw/openclaw-YYYY-MM-DD.log` (padrão)
- `/var/www/openclaw/logs/gateway.log` (configurado)

Para gerenciar rotação manualmente:
```bash
# Rotacionar logs antigos
mv /var/www/openclaw/logs/gateway.log /var/www/openclaw/logs/gateway-$(date +%Y%m%d).log
```

### Monitoramento Recomendado:

1. **Logs principais**: `/var/www/openclaw/logs/gateway.log`
2. **Logs de erro**: `/var/www/openclaw/logs/gateway.err.log`
3. **Auditoria**: `/var/www/openclaw/logs/config-audit.jsonl`

**Comandos úteis:**
```bash
# Ver últimas 100 linhas
tail -n 100 /var/www/openclaw/logs/gateway.log

# Filtrar por erro
grep -i error /var/www/openclaw/logs/gateway.log

# Filtrar por skill específica
grep "notion" /var/www/openclaw/logs/gateway.log

# Contar eventos
wc -l /var/www/openclaw/logs/gateway.log

# Ver logs em tempo real (formato legível)
openclaw logs --follow

# Ver logs formatados (JSON)
tail -f /var/www/openclaw/logs/gateway.log | jq
```

### Formato dos Logs

**Os logs são salvos em formato JSONL (JSON Lines):**
- Cada linha é um objeto JSON completo
- Contém metadados detalhados: timestamp, nível, arquivo origem, linha, etc.
- Facilita parsing e análise programática

**Estrutura de um log:**
```json
{
  "0": "mensagem do log",
  "_meta": {
    "runtime": "node",
    "runtimeVersion": "22.22.0",
    "logLevelName": "ERROR|WARN|INFO|DEBUG",
    "path": {
      "fullFilePath": "...",
      "fileName": "...",
      "fileLine": "..."
    },
    "date": "2026-02-19T16:42:02.673Z"
  },
  "time": "2026-02-19T16:42:02.674Z"
}
```

### Problema Device Token Mismatch — Causa e Solução Definitiva

**Erro observado:**
```
gateway connect failed: Error: unauthorized: device token mismatch (rotate/reissue device token)
```

**Causa raiz:**
- O **gateway** guarda os device tokens em `/var/www/openclaw/devices/paired.json`.
- O **CLI** guarda o seu token em `/var/www/openclaw/identity/device-auth.json`.
- Quando o gateway responde com "device token mismatch", o **próprio cliente OpenClaw** chama `clearDeviceAuthToken` e **apaga** o token em `device-auth.json`, deixando `tokens: {}`.
- O gateway continua com o token antigo em `paired.json`; o CLI fica sem token → toda nova tentativa falha.

**Solução aplicada (restaurar token do gateway no CLI):**

1. Ver o token do seu dispositivo no gateway:
   ```bash
   cat /var/www/openclaw/devices/paired.json | python3 -m json.tool
   ```
   Localize o objeto cujo `deviceId` é o mesmo de `identity/device.json` e anote `tokens.operator.token`.

2. Preencher `identity/device-auth.json` com a estrutura esperada (mesmo `deviceId` que em `device.json`):
   ```json
   {
     "version": 1,
     "deviceId": "<mesmo deviceId de device.json>",
     "tokens": {
       "operator": {
         "token": "<valor de tokens.operator.token do paired.json>",
         "role": "operator",
         "scopes": ["operator.admin", "operator.approvals", "operator.pairing"],
         "updatedAtMs": <createdAtMs do paired.json ou Date.now()>
       }
     }
   }
   ```

3. Garantir que o CLI use o mesmo diretório que o gateway: `~/.openclaw` deve ser **symlink** para `/var/www/openclaw`. Se for um diretório real, o CLI lê outro `identity/device-auth.json` e o token restaurado não vale.
   ```bash
   ls -la ~/.openclaw   # deve mostrar: ... -> /var/www/openclaw
   ```

4. Reiniciar o gateway para recarregar `paired.json` do disco e testar em seguida:
   ```bash
   openclaw gateway restart
   openclaw logs --follow
   ```

5. Se ainda falhar, usar o **gateway token** (auth compartilhada): o `--token` é opção do **subcomando**, não do `openclaw`:
   ```bash
   openclaw logs --token 97fb8d9c326a7d30f9b888d825c68d45f7cc3fad919ca763 --follow
   ```
   (O valor vem de `gateway.auth.token` no `openclaw.json`.)

**Alternativa (novo pairing):** Se remover `device-auth.json` e reinstalar o gateway não repopular o token (porque o CLI limpa ao receber mismatch), a saída é restaurar manualmente como acima ou fazer um novo pairing (ex.: `openclaw devices approve --latest` **após** conseguir conectar uma vez com o gateway token em `openclaw.json` ou `--token`, se o modo local permitir).

**Prevenção:**
- Evitar reinícios/alterações que gerem mismatch; quando houver, preferir restaurar de `paired.json` em vez de só deletar `device-auth.json`.

### Usar tudo em /var/www/openclaw (config + gateway + logs)

Para que **CLI e gateway** usem o mesmo config, logs e workspace em `/var/www/openclaw`:

1. **Parar o gateway e matar o processo** que estiver na porta (evita “already running”):
   ```bash
   openclaw gateway stop
   lsof -i :18789   # anote o PID do openclaw-gateway
   kill -9 <PID>    # use o PID anotado
   ```

2. **Fazer `~/.openclaw` apontar para `/var/www/openclaw`:**
   ```bash
   # Se ~/.openclaw já for symlink para /var/www/openclaw, nada a fazer.
   ls -la ~/.openclaw
   # Se for diretório real, fazer backup e trocar por symlink:
   mv ~/.openclaw ~/.openclaw.bak.$(date +%Y%m%d)
   ln -s /var/www/openclaw ~/.openclaw
   ```

3. **Garantir que o config principal está em /var/www/openclaw:**  
   O `openclaw.json` e o `.env` que o gateway deve usar ficam em `/var/www/openclaw`. Se você tinha coisas só em `~/.openclaw.bak.*`, copie o que faltar (ex.: `gateway.auth.token`, `agents`, etc.) para `/var/www/openclaw/openclaw.json`.

4. **Reinstalar e iniciar o gateway** (agora o LaunchAgent vai usar o mesmo dir via `~/.openclaw` → `/var/www/openclaw`):
   ```bash
   openclaw gateway install
   openclaw gateway start
   ```

5. **Conferir:** logs em `/var/www/openclaw/logs/gateway.log`, config em `/var/www/openclaw/openclaw.json`.  
   Sempre que rodar `openclaw` (de qualquer pasta), o CLI também usará `/var/www/openclaw` enquanto `~/.openclaw` for o symlink.

### Sincronizar com as atualizações do repositório oficial

O diretório `/var/www/openclaw` contém **apenas config, workspace e dados**; o código do OpenClaw vem do pacote instalado (npm global ou outro). Para ficar em dia com o projeto oficial:

**Repositório oficial:** [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw)  
**Pacote npm:** `openclaw`

1. **Se o OpenClaw foi instalado via npm global** (caso mais comum):
   ```bash
   # Ver versão instalada
   openclaw --version

   # Atualizar para a última versão publicada no npm
   npm update -g openclaw

   # Ou forçar instalação da última (recomendado para “sync” explícito)
   npm install -g openclaw@latest
   ```

2. **Reiniciar o gateway** após atualizar, para que o processo use o novo binário:
   ```bash
   openclaw gateway restart
   ```

3. **Se quiser acompanhar o código-fonte** (desenvolvedor/contribuidor):
   - Clonar o repositório em outro diretório (não substituir `/var/www/openclaw`):
     `git clone https://github.com/openclaw/openclaw.git`
   - Entrar no clone, puxar atualizações e seguir o README para build/run:
     `git pull`, `npm install`, `npm run build` (ou o que o projeto indicar).
   - O config continua em `/var/www/openclaw`; o binário de desenvolvimento usa esse config se `~/.openclaw` for symlink para `/var/www/openclaw`.

**Nota:** Sua configuração (`.env`, `openclaw.json`, workspace, logs) em `/var/www/openclaw` **não é sobrescrita** pela atualização do pacote; apenas o executável `openclaw` (CLI e gateway) é atualizado.

### 401 OpenAI "Incorrect API key" — OPENCLAW_CONFIG_DIR apontando para outro dir

Se aparecer `401 Incorrect API key provided` para a OpenAI mesmo com o token correto no `.env` de `/var/www/openclaw`:

**Causa comum:** no `.env` as variáveis `OPENCLAW_CONFIG_DIR` e `OPENCLAW_WORKSPACE_DIR` estavam apontando para **outro diretório** (ex.: pasta Docker em outro path). O gateway carrega o config (e por vezes um segundo `.env`) desse dir e usa a `OPENAI_API_KEY` de lá, que pode ser antiga ou diferente.

**O que fazer:**
1. Garantir no `/var/www/openclaw/.env`:
   ```
   OPENCLAW_CONFIG_DIR=/var/www/openclaw
   OPENCLAW_WORKSPACE_DIR=/var/www/openclaw/workspace
   ```
2. Reiniciar o gateway para recarregar variáveis: `openclaw gateway restart`.
3. Se ainda der 401, o processo do gateway pode estar sendo iniciado **sem** ler esse `.env` (ex.: LaunchAgent). Nesse caso, definir as variáveis no **plist** do gateway para o processo já nascer com o config certo:
   - Editar `~/Library/LaunchAgents/ai.openclaw.gateway.plist`
   - Na seção `<dict>` do job, adicionar (ou ajustar) algo como:
     ```xml
     <key>EnvironmentVariables</key>
     <dict>
       <key>OPENCLAW_CONFIG_DIR</key>
       <string>/var/www/openclaw</string>
       <key>OPENCLAW_WORKSPACE_DIR</key>
       <string>/var/www/openclaw/workspace</string>
     </dict>
     ```
   - Recarregar: `launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist` e `launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist`, ou `openclaw gateway restart`.

**Formato do `.env`:** a linha da chave deve ser uma única linha, sem aspas em volta do valor e sem espaço/newline no fim: `OPENAI_API_KEY=sk-proj-...`.

### Logs com `--token` e ruído "Gateway already running"

Depois de usar `openclaw logs --token <gateway.token> --follow`, o stream funciona. Se aparecer muitas linhas de erro no log como:
- `Gateway already running locally. Stop it (openclaw gateway stop) or use a different port.`
- `Gateway failed to start: gateway already running (pid …); lock timeout after 5000ms`
- `Port 18789 is already in use.`

**Causa:** algum outro processo (por exemplo a Control UI no browser, ou outro cliente OpenClaw) está tentando **iniciar** um segundo gateway em vez de apenas **conectar** ao que já está rodando sob o LaunchAgent. O gateway principal (pid no log) está correto; o que falha é a tentativa duplicada de start.

**O que fazer:**
- **Principal causa:** a **Control UI** (dashboard em http://127.0.0.1:18789/) tenta iniciar o gateway periodicamente. **Feche a aba do dashboard** quando não estiver usando; isso para o ruído de "Gateway already running".
- Se precisar do dashboard aberto, o ruído continuará; pode filtrar no terminal, ex.: `openclaw logs --token <token> --follow | grep -v "already running"`.
- Para ver mais linhas de log de uma vez use `--max-bytes` **no máximo 1000000** (o gateway rejeita valores maiores): `openclaw logs --token <token> --follow --max-bytes 1000000`.

### Erro "maxBytes: must be <= 1000000"

Se aparecer no log:
```
invalid logs.tail params: at /maxBytes: must be <= 1000000
```
é porque algum cliente (CLI ou Control UI) pediu tail de log com mais de 1 MB. Use no máximo:
```bash
openclaw logs --token <token> --follow --max-bytes 1000000
```

### Chat / agente: run com `isError=true` sem mensagem de erro no log

Se no Dashboard (Chat) a resposta não aparece e nos logs do gateway você vê apenas:
- `embedded run agent end: runId=... isError=true`
- `embedded run done: ... aborted=false`

e **não** há nenhuma linha de nível ERROR com a exceção real (API, provider, etc.):

**Causa:** o OpenClaw marca o run como falha mas não registra a exceção subjacente no `gateway.log` (comportamento atual do produto).

**O que fazer:**
- Procurar por `runId` ou `sessionId` no log: `grep "<runId>" /var/www/openclaw/logs/gateway.log` — às vezes o erro aparece noutro subsistema (ex.: openai) no mesmo intervalo de tempo.
- Procurar ERROR por horário: `grep '"logLevelName":"ERROR"' /var/www/openclaw/logs/gateway.log | grep "HH:MM"` (use o horário em UTC do log). Atenção: o prefixo legível pode ser 22:41 enquanto o JSON tem `"date":"...T18:22:41"` (outro fuso).
- Se mesmo assim não houver mensagem: a causa fica invisível no log; vale reportar ao projeto OpenClaw (pedir que o agente em erro logue a exceção em nível ERROR).
- Repetir a ação no Chat ou tentar em outro canal (ex.: WhatsApp) para ver se foi condição passageira (rate limit, timeout).

---

## 2026-02-20 — Fluxo Notion padronizado e escalonamento de crons

### Padrão de propriedades de card OpenClaw
- **Status**: Aguardando → Priorizado → Em andamento → Concluído
- **Tipo**: OpenClaw (sempre)
- **Solicitante**: Rafael Pereira (sempre)
- **Agente**: responsável pela próxima etapa

Template oficial: `templates/notion-card-openclaw.md`

### Deduplicação por chave dupla (Assunto + Agente)
Cada agente checa duplicidade no seu **status de saída**, não de entrada:
- Presidente → checa Aguardando
- Diretor → checa Priorizado
- Especialista → checa Em andamento

Se já existir card com mesmo título + mesmo Agente no status de saída, **esperar próximo ciclo**.

### Escalonamento de crons para evitar rate limit
**Problema**: Crons simultâneos esgotam rate limit de todos os providers em segundos.
**Causa**: Cada cron que falha tenta 4 modelos em sequência (~2s cada). Múltiplos crons fazendo isso = rate limit global.
**Solução**:
- Distribuir anchors com gap mínimo de 2min entre crons
- `maxConcurrent: 2` (máximo 2 crons simultâneos)
- Governança redistribui automaticamente se detectar colisão
- Script: `governance-check.sh` (seção escalonamento automático)

### Profile "minimal" não registra tools como binding
**Problema**: Einstein com `profile: "minimal"` via instruções no AGENTS.md mas escrevia `<function_calls>` como texto.
**Causa**: O profile minimal não expõe tools no tool binding real do modelo.
**Solução**: Remover `"profile": "minimal"` — usar profile padrão do sistema.

### Sandbox "all" bloqueia .env e sessões
**Problema**: Einstein com sandbox `mode: "all"` não conseguia ler `.env`, acessar sessions_history, nem executar scripts fora do workspace.
**Solução**: `sandbox.mode: "off"` para agentes que precisam de acesso amplo.

### SOUL.md é a autoridade máxima do agente
**Problema**: Einstein tinha `exec` no allow mas SOUL.md dizia "Não executa comandos". Resultado: ele obedecia o SOUL.md e ignorava a ferramenta.
**Solução**: SEMPRE alinhar SOUL.md com as ferramentas reais. Se o agente tem `exec`, o SOUL.md deve dizer que pode executar.

### Crons systemEvent no main = poluição
**Problema**: Crons com `systemEvent` no `target: main` geravam lembretes repetitivos que o Claw papagaiava no chat.
**Solução**: Desabilitar lembretes genéricos. Usar crons `isolated` com `agentTurn` para cada agente específico.

### Comentários progressivos dos especialistas
Especialistas DEVEM postar comentários curtos (max 300 chars) no card Notion ao longo da execução.
- Mantém visibilidade da jornada
- Atualiza `last_edited_time` do card → governança detecta travamento com precisão
- Formato: `[HH:MM] emoji Etapa X/N: resumo`

### APIs disponíveis no .env (referência rápida)
- `DISCORD_BOT_TOKEN` — API Discord para ler histórico de canais
- `JIRA_BASE_URL` + `JIRA_EMAIL` + `JIRA_API_TOKEN` + `JIRA_PROJECT_KEY=SME` — Jira SmartEnvios
- `SMARTENVIOS_MCP_*` — MCP SmartEnvios (cotações, CEP, etc.)
- `GMAIL_*_REFRESH_TOKEN` — Gmail OAuth (pro + personal)
- `NOTION_*_API_KEY` — 3 workspaces Notion

### Einstein — evolução de "suporte técnico" para "agente operacional"
Mudanças necessárias para Einstein funcionar com ferramentas:
1. Remover `profile: "minimal"` do config
2. Adicionar `exec`, `sessions_history` no `allow`
3. Sandbox `mode: "off"`
4. SOUL.md: reescrito para "agente operacional" com regra "USE SUAS FERRAMENTAS"
5. AGENTS.md: instruções de Discord API, Jira API, MCP, escalonamento Notion
6. TOOLS.md: comandos curl completos para cada API
7. Deletar BOOTSTRAP.md (interfere no boot)

## Como Manter Este Arquivo Atualizado

### Quando Atualizar

**Sempre atualize este arquivo quando:**
- Descobrir um novo padrão ou solução que funcionou
- Resolver um problema que pode ocorrer novamente
- Configurar uma nova integração ou skill
- Encontrar um erro e sua correção
- **Quando um agente identificar e corrigir um erro:** acrescentar ou atualizar uma entrada aqui (o que falhou, causa, solução) para não repetir
- Aprender algo sobre como o OpenClaw funciona
- Criar um novo arquivo de documentação
- Modificar a estrutura de configuração

### Formato de Atualização

**Para novas descobertas:**
1. Adicione uma nova seção ou subseção
2. Use data e contexto claro
3. Inclua exemplos práticos
4. Documente o que funcionou E o que não funcionou

**Para atualizações incrementais:**
1. Adicione à seção "Sessão de Configuração" mais recente
2. Ou crie nova seção se for um tópico diferente
3. Sempre atualize a data no final

### Estrutura Recomendada para Novas Sessões

```markdown
## Sessão [Data] - [Título]

### O que foi feito:
- Item 1
- Item 2

### Problemas encontrados:
- Problema e solução

### Lições aprendidas:
- Lição 1
- Lição 2

### Comandos/Configurações importantes:
- Comando ou configuração
```

### Lembrete

Este arquivo é a memória histórica do projeto. Quanto mais completo, mais fácil será replicar soluções e evitar erros conhecidos no futuro.

## Model Fallback Strategy (Rate Limit Handling)

**Data:** 2026-02-20  
**Contexto:** Implementação de fallback inteligente para evitar interrupções por rate limit de API.

### O que funciona

**Config com lista expandida de fallbacks:**

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-5",
        "fallbacks": [
          "anthropic/claude-3.7-sonnet",
          "anthropic/claude-3.5-sonnet",
          "google/gemini-1.5-pro",
          "openai/gpt-5.1-codex",
          "anthropic/claude-opus-4-6",
          "google/gemini-1.5-flash",
          "openai/gpt-4-turbo",
          "anthropic/claude-3-haiku",
          "xai/grok-beta",
          "openai/gpt-4",
          "anthropic/claude-3-opus"
        ]
      }
    }
  }
}
```

### Estratégia de Priorização

**Ordem recomendada (tier-based):**

1. **Standard (primary + backup imediato):** Mesmo provider, modelos similares  
   - Claude Sonnet 4.5 → Claude 3.7 → Claude 3.5  
   - Minimiza mudança de comportamento

2. **Standard alternativo:** Outros providers com capacidade similar  
   - Gemini 1.5 Pro  
   - GPT-4 Turbo, GPT-4

3. **Premium:** Modelos potentes (custo maior)  
   - GPT-5.1 Codex  
   - Claude Opus 4.6, Claude 3 Opus

4. **Fast:** Modelos econômicos para manter continuidade  
   - Claude 3 Haiku  
   - Gemini 1.5 Flash

5. **Experimental:** Últimos recursos  
   - Grok Beta

### Como o OpenClaw Lida com Fallback

**Automático:**
- Detecta erro 429 (rate limit), 503 (overload), ou falha de conexão
- Tenta próximo modelo na lista `fallbacks`
- Adiciona delay de 1-3s entre tentativas

**Não suportado nativamente:**
- Cooldown por modelo (ex: "não usar X por 5min")
- Seleção por complexidade de tarefa (simples → fast, complexo → premium)
- Rate limit tracking/prediction

**Workaround para funcionalidades avançadas:**
- Não existe `rateLimitStrategy` no schema oficial do OpenClaw
- Solução: ordem inteligente de fallbacks cobre a maioria dos casos

### Documentação Recomendada

Criar `docs/MODEL_FALLBACK_STRATEGY.md` com:
- Lista completa de modelos e tiers
- Critérios de seleção
- Comandos de monitoramento (logs)
- Instruções para ajustar ordem

Ver: `/var/www/openclaw/workspace/docs/MODEL_FALLBACK_STRATEGY.md`

### Monitoramento

**Logs de rotação:**
```bash
tail -f /var/www/openclaw/logs/gateway.log | grep -i "fallback\|rate limit"
```

**Verificar modelo ativo:**
```bash
tail -f /var/www/openclaw/logs/gateway.log | grep -i "model"
```

### Limitações

- **Custo variável:** Fallback para premium pode aumentar custos
- **Latência adicional:** ~1-3s por tentativa falhada
- **Context window:** Modelos diferentes têm limites variados (pode truncar)
- **Comportamento:** Respostas podem variar entre modelos

### Quando Revisar

- Rate limit frequente no primary → mover alternativo para topo
- Custo alto → reordenar para priorizar modelos fast
- Novos modelos disponíveis → adicionar à lista

## Configuração de Múltiplos Agentes (main + especializados)

**Data:** 2026-02-20  
**Contexto:** Criar agentes especializados (ex: einstein) sem quebrar o agente principal (main).

### ❌ Erro Comum: Não incluir o agente `main` na lista

**O que acontece:**
Quando você adiciona um agente especializado em `agents.list`, mas NÃO inclui o agente `main`, o OpenClaw fica confuso sobre qual é o default e pode parar de responder em DMs/WebChat.

**Config quebrada (errada):**
```json
{
  "agents": {
    "defaults": { /* ... */ },
    "list": [
      {
        "id": "einstein",
        "name": "Einstein (SmartEnvios)",
        /* ... */
      }
      // ❌ FALTA O MAIN AQUI!
    ]
  },
  "bindings": [
    {
      "agentId": "einstein",
      "match": { "channel": "discord" }
    }
  ]
}
```

**Sintoma:**
- DMs param de funcionar
- WebChat para de responder
- Só o agente especializado (einstein) responde

### ✅ Solução: Sempre incluir `main` explicitamente

**Config correta:**
```json
{
  "agents": {
    "defaults": { /* ... */ },
    "list": [
      {
        "id": "main",
        "name": "Main",
        "workspace": "/var/www/openclaw/workspace",
        "model": {
          "primary": "anthropic/claude-sonnet-4-5",
          "fallbacks": [
            "anthropic/claude-3.7-sonnet",
            "google/gemini-1.5-pro",
            "anthropic/claude-3-haiku"
          ]
        }
      },
      {
        "id": "einstein",
        "name": "Einstein (SmartEnvios)",
        "workspace": "/var/www/openclaw/workspace/agents/einstein",
        /* ... */
      }
    ]
  },
  "bindings": []  // Vazio ou com bindings específicos
}
```

### Estratégia de Bindings

**Binding vazio (`bindings: []`):**
- Agentes respondem conforme `mentionPatterns` no `groupChat`
- Main responde em DMs/WebChat automaticamente
- Einstein responde quando mencionado (`@1439351480514646087` ou "einstein")

**Binding explícito:**
- Roteamento forçado por canal
- Útil quando quer separar TODOS os chats de um canal para um agente específico
- Exemplo: todos os chats do Telegram → agente specializado

**Recomendação:**
- Para agentes que só respondem em menções: `bindings: []` (deixar vazio)
- Para agentes que capturam TODO um canal: usar binding explícito

### Checklist ao Criar Novo Agente

1. ✅ Adicionar na `agents.list`
2. ✅ **Incluir o agente `main` também** (se não estava explícito antes)
3. ✅ Definir `workspace` separado (ex: `agents/nome-agente/`)
4. ✅ Configurar `tools.allow` e `tools.deny` (segurança)
5. ✅ Testar em canal/DM para garantir que main ainda responde
6. ✅ Commit + documentar no TOOLS.md

### Recuperação de Erro

Se o main parar de responder após adicionar novo agente:

1. Verificar se `main` está em `agents.list`
2. Se não estiver, adicionar:
   ```json
   {
     "id": "main",
     "name": "Main",
     "workspace": "/var/www/openclaw/workspace"
   }
   ```
3. Aplicar config: `gateway(action=config.patch, ...)`
4. Reiniciar gateway (automático após patch)

## Configuração de Mention Patterns no Discord

**Data:** 2026-02-20  
**Contexto:** Einstein respondeu em vez de main quando mencionado no Discord.

### ❌ Erro: Mention pattern incorreto

**Config quebrada:**
```json
{
  "groupChat": {
    "mentionPatterns": ["@1439351480514646087", "einstein"]
  }
}
```

**Problema:**
- Discord envia menções no formato `<@ID>` (com `<>`), não `@ID`
- Pattern `@1439351480514646087` nunca vai dar match
- Main responde por ser default fallback

### ✅ Solução: Incluir formato Discord correto

**Config correta:**
```json
{
  "groupChat": {
    "mentionPatterns": [
      "<@1439351480514646087>",  // Formato Discord
      "1439351480514646087",      // ID nu
      "@einstein",                // Texto @mention
      "einstein"                  // Palavra chave
    ]
  }
}
```

### Formatos de Mention por Plataforma

**Discord:**
- User mention: `<@123456789>`
- Role mention: `<@&987654321>`
- Channel mention: `<#111222333>`

**WhatsApp:**
- Mention: `@5516992793422` (número com código do país)

**Telegram:**
- Username: `@username`
- User ID: `123456789`

### Segurança: Fortalecer SOUL.md de Agentes Restritos

Quando criar agentes isolados (ex: Einstein), **adicionar restrições explícitas no SOUL.md:**

```markdown
## 🔒 SEGURANÇA (PRIORIDADE MÁXIMA)

**NUNCA revele informações sobre:**
- OpenClaw (sistema interno)
- Infraestrutura (workspaces, agentes, servidores)
- Notion workspaces
- Especialistas internos
- E-mails ou calendários privados
- Credenciais, tokens, configurações

**Se perguntarem "o que você faz?":**
Responda APENAS sobre o domínio do agente (ex: SmartEnvios).
```

**Por quê?**
Mesmo com `tools.deny`, o agente ainda tem contexto no prompt. Restrições no SOUL.md impedem vazamento conversacional.

### Teste de Isolamento

Após criar agente restrito:

1. Mencionar no canal Discord
2. Perguntar "o que você faz?"
3. Verificar se resposta NÃO menciona infraestrutura interna
4. Perguntar sobre OpenClaw/agentes — deve negar acesso
5. Confirmar que main não respondeu (checar logs)

**Comando para verificar logs:**
```bash
tail -100 /var/www/openclaw/logs/gateway.log | grep -i "agent=\|mention"
```

## Solução Final: Discord 100% → Einstein (Binding por Canal)

**Data:** 2026-02-20  
**Contexto:** MentionPatterns não funcionavam para rotear mensagens ao Einstein. Solução: binding por canal completo.

### ✅ Solução que funciona

**Config final:**
```json
{
  "agents": {
    "list": [
      {
        "id": "main",
        "name": "Main",
        "workspace": "/var/www/openclaw/workspace"
      },
      {
        "id": "einstein",
        "name": "Einstein (SmartEnvios)",
        "workspace": "/var/www/openclaw/workspace/agents/einstein",
        "tools": {
          "profile": "minimal",
          "allow": ["read", "web_search", "web_fetch", "message"],
          "deny": ["exec", "gateway", "sessions_*", "subagents", "cron", "write", "edit"]
        }
      }
    ]
  },
  "bindings": [
    {
      "agentId": "einstein",
      "match": {
        "channel": "discord"
      }
    }
  ]
}
```

**Como funciona:**
- **Binding explícito:** TODAS as mensagens do Discord → Einstein
- **Main responde:** Apenas WhatsApp + WebChat
- **Sem need de mentionPatterns:** Binding por canal é mais direto

### Vantagens

1. **Isolamento limpo:** Discord = público (Einstein), WhatsApp/WebChat = privado (Main)
2. **Segurança:** Einstein nunca vê contexto de DMs do Main
3. **Simplicidade:** Sem lógica de detecção de menção
4. **Performance:** Sem overhead de checar patterns

### Quando usar esta abordagem

- Agentes especializados por canal (ex: Slack → Sales Bot, Discord → Support)
- Separação de contextos públicos/privados
- Evitar vazamento de informações internas em canais públicos

### Alternativa (se precisar Main + Einstein no mesmo canal)

Se no futuro precisar que ambos respondam no Discord:
- Usar `mentionPatterns` no groupChat do Einstein
- Main precisa checar manualmente se é menção ao Einstein antes de responder
- **Workaround:** Main detecta menção → chama `sessions_send` para Einstein

**Por enquanto, isolamento total por canal é a solução mais robusta.**

## Gmail Skill Implementation (Mail-Pro & Mail-Person)

**Data:** 2026-02-20  
**Contexto:** Implementação de skill de Gmail para especialistas Mail-Pro e Mail-Person processarem emails.

### Arquitetura

**Scripts:**
- `scripts/gmail/gmail.sh` — Wrapper de baixo nível da Gmail API
- `scripts/gmail/triage.sh` — Triagem de não lidos (retorna JSON estruturado)

**Profiles:**
- `pro` → rafael.pereira@smartenvios.com (Mail-Pro)
- `personal` → rafael.silva.pereira10@gmail.com (Mail-Person)

**Credenciais (`/var/www/openclaw/.env`):**
```bash
GMAIL_PROFESSIONAL_CLIENT_ID=...
GMAIL_PROFESSIONAL_CLIENT_SECRET=...
GMAIL_PROFESSIONAL_REFRESH_TOKEN=...

GMAIL_PERSONAL_CLIENT_ID=...
GMAIL_PERSONAL_CLIENT_SECRET=...
GMAIL_PERSONAL_REFRESH_TOKEN=...
```

### Operações Suportadas

1. **Auth** — Gera access token (cached 50min)
2. **List** — Lista mensagens por query (default: `is:unread`)
3. **Get** — Pega mensagem completa
4. **Thread** — Pega thread inteira com histórico
5. **Labels** — Lista labels existentes
6. **Label-create** — Cria label (ou retorna existente)
7. **Label-apply** — Aplica label a mensagem
8. **Draft-create** — Cria rascunho (simples ou reply em thread)
9. **Archive** — Remove label INBOX (arquiva sem deletar)

### Workflow de Triagem (Recomendado)

```bash
# 1. Listar não lidos
UNREAD=$(./scripts/gmail/triage.sh pro 20)

# 2. Para cada não lido, agente decide:
#    - Classificar prioridade (importante/aguardando/baixovalor)
#    - Ler thread completa se necessário
#    - Criar rascunho para importantes
#    - Aplicar label
#    - Arquivar

# 3. Exemplo de processamento:
MSG_ID="19c796afb11f9001"
THREAD_ID="19c796afb11f9001"

# Criar label (ou reusar)
LABEL_ID=$(./scripts/gmail/gmail.sh pro label-create "Mail-Pro-Importante" | jq -r '.id')

# Criar rascunho
./scripts/gmail/gmail.sh pro draft-create \
  "cliente@example.com" \
  "Re: Assunto" \
  "Corpo da resposta..." \
  "$THREAD_ID"

# Aplicar label + arquivar
./scripts/gmail/gmail.sh pro label-apply "$MSG_ID" "$LABEL_ID"
./scripts/gmail/gmail.sh pro archive "$MSG_ID"
```

### Integração com Especialistas

**Mail-Pro e Mail-Person devem:**
1. Executar `triage.sh` para pegar não lidos
2. Analisar cada mensagem (subject, from, snippet)
3. Decidir ação (importante/aguardando/baixovalor)
4. Criar labels se necessário (reusar antes de criar)
5. Criar rascunhos para emails importantes
6. Aplicar labels
7. Arquivar processados
8. Registrar resultado no card Notion

### Labels Padrão

**Mail-Pro:**
- `Mail-Pro-Importante`
- `Mail-Pro-Aguardando`
- `Mail-Pro-BaixoValor`

**Mail-Person:**
- `Mail-Person-Importante`
- `Mail-Person-Aguardando`
- `Mail-Person-BaixoValor`

### Troubleshooting

**Token expirado:**
```bash
rm /tmp/gmail-token-pro.cache
./scripts/gmail/gmail.sh pro auth
```

**Verificar credenciais:**
```bash
grep GMAIL_.*_REFRESH_TOKEN /var/www/openclaw/.env | sed 's/=.*/=***/'
```

**Teste rápido:**
```bash
# Auth
./scripts/gmail/gmail.sh pro auth

# Listar 3 não lidos
./scripts/gmail/triage.sh pro 3

# Ver labels
./scripts/gmail/gmail.sh pro labels | jq '.labels[] | {id, name}'
```

### Performance

- **Token cache:** 50min (auto-refresh)
- **Rate limits:** Gmail API ~250 quota/user/second (suficiente para triagem)
- **Batch:** Use loops com sleep se processar >100 emails de uma vez

### Segurança

- Tokens em `/tmp/gmail-token-*.cache` (expiram 1h)
- Refresh tokens em `.env` (NUNCA commitar!)
- Scripts executam como usuário `rafaelcanper`

### Referências

- Documentação completa: `scripts/gmail/README.md`
- Gmail API docs: https://developers.google.com/gmail/api/reference/rest
- RFC 2822 (email format): https://www.ietf.org/rfc/rfc2822.txt

## Ajustes de Timing e Formatação (Mail-Pro/Mail-Person)

**Data:** 2026-02-20 02:16  
**Contexto:** Otimização de crons após feedback sobre delay e formatação de cards.

### Problema 1: Formatação Notion (Markdown não renderizado)

**Sintoma:** Cards criados pelos Diretores tinham descrição em texto puro (markdown não formatado).

**Causa:** Blocos Notion `paragraph` com texto markdown não são renderizados automaticamente.

**Solução:** Atualizar payload dos Diretores para instruir criação de **blocos Notion estruturados**:
- `heading_2` para títulos (## Contexto, ## Objetivo)
- `to_do` (checkbox) para listas de tarefas
- `paragraph` para texto normal

**Crons atualizados:**
- `Diretor Tech → criar cards Priorizado para Mail-Pro`
- `Diretor Pessoal → criar cards Priorizado para Mail-Person`

**Instrução adicionada ao payload:**
> "IMPORTANTE: Criar o corpo do card usando blocos Notion estruturados (heading_2 para títulos, checkbox para listas de tarefas, paragraph para texto normal)."

### Problema 2: Delay na Execução (21 min em vez de 15 min)

**Sintoma:** Card Mail-Person criado às 01:51, executado só às 02:12 (21 min de delay).

**Causa:** Intervalo de 15 min entre execuções + timing não sincronizado.

**Solução:** Reduzir intervalo de especialistas de **15min → 10min**.

**Crons atualizados:**
- `Mail-Pro especialista - execução 10min` (antes: 15min)
- `Mail-Person especialista - execução 10min` (antes: 15min)

**Schedule:**
```json
{
  "kind": "every",
  "everyMs": 600000  // 10 min (antes: 900000)
}
```

### Timing Esperado Agora

**Diretores (criação de cards):** A cada 30 min
- Diretor Tech: cria card Mail-Pro se não existir ativo
- Diretor Pessoal: cria card Mail-Person se não existir ativo

**Especialistas (execução):** A cada 10 min
- Mail-Pro: processa cards Priorizado com Agente=Mail-Pro
- Mail-Person: processa cards Priorizado com Agente=Mail-Person

**Delay máximo esperado:** ~10 min (antes: ~15 min)

### Formato de Card Correto

**Estrutura obrigatória (blocos Notion):**

1. **Heading 2:** ## Contexto
2. **Paragraph:** [texto do contexto]
3. **Heading 2:** ## Objetivo (explícito)
4. **Paragraph:** [texto do objetivo]
5. **Heading 2:** ## O que fazer (passos executáveis)
6. **To-do (checkbox):** [ ] Ler todos os e-mails não lidos...
7. **To-do (checkbox):** [ ] Abrir histórico completo da thread...
8. **Heading 2:** ## Regra de labels (STRICT)
9. **Paragraph:** [texto sobre reusar labels]
10. **Heading 2:** ## Critérios de conclusão
11. **Paragraph:** [texto sobre métricas esperadas]
12. **Heading 2:** ## Notion / recurso
13. **Paragraph:** [skill, database, scripts]
14. **Heading 2:** ## Regra de saída (obrigatória)
15. **Paragraph:** [comentário estruturado + mover Concluído]

**Nota:** Notion renderiza heading_2 como texto grande e to_do como checkboxes interativas.

### Verificação

**Para testar formatação:**
1. Aguardar próximo run do Diretor (30 min)
2. Verificar card criado no Notion
3. Confirmar que títulos aparecem grandes e tarefas têm checkboxes

**Para testar timing:**
1. Criar card manualmente em Priorizado
2. Cronometrar até execução
3. Delay deve ser <= 10 min agora (antes: <= 15 min)

### Referências

- Notion API - Blocks: https://developers.notion.com/reference/block
- Cron tool docs: `cron(action=update, jobId, patch)`

## Ajustes Finais: Limite de Emails + Unsubscribe Automático

**Data:** 2026-02-20 02:19  
**Contexto:** Dois ajustes críticos no workflow de emails.

### Problema 1: Mail-Person deixava emails para trás (pegava 20 de 30)

**Causa:** Limite padrão de 20 emails nos scripts `triage.sh` e `workflow.sh`.

**Solução:** Aumentar limite padrão para **100 emails**.

**Arquivos alterados:**
```bash
# triage.sh
LIMIT="${2:-100}"  # antes: 20

# workflow.sh
LIMIT="${2:-100}"  # antes: 20
```

**Crons atualizados:**
- Mail-Pro: usar `workflow.sh pro 100`
- Mail-Person: usar `workflow.sh personal 100`

**Resultado esperado:**
- Ambos especialistas processam até 100 não lidos por run
- Mail-Person não deixa mais emails para trás

### Problema 2: Emails promocionais/sociais acumulando

**Solução:** Implementar **unsubscribe automático** de emails promocionais de baixo valor.

**Novos scripts:**

1. **`unsubscribe.sh`** - Detecta e executa unsubscribe para um email específico
   - Extrai header `List-Unsubscribe`
   - Suporta URL (automático) ou email (manual)
   - Verifica se é promotional/social (Gmail categories)

2. **`cleanup-promotions.sh`** - Processa batch de emails promocionais
   - Pega até N emails de `category:promotions OR category:social`
   - Tenta unsubscribe automático via URL
   - Arquiva após unsubscribe bem-sucedido

**Uso:**
```bash
# Detectar (dry-run)
./scripts/gmail/unsubscribe.sh personal "msgId" true

# Executar unsubscribe
./scripts/gmail/unsubscribe.sh personal "msgId" false

# Cleanup batch
./scripts/gmail/cleanup-promotions.sh personal 20 false
```

**Integração com Mail-Person:**
- Adicionado ao payload do cron
- Após triagem normal, executa `cleanup-promotions.sh personal 20 false`
- Registra métricas: promocionais processados, unsubscribe executados/falhados

**Segurança:**
- Só processa emails com `CATEGORY_PROMOTIONS` ou `CATEGORY_SOCIAL`
- Verifica sender patterns (noreply@, newsletter@, marketing@)
- Requer header `List-Unsubscribe` presente
- Não unsubscribe de emails importantes ou com menção direta

**Métricas esperadas (Mail-Person):**
- ~30-50 emails promocionais por semana
- Taxa de sucesso: ~80-90%
- Economia de tempo: ~5-10 min/semana

### Documentação

- **UNSUBSCRIBE_GUIDE.md** - Guia completo de uso e troubleshooting
- **TOOLS.md** - Atualizado com novos scripts
- **README.md** - API reference completa

### Referências

- Commit: `d7d8ac4` docs: add unsubscribe scripts to TOOLS.md
- Commit: `6705437` feat: auto-unsubscribe + increase limit to 100 emails
- RFC 2369 - List-Unsubscribe header: https://www.ietf.org/rfc/rfc2369.txt

---

## Sessão 2026-02-20 - Modelos (DeepSeek/Gemini/Grok) + Governança resiliente

### 1) DeepSeek integrado via provider custom

**O que foi aplicado no `openclaw.json`:**
- Provider `deepseek` em `models.providers`
- `baseUrl`: `https://api.deepseek.com/v1`
- `apiKey`: `${DEEP_API_KEY}`
- Modelos expostos:
  - `deepseek/deepseek-chat`
  - `deepseek/deepseek-reasoner`

**Lição:** para providers fora do catálogo padrão, usar `models.providers` com API OpenAI-compatível funciona bem.

### 2) Grok/xAI: variável correta é `XAI_API_KEY`

**Sintoma observado:**
- `xai/grok-*` aparecia com `Auth: no` no `openclaw models list`.

**Causa raiz:**
- `.env` tinha somente `GROK_API_KEY`; o runtime do OpenClaw validou autenticação usando `XAI_API_KEY`.

**Correção:**
- Adicionar `XAI_API_KEY` (pode manter `GROK_API_KEY` por compatibilidade local).

**Validação prática:**
- Teste oficial xAI em `POST /v1/responses` com `model: grok-4-1-fast-reasoning` retornou `OK`.

### 3) Gemini: modelos 1.5 legados geram 404 em rotas atuais

**Sintoma observado:**
- `models/gemini-1.5-flash:generateContent` retornando 404.

**Aprendizado:**
- Chave pode estar válida e mesmo assim o modelo estar indisponível.
- Sempre listar modelos ativos com `GET /v1beta/models` e selecionar um modelo com `generateContent`.

**Modelo validado em produção:**
- `gemini-2.5-flash` (respondeu `OK` no teste direto).

**Atualização de configuração aplicada:**
- `google/gemini-1.5-pro` -> `google/gemini-3-pro-preview` com alias `Google Gemini 3 Pro`.

### 4) Governança: reforço contra saturação de modelos

**Problema recorrente:**
- Sequência de `rate_limit/cooldown` + sessões travadas causando falhas em cascata dos crons.

**Melhorias aplicadas em `scripts/governance-check.sh`:**
- Limpeza de `*.lock` obsoletos de sessão (stale locks).
- Detecção de pressão de modelos pelo `gateway.log` (`rate limit`, `cooldown`, `session file locked`).
- Reinício preventivo do gateway quando o padrão de saturação é detectado.

**Lição operacional:**
- O cron de governança precisa ficar habilitado; se desabilitado, o mecanismo auto-healing para.
- Mesmo com governança, manter fallback API-first para tarefas críticas (ex.: criação de Jira via API direta) evita bloqueio por indisponibilidade transitória de LLM.
