# FLUXO_AGENTES.md — Presidente, Diretores e Especialistas

Este documento define o fluxo operacional no Notion para cards com:
- **Status:** `Aguardando` → `Priorizado` → `Em andamento` → `Concluído`
- **Tipo:** `OpenClaw`
- **Propriedade chave:** `Agente`

### Regra de escopo e deduplicação por agente — OBRIGATÓRIO

Cada agente opera em **dois status**: capta do status de entrada e checa duplicidade no status de saída.

| Agente | Capta de | Checa duplicidade em | Move para |
|---|---|---|---|
| **Presidente** | — (cria) | `Aguardando` | `Aguardando` |
| **Diretor** | `Aguardando` | `Priorizado` | `Priorizado` |
| **Especialista** | `Priorizado` | `Em andamento` | `Em andamento` → `Concluído` |

**Regra de duplicidade — chave dupla: Assunto + Agente**

- Um card é considerado duplicado se já existir outro com o **mesmo título** e o **mesmo Agente** no status de saída do agente.
- Se existir 1 card em `Aguardando` e 0 em `Priorizado` (mesmo assunto+agente), o diretor **deve priorizar**.
- Se existir 1 em `Aguardando` e 1 em `Priorizado` (mesmo assunto+agente), o diretor **espera o próximo ciclo** para não duplicar.
- Mesma lógica para especialistas: se já existir 1 em `Em andamento` (mesmo assunto+agente), esperar o próximo ciclo.

**O que cada agente NÃO consulta:**

- Presidente: não consulta `Priorizado`, `Em andamento` nem `Concluído`.
- Diretor: não consulta `Em andamento` nem `Concluído`.
- Especialista: não consulta `Aguardando` nem `Concluído`.

## 1) Papéis e responsabilidades

## Presidente
- Recebe demandas por Discord, WhatsApp e Web Chat.
- Entende o pedido, cria uma descrição breve e abre card em **Aguardando**.
- Define a propriedade **Agente** para o diretor responsável.
- Define **Tipo = OpenClaw**.
- **Solicitante obrigatório:** ao triar para diretores, deve tentar definir o campo **Solicitante** com a pessoa correta (prioridade para **Rafael Pereira** quando aplicável). Se houver ambiguidade de utilizador, pedir confirmação antes de criar/encaminhar.
- **Revisão contínua:** deve ler cards `Tipo OpenClaw` em `Concluído`, comparar com o esperado, juntar feedback do utilizador e usar isso para melhorar instruções/templates/KNOWLEDGE/fluxos.

### Função padrão (Notion) — Presidente/Main

Quando o pedido for para Notion, o Presidente deve:

1. Criar card com propriedades obrigatórias:
   - **Status:** `Aguardando`
   - **Tipo:** `OpenClaw`
   - **Solicitante:** `Rafael Pereira`
   - **Agente:** diretor responsável por conduzir com o especialista adequado
2. Aplicar inteligência de roteamento:
   - Identificar o tipo de tarefa e o especialista ideal.
   - Atribuir o card ao diretor correto para esse especialista.
3. Escrever descrição funcional no card para orientar o diretor.

### Regra de profundidade da descrição (Presidente) — CRÍTICO

O Presidente deve escrever descrição **funcional e clara**, mas **sem detalhamento técnico**.
Os diretores agora operam com cron **generalista** — captam qualquer card `Aguardando` do domínio deles. Por isso, a descrição funcional do Presidente é a **única fonte de contexto** para o diretor entender, rotear e detalhar tecnicamente.

**O que o Presidente DEVE incluir:**
- Qual é a demanda (em linguagem funcional, sem termos técnicos)
- Qual domínio / área (ex: e-mail profissional SmartEnvios, e-mail pessoal, backend, negócios)
- Objetivo em 1-2 frases (ex: "triar e-mails não lidos e criar rascunhos para os importantes")
- Critérios de conclusão funcionais (ex: "todos os não lidos classificados e arquivados")
- Contexto relevante (ex: "foco em menções diretas ao Rafael", "caixa: rafael.pereira@smartenvios.com")

**O que o Presidente NÃO deve incluir:**
- Passo técnico de implementação, arquitetura, script/comando, instrução de código
- Nome de ferramentas internas ou paths de scripts

**Quem detalha tecnicamente é o Diretor** ao captar o card e mover para `Priorizado`.

**Exemplo de descrição funcional (Presidente):**

