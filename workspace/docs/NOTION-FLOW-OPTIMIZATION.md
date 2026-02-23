# Otimização do fluxo Notion e coordenação Presidente – Governança – Otimizador

**Objetivo:** Reduzir congestionamento no Notion, eliminar sobreposição de responsabilidades entre agentes/crons e fazer Presidente, Governança e Otimizador evoluírem o fluxo em conjunto.

**Princípio: resolver na raiz.** Não ficar criando fallbacks nem camadas de criticidade. Se o processo principal está a falhar (cron não cumpre o papel, e-mail a acumular, card travado), a resposta é **corrigir o processo principal** — cron, script, payload, frequência, gateway. Adicionar alternativas (wake forçado, cadeia em cooldown, mais um recovery) sobrecarrega o ecossistema e torna as execuções aleatórias. O alvo é: cada cron roda no seu horário e cumpre uma única responsabilidade; quando não cumpre, diagnostica-se e corrige-se a causa raiz (com ajuda do Otimizador / Eng. de Prompt), não se acrescenta outro desvio.

---

## 1. Onde o fluxo congestiona

| Ponto | Causa | Efeito |
|-------|--------|--------|
| **Aguardando** | Presidente (ou rotinas) criam mais cards do que os diretores promovem | Acúmulo em Aguardando |
| **Diretores** | 1 card por rodada (30 min) cada; 3 diretores = 3 cards/30 min no máximo | Gargalo se Aguardando > 6 |
| **Priorizado** | Especialistas processam 1 card por rodada (Mail-Pro/Mail-Person 1/h; Eng. Prompt 6/h; Eng. SmartEnvios 1/h) | Fila em Priorizado cresce se chegada > saída |
| **Criação dupla** | Presidente cria demanda de e-mail em Aguardando **e** Diretor Tech pode criar card Priorizado para Mail-Pro (rotina) | Risco de duplicidade ou confusão de responsável |
| **Governança** | Acorda crons e corrige roteamento, mas não reduz a **causa** do acúmulo | Efeito “apagar incêndio” sem evolução |

**Princípio:** A vazão do pipeline é limitada pelo elo mais lento. Ajustes devem aumentar vazão (mais cards por ciclo quando backlog alto) ou reduzir entrada (Presidente não criar quando Aguardando já estourou).

---

## 2. Matriz de responsabilidades (sem duplicidade)

Cada ação no Notion pertence a **um** agente/cron. Nenhum outro deve fazer a mesma coisa.

