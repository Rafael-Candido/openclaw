# Design Patterns Operacionais — Agentes OpenClaw

Este documento define padrões transversais para comportamento de agentes em atividades semelhantes.

Objetivo:
- reduzir variação de estilo entre agentes;
- facilitar leitura de histórico por humanos e automações;
- tornar previsível quando comentar, quando detalhar no corpo e quando apenas executar.

Escopo de consumo:
- Este é o contrato único para comportamentos operacionais semelhantes no fluxo OpenClaw.
- AGENTS por papel devem manter apenas regras específicas (delta), sem duplicar padrão transversal.

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
- deduplicação por **título + agente** no status de saída do papel;
- status só pode ir para `Concluído` quando execução estiver efetivamente aplicada (não apenas análise);
- toda métrica declarada em comentário final deve vir de output real de execução.

Escopo de consulta por papel:
- Presidente: cria em `Aguardando` e não opera execução técnica;
- Diretor: capta `Aguardando`, normaliza em `Priorizado`, define especialista;
- Especialista: capta `Priorizado`, executa em `Em andamento`, conclui.

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

### 2.3 Bloqueio (curto + objetivo)
Quando usar:
- erro de credencial, script, permissão, timeout, API.

Formato:
- erro + impacto + ação de contenção.

Exemplo:
- `Bloqueio: NOTION_PERSONAL_API_KEY ausente. Execução pausada; card permanece em Em andamento.`

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

### Gestores Operacionais (Governança / Otimizador)
- foco em saúde do fluxo, erros recorrentes e causa raiz;
- devem comentar incidentes, ação aplicada e recomendação;
- quando abrir card de melhoria, usar assinatura explícita e corpo estruturado.
- Governança deve auditar periodicamente a adoção deste documento e abrir card para `Engenheiro de Prompt` quando detectar desvios ou novas oportunidades de padronização.

## 5) Padrão de Ferramentas

Notion:
- usar `workspace/scripts/notion-helper.sh` (query, update-status, comment, append-body, create-card);
- sempre caminho absoluto em automação;
- comentário com assinatura obrigatória (4º parâmetro).
- criação de card com autoria explícita (`create-card` com criador).

Gmail:
- usar pipeline unificado para especialistas de e-mail;
- após triagem e aplicação de labels, marcar como lido e arquivar;
- reportar contagens reais (triados, marcados como lidos, arquivados, rascunhos).

Regras transversais de execução:
- preferir fluxo automatizado padronizado em vez de lógica ad hoc por agente;
- usar caminhos absolutos em automação (`/var/www/openclaw/workspace/...`);
- evitar polling infinito e “estado herdado” de sessão anterior.

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

## 8) Checklist rápido

- Assinatura correta no comentário.
- Status correto do card.
- Corpo atualizado (se escopo mudou).
- Comentário final estruturado com métricas reais.
- Evidências objetivas (IDs, links, outputs).
- Sem divergência de formato entre agentes do mesmo tipo de tarefa.