```
Demanda: triagem periódica da caixa de e-mail profissional.
Domínio: e-mail profissional SmartEnvios (rafael.pereira@smartenvios.com).
Objetivo: ler e-mails não lidos, classificar por relevância, criar rascunhos
para os importantes e arquivar os processados.
Critérios de conclusão: todos os não lidos triados, classificados e arquivados.
Contexto: priorizar e-mails com menção direta ao Rafael.
```

## Diretores (3)

### Mapeamento diretor → Notion/skill
- **Diretor Tech SmartEnvios** → `notion` (`NOTION_SMARTENVIOS_API_KEY`)
- **Diretor Pessoal** → `notion-personal` (`NOTION_PERSONAL_API_KEY`)
- **Diretor Negócios** → `notion-canper` (`NOTION_CANPER_API_KEY`)

Cada diretor delega no seu próprio Notion; por padrão, especialistas usam o mesmo Notion do diretor.

### Função padrão (Notion) — Diretor

Quando o pedido estiver no escopo do diretor, ele deve:

1. Criar ou captar e atualizar card com propriedades obrigatórias:
   - **Status:** `Priorizado`
   - **Tipo:** `OpenClaw`
   - **Solicitante:** `Rafael Pereira`
   - **Agente:** especialista responsável por executar o tipo de tarefa
2. Aplicar inteligência de roteamento:
   - Identificar o especialista adequado para execução.
   - Responsabilizar o especialista correto no campo **Agente**.
3. Escrever descrição técnica completa para o especialista.

### Função padrão (Notion) — Diretor de Negócios

Enquanto os especialistas dedicados de Negócios não existem, o Diretor de Negócios deve:

1. Captar demandas de negócio e normalizar o card para:
   - **Status:** `Priorizado`
   - **Tipo:** `OpenClaw`
   - **Solicitante:** `Rafael Pereira`
   - **Agente:** especialista de negócios alvo (quando existir) ou `Tech` para execução técnica temporária
2. Escrever descrição técnica/funcional acionável para execução.
3. Registrar no card qual especialista de negócios será o responsável definitivo assim que for criado.

Quando os especialistas de Negócios forem criados:

- Substituir o `Agente` temporário pelo especialista correto.
- Manter o mesmo padrão de lifecycle: `Priorizado` -> `Em andamento` -> `Concluído`.

### Pontuais (ad hoc)
- Cron sugerido: **a cada 1 hora** (acionável manualmente).
- Captam cards em **Aguardando** que exigem análise/planejamento.
- Devem:
  1. Entender o pedido.
  2. Criar plano detalhado na descrição.
  3. Mover para **Priorizado**.
  4. Trocar **Agente** para o especialista adequado.
  5. Garantir **Tipo = OpenClaw**.

### Rotinas
- Cron sugerido: **a cada 30 minutos**.
- Aciona o Presidente para abrir/organizar rotinas em **Priorizado**, com **Agente** já definido para o especialista e descrição detalhada.

## Especialistas
- Cron sugerido: **a cada 15 minutos**.
- Captam cards em **Priorizado** cujo **Agente** seja eles.
- Fluxo:
  1. Mover para **Em andamento**.
  2. Ler a descrição do card (o que fazer, critérios de conclusão, Notion/recurso).
  3. Executar exatamente conforme descrição.
  4. Registrar resultado no card (descrição/comentários).
  5. Enviar status report no Discord e WhatsApp (quando aplicável).
  6. Mover para **Concluído**.

### Função padrão (Notion) — Especialista

Ao captar o card:

1. Atualizar **Status** para `Em andamento`.
2. **Comentário de início:** postar comentário no card (max 300 chars) indicando que captou e o que vai fazer.
3. Executar a atividade conforme descrição do card.
4. **Comentários progressivos durante execução:** a cada etapa relevante, postar comentário curto no card (max 300 chars) mostrando progresso, etapa atual e próximo passo. Isso garante visibilidade da jornada mesmo se o processo travar.
5. **Comentário de conclusão:** postar comentário final estruturado com resultado completo.
6. Atualizar **Status** para `Concluído`.

### Regra de comentários progressivos — OBRIGATÓRIO para especialistas

Especialistas DEVEM postar comentários no card do Notion ao longo da execução, não apenas no final. Máximo **300 caracteres** por comentário.

**Quando comentar:**
- Ao captar o card (início)
- Ao concluir cada etapa significativa
- Se encontrar erro ou bloqueio
- Ao concluir (resultado final)