| Agente / Cron | Responsabilidade única | Não faz |
|----------------|-------------------------|---------|
| **Presidente** | Criar cards em **Aguardando** com descrição **funcional**; definir **Agente** = diretor responsável; rotinas de demanda (e-mail) só quando backlog passar do limiar e não houver card ativo na cadeia | Não prioriza; não escreve descrição técnica; não executa |
| **Diretor Tech** | Captar **1** card Aguardando (mais antigo) do DB Tech; rotear para Mail-Pro ou Eng. SmartEnvios; escrever descrição técnica; mover para **Priorizado**; criar card Priorizado para rotina Mail-Pro **só** se não existir card ativo (dedupe por título+Agente) | Não executa e-mail; não cria card para Eng. Prompt (vai para Pessoal) |
| **Diretor Pessoal** | Captar **1** card Aguardando do DB Pessoal; rotear para Mail-Person ou Eng. de Prompt; descrição técnica; **Priorizado**; rotina Mail-Person com dedupe | Não executa; não cria no DB SmartEnvios |
| **Diretor Negócios** | Captar **1** card Aguardando do DB Canper; rotear; descrição técnica; **Priorizado** | Não executa; não opera em Tech/Pessoal |
| **Mail-Pro** | Captar **1** card Priorizado com Agente=Mail-Pro no DB Tech (ou rodar triagem sem card se backlog e-mail ≥ limiar); executar workflow Gmail (triagem, labels, rascunhos, arquivar); comentar resultado no card; mover para **Concluído** | Não cria cards; não prioriza; não opera no DB Pessoal; não altera cron/scripts (isso é Eng. de Prompt) |
| **Mail-Person** | Idem para Agente=Mail-Person no DB Pessoal e caixa pessoal; 1 card por rodada ou triagem sem card se backlog ≥ limiar | Não cria cards; não prioriza; não opera no DB SmartEnvios; não altera cron/scripts |
| **Eng. de Prompt** | Captar **1** card Priorizado/Em andamento com Agente=Eng. de Prompt no **DB Pessoal**; implementar melhoria (prompts, agentes, docs, cron, scripts OpenClaw); **Concluído** ou Impedimento se contexto insuficiente | Não cria cards no SmartEnvios; não prioriza; não executa tarefa de outro especialista (e-mail, código SmartEnvios); não altera credenciais nem desabilita crons sem aprovação |
| **Eng. SmartEnvios** | Captar **1** card Priorizado/Em andamento com Agente=Eng. SmartEnvios no **DB Tech**; executar tarefa técnica (bug, feature, MCP) em repos `/var/www/`; **Concluído** com evidências | Não cria cards; não prioriza; não altera estrutura OpenClaw (cron, prompts, FLUXO_AGENTES — isso é Eng. de Prompt); não opera e-mail; aprovação obrigatória para deploy/dados sensíveis |
| **Governança** | Health check; recuperar crons/sessões; **corrigir** roteamento (ex.: Eng. Prompt no SmartEnvios → migrar para Pessoal); **escalar** causa raiz (card para Eng. Prompt); escrever gargalos para o Otimizador; **não** criar demanda de negócio | Não move card de status por decisão de negócio; não executa tarefa de especialista |
| **Otimizador** | Ler custo/tokens, **ler gargalos da Governança**, aplicar correções de baixo risco, **criar/atualizar cards para Eng. de Prompt** com causa raiz e critério de aceite; atualizar KNOWLEDGE e memory | Não desabilita crons; não altera credenciais |

Regra de ouro: **quem cria em Aguardando é o Presidente (ou script de rotina sob regra clara). Quem promove para Priorizado é o Diretor. Quem executa é o Especialista. Quem corrige e escala causa raiz é a Governança. Quem elimina a causa raiz é o Otimizador (via Eng. de Prompt).**

### 2.1 Papéis dos especialistas (detalhado)

Cada especialista opera em **um** Notion e **um** tipo de tarefa. Nenhum substitui outro.

| Especialista | Notion (DB) | Capta de | Move para | Escopo de execução | Nunca faz |
|--------------|-------------|----------|-----------|--------------------|-----------|
| **Mail-Pro** | SmartEnvios (Tech) | Priorizado, Agente=Mail-Pro | Em andamento → Concluído | Caixa rafael.pereira@smartenvios.com: triagem, labels Mail-Pro-*, rascunhos, marcar lido, arquivar | Criar/priorizar cards; tocar DB Pessoal; alterar cron/scripts do OpenClaw |
| **Mail-Person** | Pessoal | Priorizado, Agente=Mail-Person | Em andamento → Concluído | Caixa pessoal: triagem, labels Mail-Person-*, rascunhos, arquivar | Criar/priorizar cards; tocar DB SmartEnvios; alterar cron/scripts |
| **Eng. de Prompt** | Pessoal | Priorizado ou Em andamento, Agente=Eng. de Prompt | Em andamento → Concluído ou Impedimento | OpenClaw: agentes, prompts, FLUXO_AGENTES, KNOWLEDGE, SETUP_COMPLETO, crons, scripts (workspace), GitHub Rafael-Candido/openclaw | Criar cards no SmartEnvios; priorizar; executar e-mail ou código SmartEnvios; alterar .env/credenciais; desabilitar crons sem aprovação |
| **Eng. SmartEnvios** | SmartEnvios (Tech) | Priorizado ou Em andamento, Agente=Eng. SmartEnvios | Em andamento → Concluído | Código e sistemas SmartEnvios em `/var/www/` (MCP, microserviços); GitHub SmartEnvios | Criar/priorizar cards; alterar prompts/crons/docs do OpenClaw (é Eng. de Prompt); operar e-mail; deploy/dados sensíveis sem aprovação no card |

