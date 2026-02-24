# Design Patterns Operacionais — Agentes OpenClaw

Este documento define padrões transversais para comportamento de agentes em atividades semelhantes.

Objetivo:
- reduzir variação de estilo entre agentes;
- facilitar leitura de histórico por humanos e automações;
- tornar previsível quando comentar, quando detalhar no corpo e quando apenas executar.

Escopo de consumo:
- Este é o contrato único para comportamentos operacionais semelhantes no fluxo OpenClaw.
- AGENTS por papel devem manter apenas regras específicas (delta), sem duplicar padrão transversal.
- Novo especialista (ou novo cron de especialista) deve nascer aderente a este documento, incluindo fatiamento obrigatório para demanda complexa.

## 1) Padrão de Assinatura (obrigatório)

Regra geral:
- todo comentário no Notion deve usar `notion-helper.sh comment ... 'ASSINATURA'`;
- a assinatura vira prefixo no comentário: `[ASSINATURA]`.

Assinaturas recomendadas:
- Agentes: `Presidente`, `Diretor Tech`, `Diretor Pessoal`, `Diretor Negócios`, `Mail-Pro`, `Mail-Person`, `Engenheiro de Prompt`, `Engenheiro SmartEnvios`, `Governança`, `Otimizador`.
- Humano (quando for anotação manual): `Rafael`.

Exemplos:
- `[Mail-Pro] Início da execução do card ...`
- `[Rafael] Avaliei o ticket e aprovei a proposta.`

## 1.1) Contrato Operacional Comum (atividades semelhantes)

Para qualquer atividade baseada em card Notion no fluxo OpenClaw:
- lifecycle padrão: `Aguardando` -> `Priorizado` -> `Em andamento` -> `Concluído`;
- ordem de captura do especialista: **retomar primeiro `Em andamento`**, depois captar `Priorizado` (mais antigo primeiro);
- orçamento determinístico padrão: **1 card por rodada por agente** (salvo exceção explícita no cron);
- deduplicação por **título + agente** no status de saída do papel;
- status só pode ir para `Concluído` quando execução estiver efetivamente aplicada (não apenas análise);
- toda métrica declarada em comentário final deve vir de output real de execução.
- é proibido fechar card por “drenagem manual” sem execução real do agente responsável.

### 1.1.1) Fatiamento obrigatório para tarefas complexas (micro-cards)

Objetivo:
- garantir execução visual, rastreável e retomável em ciclos curtos de cron.

Regra:
- antes de executar demanda complexa, o especialista deve estimar esforço e quebrar em micro-cards;
- cada micro-card deve ter objetivo único, evidência de pronto e ETA alvo curto (padrão: `<=30s` por rodada);
- a execução nas rodadas seguintes deve priorizar micro-cards sobre card macro;
- o card macro vira card pai de acompanhamento e não deve gerar duplicação de planejamento.

Critério de tarefa complexa (heurística mínima):
- escopo amplo (ex.: "novo projeto", "arquitetura", "integração grande", "refatoração ampla");
- descrição longa ou com múltiplas entregas dependentes.

Regras de idempotência:
- marcar o card pai com identificador de microplano (`MICROPLAN_V1_PARENT`);
- nunca recriar micro-cards se já existir marcador válido;
- comentários de progresso devem citar etapa atual e próximo micro-card.
- aplicar limite de WIP de micro-cards por especialista; ao atingir o teto, adiar novo fatiamento e drenar a fila ativa.

Regra de retomada:
- quando houver micro-cards pendentes, o especialista retoma primeiro a menor fatia pendente de maior prioridade;
- somente após concluir as fatias obrigatórias o fluxo volta ao card pai para consolidação final.

Escopo de consulta por papel:
- Presidente: cria em `Aguardando` e não opera execução técnica;
- Diretor: capta `Aguardando`, normaliza em `Priorizado`, define especialista;
- Especialista: capta `Priorizado`, executa em `Em andamento`, conclui.