**Formato sugerido:**
```
[HH:MM] 🟢 Início: captei card, lendo descrição. Próximo: verificar credenciais Gmail.
[HH:MM] 📧 Etapa 1/4: 47 não lidos encontrados. Triando por relevância...
[HH:MM] 🏷️ Etapa 2/4: 12 importantes, 8 baixo valor, 27 auto-reply. Aplicando labels...
[HH:MM] ✍️ Etapa 3/4: 3 rascunhos criados para urgentes. Arquivando processados...
[HH:MM] ✅ Concluído: 47 triados, 3 rascunhos, 44 arquivados. Movendo para Concluído.
```

**Por que isso é crítico:**
- Se o especialista travar, sabemos exatamente em que etapa parou.
- O Presidente e diretores podem acompanhar execuções em tempo real.
- A governança usa o `last_edited_time` do card para detectar travamento — comentários progressivos mantêm esse timestamp atualizado.

## Especialistas nomeados

Cada especialista capta apenas cards em **Priorizado** onde a propriedade **Agente** está no **seu nome**.

### Engenheiro SmartEnvios
- **Agente:** propriedade do card = **Engenheiro SmartEnvios**
- **Diretor:** Tech
- **Escopo:** bugs, features, melhorias em todos os repos SmartEnvios (`/var/www/ms.*`, `/var/www/mcp`, `/var/www/lgc.core`, etc.)
- **GitHub:** https://github.com/SmartEnvios
- **Acesso:** fullstack, git, exec, todos os repos em /var/www/

### Engenheiro de Prompt
- **Agente:** propriedade do card = **Engenheiro de Prompt**
- **Diretor:** Pessoal
- **Escopo:** manutenção e evolução da estrutura OpenClaw — agentes, prompts, documentação, KNOWLEDGE, SETUP_COMPLETO, versionamento
- **GitHub:** https://github.com/Rafael-Candido (repo `openclaw`)
- **Parceiros:** Otimizador e Governança criam cards para ele evoluir a estrutura
- **Acesso:** workspace OpenClaw completo, git, exec

### Mail-Pro e Mail-Person

### Mail-Pro
- **Agente:** propriedade do card = **Mail-Pro**.
- **Rotina:** (1) Captar cards em **Priorizado** onde **Agente** = **Mail-Pro**. (2) Ler a descrição do card (contexto, o que fazer, critérios de conclusão, Notion/recursos). (3) Mover para **Em andamento**. (4) Executar exatamente conforme a descrição. (5) Registar o resultado na descrição do card. (6) Enviar status report no Discord e WhatsApp. (7) Mover para **Concluído**.
- **Uso:** tarefas de e-mail **profissional** (SmartEnvios). Quando a tarefa envolver Gmail, usar credenciais/skill de e-mail profissional (mail-pro). Usa o Notion indicado na descrição do card (por padrão o mesmo do diretor que delegou).

### Mail-Person
- **Agente:** propriedade do card = **Mail-Person**.
- **Rotina:** (1) Captar cards em **Priorizado** onde **Agente** = **Mail-Person**. (2) Ler a descrição do card (contexto, o que fazer, critérios de conclusão, Notion/recursos). (3) Mover para **Em andamento**. (4) Executar exatamente conforme a descrição. (5) Registar o resultado na descrição do card. (6) Enviar status report no Discord e WhatsApp. (7) Mover para **Concluído**.
- **Uso:** tarefas de e-mail **pessoal**. Quando a tarefa envolver Gmail, usar credenciais/skill de e-mail pessoal (mail-person). Usa o Notion indicado na descrição do card (por padrão o mesmo do diretor que delegou).

Os diretores devem nomear **Agente** = **Mail-Pro** ou **Mail-Person** conforme o especialista adequado à tarefa (e-mail profissional/SmartEnvios → Mail-Pro; e-mail pessoal → Mail-Person).

## Especialista Dúvidas SmartEnvios (único)
- Canal: WhatsApp e Discord.
- **Gatilho obrigatório:** `Dúvida: {{texto}}`.
- Fora desse formato, não deve assumir que a mensagem é para ele.
- Ao receber a dúvida:
  - Consultar bases, MCP, documentos, APIs e sites relevantes.
  - Responder objetivamente.
  - Registrar aprendizados para evolução contínua (KNOWLEDGE/base própria).

### Regra de encaminhamento
- Rafael Pereira pode interagir normalmente.
- Para outros utilizadores, se o Presidente identificar intenção de tirar dúvida sem prefixo, deve orientar: **use `Dúvida: {{texto}}`**.

## 2) Requisito central: descrição detalhada do diretor para o especialista

A descrição do card deve ser suficiente para execução sem ambiguidade.