**Separação crítica:** Problema na caixa de e-mail ou no fluxo do Mail-Pro → **Mail-Pro** executa a triagem. Correção no cron, no `workflow.sh` ou na config do OpenClaw → **Eng. de Prompt** implementa. Bug/feature em repo SmartEnvios ou MCP → **Eng. SmartEnvios** implementa.

---

## 3. Coordenação Presidente – Governança – Otimizador

- **Presidente**
  - Cria demanda quando faz sentido; não encher Aguardando além da capacidade de drenagem dos diretores.
  - Pode consumir sinal da Governança (ex.: “backlog e-mail alto”) para forçar cadeia (wake Diretor + Mail) em vez de só criar card.
  - Revisar cards Concluídos e feedback para melhorar descrições e fluxos (aprendizado contínuo).

- **Governança**
  - Detecta congestionamento (backlog Aguardando/Priorizado, cards travados, roteamento errado).
  - **Corrige na hora:** wake do cron certo, migrar card para o DB certo, rebaixar card sem contexto.
  - **Entrega para o Otimizador:** ao final da rodada, escreve em `workspace/docs/operacao/governance-bottlenecks-for-optimizer.md` os gargalos do dia (key, severity, título, recomendação) para o Otimizador ler e transformar em melhoria estrutural.
  - **Resposta a gargalo:** corrigir causa raiz (cron, script, fluxo) via Otimizador/Eng. de Prompt; **não** adicionar novo fallback nem nova lógica de recovery na governança.

- **Otimizador**
  - Roda com a cadência definida (ex.: 6h); lê custo/tokens e **lê `governance-bottlenecks-for-optimizer.md`**.
  - Prioridade: custo/token → estabilidade → vazão do Notion.
  - Para cada gargalo recorrente: causa raiz → card para Eng. de Prompt com evidência + mudança proposta + critério de aceite; ou fix direto quando for baixo risco.
  - Atualiza KNOWLEDGE e memory para o fluxo evoluir e a Governança ter cada vez menos “incêndios”.

Objetivo de longo prazo: **fluxo estável com zero congestionamento recorrente**; Governança só age em exceções; Otimizador e Eng. de Prompt incorporam as lições no desenho do fluxo.

---

## 4. Ajustes de throughput (reduzir congestionamento)

- **Diretores:** Manter 1 card por rodada por padrão. Opcional: se contagem de Aguardando no DB do diretor > N (ex.: 5), processar 2 cards na mesma rodada (configurável por env ou KNOWLEDGE).
- **Presidente:** Não criar novo card de rotina (e-mail) se já existir card ativo na cadeia (Aguardando + Priorizado + Em andamento) para aquele Agente. Limites por cooldown já existem em `president-mail-demand-cycle.sh`.
- **Governança:** Já força wake quando há backlog; já migra cards Eng. Prompt para Pessoal; já cria card de causa raiz. Garantir que **sempre** escreva os gargalos no arquivo para o Otimizador.
- **Especialistas:** Manter 1 card por rodada para evitar corrida e duplicidade; aumentar frequência dos crons (ex.: Eng. Prompt 10 min) se a fila Priorizado for estruturalmente alta, ou escalar para o Otimizador “reduzir causa de acúmulo” (ex.: menos criação ou descrições melhores).

---

## 5. Referências

- Lifecycle e responsabilidades gerais: `workspace/FLUXO_AGENTES.md`
- Padrões de assinatura e comentários: `workspace/templates/agent-behavior-patterns.md`
- Governança: `workspace/scripts/governance-check.sh`
- Otimizador: `workspace/scripts/optimizer-deterministic-cycle.sh`, `workspace/scripts/optimizer-prompt.txt`
- Handoff Governança → Otimizador: `workspace/docs/operacao/governance-bottlenecks-for-optimizer.md`