## 1.2) Padrão de Severidade e Prioridade (obrigatório)

Objetivo:
- padronizar urgência entre agentes e reduzir cards sem classificação.

Regra geral:
- todo card criado por automação deve preencher a propriedade `Prioridade` no Notion.

Mapeamento canônico:
- `critical` ou `high` -> `Alta`
- `medium` -> `Média`
- `low` -> `Baixa`

Fallback quando severidade não vier explícita:
- card criado em `Priorizado` -> `Média`
- card criado em `Aguardando` -> `Baixa`

Regra de escalonamento:
- se card ficar parado por múltiplos ciclos de cron, subir prioridade em um nível (até `Alta`) e comentar a razão.

## 2) Padrão de Comentários

### 2.1 Início (curto)
Quando usar:
- ao captar card e mover para `Em andamento`.

Formato:
- 1 linha, com ação atual e próximo passo.

Exemplo:
- `Início: card captado. Próximo passo: validar credenciais e executar workflow.`

### 2.2 Progresso (curto)
Quando usar:
- em etapas longas;
- antes/depois de ações de risco;
- quando execução passar de 2-3 minutos.

Formato:
- `Etapa X/N`, resultado parcial e próximo passo.

Exemplo:
- `Etapa 2/4: 5 e-mails triados, labels aplicadas. Próximo: criar rascunhos.`

Regra de ETA (obrigatória):
- se o card ficar sem atualização do agente por janela acima do limite operacional (ex.: 20-30 min), publicar comentário de progresso com:
  - etapa atual;
  - ações pendentes;
  - ETA revisado.
- esse comentário deve ser assinado e objetivo (sem repetir texto idêntico).

### 2.3 Bloqueio (curto + objetivo)
Quando usar:
- erro de credencial, script, permissão, timeout, API.

Formato:
- erro + impacto + ação de contenção.

Exemplo:
- `Bloqueio: NOTION_PERSONAL_API_KEY ausente. Execução pausada; card permanece em Em andamento.`

Regra de contexto mínimo (obrigatória):
- se o card não tiver contexto técnico/funcional mínimo para execução (ex.: descrição vazia ou insuficiente), não manter em loop;
- comentar bloqueio com motivo objetivo e mover para `Impedimento`.

### 2.4 Conclusão (estruturado)
Quando usar:
- sempre ao finalizar execução do especialista;
- opcional para diretor (quando decisão relevante);
- obrigatório para governança/otimizador quando houver incidente.

Formato mínimo:
- `## Resultado executivo`
- `## Métricas`
- `## Evidências`
- `## Decisões e próximos passos`

Campos recomendados por tipo:
- operações de e-mail: incluir `marcados como lidos`, `arquivados`, `rascunhos`;
- desenvolvimento técnico: incluir `arquivos alterados`, `commits/PR`, `resultado de testes`;
- governança/otimização: incluir `incidente`, `causa raiz`, `ação aplicada`, `prevenção`.

### 2.5 Anti-Spam de Comentário (obrigatório)
Quando NÃO comentar:
- não repetir o mesmo comentário de acompanhamento no mesmo card sem mudança real de estado;
- não comentar em loop com o mesmo texto em execuções consecutivas.

Regra prática:
- comentar apenas em: mudança de status, bloqueio novo, avanço de etapa, conclusão;
- mensagens de acompanhamento idênticas no mesmo card devem ser evitadas (dedupe por texto normalizado).
- comentário de conclusão deve conter evidência mínima: comando/script executado + resultado objetivo + validação final.

## 3) Padrão Corpo x Comentário

Use corpo do card (`append-body`) para:
- escopo estável;
- descrição técnica/função;
- critérios de conclusão;
- decisões arquiteturais.

Use comentário para:
- linha do tempo de execução;
- progresso, bloqueios e resultado operacional;
- aprovações e checkpoints.

Regra prática:
- se muda o "como executar", atualizar corpo;
- se mostra "o que aconteceu na execução", comentar.