Obrigatório incluir:
- **Contexto:** origem da demanda e objetivo em uma frase.
- **O que fazer:** passos concretos e ordenados.
- **Critérios de conclusão:** definição clara de “feito”.
- **Notion/recursos:** skill (`notion`, `notion-personal`, `notion-canper`) + IDs/links necessários.
- **Especialista nomeado:** propriedade **Agente** correta.
- **Solicitante definido:** preencher o campo **Solicitante** (people), priorizando **Rafael Pereira** quando for o demandante.

## 2.1) Padrão reutilizável de propriedades (sem retrabalho)

Ao criar cards de rotina/melhoria, usar padrão base:

- **Status:** `Aguardando`
- **Tipo:** `OpenClaw`
- **Solicitante:** `Rafael Pereira`
- **Agente:** conforme responsável inicial (`Tech`, `Mail-Pro`, `Mail-Person`, etc.)

Template oficial: `templates/notion-card-openclaw.md`

Assim, o diretor só precisa complementar contexto/escopo e promover para `Priorizado`.

## 2.2) Regra API-first

- Todo acesso operacional deve ser via **API/MCP**.
- Zendesk também deve ser consumido via MCP (API).
- Exceção permitida: painel da base de conhecimento Zendesk para consulta visual quando necessário.

## 2.3) Esteira Einstein -> Diretor Tech -> Engenheiro Backend

Quando Einstein não conseguir responder uma dúvida SmartEnvios por limitação técnica:

1. Criar card em `Aguardando` com:
   - **Tipo:** `OpenClaw`
   - **Solicitante:** `Rafael Pereira`
   - **Agente:** `Tech`
2. Diretor Tech detalha solução/plano técnico e muda para:
   - **Status:** `Priorizado`
   - **Agente:** `Engenheiro Backend`
3. Engenheiro Backend executa melhoria no repositório MCP/API, documenta evidências e conclui.

## Template de descrição (diretor)

```md
## Contexto
[Origem do pedido e objetivo em uma frase.]

## O que fazer (passos)
1. ...
2. ...
3. ...

## Critérios de conclusão
- ...

## Notion / recurso
- Skill: notion | notion-personal | notion-canper
- [IDs ou links]

## Checklist obrigatório (strict)
- [ ] Status inicial em Priorizado
- [ ] Agente correto (Mail-Pro ou Mail-Person)
- [ ] Objetivo e escopo explícitos
- [ ] Passos executáveis sem ambiguidade
- [ ] Regra de labels (reusar antes de criar)
- [ ] Regra de saída (comunicar no Discord/WhatsApp + mover para Concluído)
```

## Template de comentário de conclusão (especialista)

```md
🚀 UPGRADE: [Título da entrega] ([AAAA-MM-DD HH:mm GMT-3])

Novo sistema de análise automática:

✅ [Melhoria 1]
✅ [Melhoria 2]
✅ [Melhoria 3]

📊 Capacidades:
- [Capacidade 1]
- [Capacidade 2]
- [Capacidade 3]

🎯 Ações por score:
- draft (50+): Criar rascunho contextualizado
- review (20-49): Revisar e decidir
- label (0-19): Apenas labelar
- ignore (<0): Auto-reply, arquivar

Documentação: [caminho(s) de documentação]
Commits: [hash1], [hash2]
```

## 3) Objetivo dos cards de e-mail (especialistas)

## Mail-Pro — caixa profissional
- Caixa: `rafael.pereira@smartenvios.com`
- Credenciais no `.env`: `GMAIL_PROFESSIONAL_CLIENT_ID` e `GMAIL_PROFESSIONAL_CLIENT_SECRET`
- Responsabilidades da rotina:
  1. Buscar e-mails não lidos.
  2. Ler com contexto completo da conversa (thread/histórico).
  3. Classificar prioridade e necessidade de ação.
  4. Criar rascunho contextualizado para e-mails importantes.
  5. Arquivar e-mails após processamento.
  6. Gerir labels com reuso inteligente (criar apenas se não existir):
     - `Mail-Pro-Aguardando`
     - `Mail-Pro-BaixoValor`
     - `Mail-Pro-Importante`
  7. Aprendizado contínuo com histórico de e-mails respondidos (responder vs arquivar vs ignorar).

## Mail-Person — caixa pessoal
- Caixa: `rafael.silva.pereira10@gmail.com`
- Credenciais no `.env`: `GMAIL_PERSONAL_CLIENT_ID` e `GMAIL_PERSONAL_CLIENT_SECRET`
- Responsabilidades da rotina:
  1. Buscar e-mails não lidos.
  2. Ler com contexto completo da conversa (thread/histórico).
  3. Classificar relevância pessoal.
  4. Criar rascunhos apenas para os importantes.
  5. Arquivar e-mails após processamento.
  6. Gerir labels com reuso inteligente (criar apenas se não existir):
     - `Mail-Person-Aguardando`
     - `Mail-Person-BaixoValor`
     - `Mail-Person-Importante`
  7. Aprendizado contínuo com histórico (responder vs arquivar vs ignorar).