### 3.1 Idempotência do Corpo (obrigatório)
- diretores não devem reapendar a especificação completa em toda triagem;
- antes de `append-body`, verificar se a seção já existe e escrever apenas delta;
- evitar duplicar seções estruturais como `Objetivo`, `Escopo`, `Critérios de conclusão`.

Para rotinas de Mail:
- não fixar `limite 100` no corpo como regra permanente;
- descrever como `lote base + autoescalonamento seguro`, refletindo execução real.

## 4) Padrões por Papel

### Presidente
- cria card funcional em `Aguardando`;
- não detalha implementação técnica;
- comentário apenas quando houver mudança de entendimento, dependência externa ou follow-up.

### Diretores
- convertem para `Priorizado`;
- escrevem detalhamento técnico/funcional no corpo;
- definem especialista (`Agente`);
- comentário de triagem é obrigatório ao mover `Aguardando -> Priorizado` (informar agente destino e resumo da decisão).
- normalizam legado de agente ao triar (ex.: `Tech` -> `Diretor Tech` ou especialista final), evitando card parado fora da fila correta.

### Especialistas
- captam em `Priorizado`, executam em `Em andamento`, concluem;
- padrão mínimo de comentários: início + (progresso se necessário) + conclusão estruturada;
- métricas sempre com dados reais da execução.
- após `update-status`, validar estado final no Notion (verificação pós-write) antes de prosseguir;
- se a transição não confirmar, abortar rodada com status de falha controlada (sem concluir indevidamente).
- primeira ação em tarefa complexa: planejar e fatiar em micro-cards com ETA e critério de pronto.

### Gestores Operacionais (Governança / Otimizador)
- foco em saúde do fluxo, erros recorrentes e causa raiz;
- devem comentar incidentes, ação aplicada e recomendação;
- quando abrir card de melhoria, usar assinatura explícita e corpo estruturado.
- Governança deve auditar periodicamente a adoção deste documento e abrir card para `Engenheiro de Prompt` quando detectar desvios ou novas oportunidades de padronização.

### 4.1) Regra de Cadeia sem Sobreposição (Presidente -> Diretor -> Especialista)
- O Presidente só cria demanda quando backlog >= limiar e **não existe card aberto da mesma rotina** (dedupe por prefixo de título da rotina).
- Se a cadeia estiver vazia e backlog persistir, o Presidente pode furar cooldown e recriar demanda (não deixar fluxo sem card).
- Wake forçado deve ser seletivo por domínio:
  - Profissional: acordar apenas `Diretor Tech` e `Mail-Pro`.
  - Pessoal: acordar apenas `Diretor Pessoal` e `Mail-Person`.
- Não acordar todos os crons indiscriminadamente; isso cria corrida e degrada throughput.
- Otimizador deve ser acordado apenas quando houve criação de nova demanda (evento de mudança real).
- Governança deve validar em cada auditoria:
  - backlog de e-mail,
  - quantidade de cards abertos por cadeia,
  - tempo entre criação -> triagem -> execução -> conclusão.

### 4.2) Triagem de Diretor (transação curta)

Fluxo recomendado para diretores ao triar:
1. Captar card e aplicar lock curto em `Em andamento` para evitar corrida.
2. Definir `Agente` de destino + comentário de triagem assinado.
3. Retornar para `Priorizado` para execução do especialista.

Restrições:
- diretor não conclui execução técnica no lugar do especialista;
- toda triagem deve deixar explícito no comentário o próximo executor.

### 4.1) Protocolo de Recuperação Autônoma (Governança)

A cada rodada, a Governança deve executar nesta ordem:
1. Detectar anomalia operacional (stuck, abandonado, backlog, roteamento incorreto, card vazio).
2. Aplicar recuperação imediata (wake/run, normalização de agente, quarantine de card inválido).
3. Registrar gargalo com severidade e evidência objetiva.
4. Escalonar melhoria estrutural para `Engenheiro de Prompt` no Notion Pessoal.
5. Reportar resultado no painel (o que foi corrigido agora vs o que depende de evolução estrutural).
6. Auditar cards recém-concluídos: se não houver evidência mínima, reabrir para `Priorizado` e acionar wake do agente responsável.

Restrições:
- não ficar apenas em “status ok” quando houver cards parados ou backlog alto;
- não abrir card técnico sem descrição mínima (objetivo + escopo + critério de aceite);
- não deixar roteamento inválido persistir entre bancos Notion (profissional x pessoal).

## 5) Padrão de Ferramentas

Notion:
- usar `workspace/scripts/notion-helper.sh` (query, update-status, comment, append-body, create-card);
- sempre caminho absoluto em automação;
- comentário com assinatura obrigatória (4º parâmetro).
- `notion-helper.sh comment` aplica dedupe anti-spam de comentário idêntico no mesmo card.
- criação de card com autoria explícita (`create-card` com criador).

OpenClaw (autonomia operacional):
- scripts de automação devem usar `workspace/scripts/openclaw-helper.sh` (retry + hard timeouts) quando chamarem `openclaw` em loop;
- toda etapa de auditoria/integração externa (Notion/API) deve ter orçamento de tempo interno; ao atingir o limite, retornar parcial e seguir a rodada (nunca travar execução inteira);
- Governança pode executar ações de recuperação sem intervenção humana:
  - `ocw_cron_run` (forçar execução imediata de cron),
  - `ocw_cron_wake_now` (wake quando o run falhar),
  - `ocw_sessions_reset` (derrubar sessão problemática de cron),
  - `ocw_cron_disable`/`ocw_cron_enable` (circuit breaker para falhas previsíveis de credencial/billing),
  - `ocw_gateway_restart` (somente quando gateway estiver DOWN ou quando explicitamente habilitado por flag).
- evitar reiniciar o gateway no meio de uma rodada enquanto está forçando `cron run` (usar restart "post-ops" quando necessário).

Gmail:
- usar pipeline unificado para especialistas de e-mail;
- após triagem e aplicação de labels, marcar como lido e arquivar;
- reportar contagens reais (triados, marcados como lidos, arquivados, rascunhos).
- regra de rascunho: só criar `draft` quando o e-mail estiver claramente direcionado ao usuário (`To` direto) **e** houver sinal de pedido/ação (request signal) ou thread acionável.
- e-mails promocionais/comerciais (ex.: convite genérico, newsletter, outreach) não devem virar `draft` automático; classificar como `review` ou `label`.

Regras transversais de execução:
- preferir fluxo automatizado padronizado em vez de lógica ad hoc por agente;
- usar caminhos absolutos em automação (`/var/www/openclaw/workspace/...`);
- evitar polling infinito e “estado herdado” de sessão anterior.
- para comunicações operacionais recorrentes (ex.: painel da governança no WhatsApp), priorizar formato textual; usar imagem apenas quando explicitamente solicitado.

## 6) Convenção de Texto

- Frases curtas e diretas.
- Evitar texto promocional.
- Sem ambiguidade temporal: usar timestamp quando útil.
- Não duplicar conteúdo: corpo para especificação, comentário para execução.

## 7) Quando estes padrões ajudam mais

- Muitos cards semelhantes em paralelo.
- Troca de responsável no meio da execução.
- Auditoria de incidentes e regressões.
- Governação por cron (detecção de travas por `last_edited_time`).

Nota de confiabilidade de atividade:
- `last_edited_time` da página pode não refletir atividade real do agente em todos os casos.
- para medir “tempo sem atualização”, preferir a **última atividade assinada do agente nos comentários**; usar `last_edited_time` apenas como fallback.

## 8) Checklist rápido

- Assinatura correta no comentário.
- Status correto do card.
- Corpo atualizado (se escopo mudou).
- Comentário final estruturado com métricas reais.
- Evidências objetivas (IDs, links, outputs).
- Sem divergência de formato entre agentes do mesmo tipo de tarefa.