## 4) Agente de Governança

Agente dedicado a garantir continuidade operacional e escalonamento correto de todos os crons e agentes.

- **Cron:** `Governança - health check 10min` (ID: `e5bb7978-cd99-4e8d-924a-b4d42a140c1e`)
- **Frequência:** a cada 10 minutos
- **Script:** `scripts/governance-check.sh`

### O que faz:

1. **Health check do gateway** — se DOWN, reinicia automaticamente.
2. **Detecta crons com erros consecutivos** (>= 2) — reseta sessão e re-habilita.
3. **Detecta crons travados** (running > 20min) — reseta sessão.
4. **Escalonamento automático de crons** — verifica se há colisão entre crons (gap < 2min entre execuções próximas). Se detectar sobreposição, ajusta os anchors automaticamente para garantir separação mínima de 2 minutos. Isso escala com novos agentes/crons sem intervenção manual.
5. **Verifica cards em `Em andamento` há muito tempo** (>20min sem atividade):
   - `Agente=Mail-Pro` → força execução do cron Mail-Pro
   - `Agente=Mail-Person` → força execução do cron Mail-Person
   - Outros agentes (>30min) → registra alerta para intervenção manual
6. **Registra incidentes** em `memory/YYYY-MM-DD.md`.

### Escalonamento automático — como funciona:

A governança calcula o `nextRun` de cada cron habilitado, ordena por proximidade, e verifica se há gap < 2min entre consecutivos. Se houver, desloca o anchor do cron mais tardio para manter separação mínima.

Isso significa que ao **adicionar novos agentes e crons**, a governança redistribui automaticamente — basta aumentar a periodicidade conforme o número de crons cresce para manter folga no rate limit.

**Regra prática de periodicidade:**
- Até 10 crons: intervalos de 10min (especialistas) e 30min (diretores) são suficientes
- 10-15 crons: considerar intervalos de 15min e 45min
- 15+ crons: considerar intervalos de 20min e 1h, ou reduzir `maxConcurrent` para 1

### O que NÃO faz:

- Não cria cards no Notion.
- Não move cards de status.
- Não interfere na lógica de negócio dos agentes.

## 5) Agente de Otimização e Performance

Trabalha em parceria com a Governança. A governança é o **bombeiro** (garante execução em tempo real); o otimizador é o **engenheiro** (elimina a causa raiz para que a governança tenha cada vez menos trabalho).

- **Cron:** `Otimizador - análise diária 7h` (ID: `9cb7163f-2e4e-48ed-9035-8148c77c5968`)
- **Frequência:** diário às 7h (America/Sao_Paulo)
- **Prompt:** `scripts/optimizer-prompt.txt`

### Fases de execução:

1. **O que deu trabalho para a governança?**
   - Lê logs, memory, cron list → identifica erros, sessões inchadas, crons lentos, cards travados, gateway restarts.
   - Para cada incidente, identifica a **causa raiz** (não apenas o sintoma).

2. **Eliminar a causa raiz:**
   - Sessão inchada → reset + análise se prompt pode ser enxuto
   - Cron lento → simplifica prompt
   - Gateway instável → aplica stagger entre crons
   - Card travado → melhora instruções do especialista
   - Instruções conflitantes → corrige documentos e prompts dos crons
   - Regras duplicadas → consolida em local único

3. **Documentar para não repetir:**
   - `KNOWLEDGE.md` → padrões definitivos com causa + fix
   - `memory/YYYY-MM-DD.md` → resumo do dia + tendência

### Objetivo de longo prazo:

Fluxos maduros devem gerar **zero incidentes** para a governança. O otimizador mede isso via tendência diária (incidentes hoje vs ontem).

### O que pode fazer:

- Resetar sessões, ajustar stagger, simplificar prompts, corrigir documentos.
- Toda alteração registrada em KNOWLEDGE.md.

### O que NÃO faz:

- Não desabilita crons.
- Não cria/move cards no Notion.
- Não altera credenciais.

## 6) Resiliência e autonomia

Todos (Presidente, Diretores, Especialistas, Governança, Otimizador) devem agir com resiliência:
- identificar falhas,
- corrigir rota sem pedir para mudanças não destrutivas,
- documentar lições para não repetir.

Referência operativa: **AGENTS.md → Autonomia – erros, correção e documentação**.
