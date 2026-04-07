

## Problema: Falha na Criação de Cards Notion com Conteúdo Extenso (HTTP 0)
- **Data:** 2026-04-06
- **Contexto:** Ao tentar criar ou atualizar cards no Notion via `notion-helper.sh create-card` ou `append-body` com um `body_file` contendo conteúdo extenso, a operação falhou consistentemente com erro `HTTP 0` (falha de conexão/requisição `curl`). No entanto, a criação de cards mais simples ou para outros agentes (sem `body_file` complexo) funcionou.
- **Causa Raiz Provável:** Embora o `BODY` JSON pareça bem-formado, o erro `HTTP 0` em `curl` durante o `POST` para `api.notion.com` indica que o payload JSON gerado a partir de um `body_file` muito longo ou complexo pode estar excedendo limites internos da API do Notion ou de conectividade no momento da requisição. Isso não é um erro de validação JSON, mas uma falha de baixo nível na comunicação HTTP/S.
- **Correção Aplicada:** Para contornar, reduziu-se o tamanho e a complexidade do `body_file` utilizado na criação do card de investigação. A delegação de tarefas de investigação que geram logs extensos agora será feita com um contexto mais conciso no card, e a análise de detalhes será feita sob demanda pelo agente especialista.
- **Padrão Reforçado:** Evitar `body_file` excessivamente longos ou complexos (`> 2000-3000 caracteres` como regra de bolso) ao criar ou anexar conteúdo a cards do Notion. Mantenha os corpos dos cards concisos e priorize links para contexto externo ou crie subtarefas para detalhes.
- **Impacto:** Bloqueia a criação e atualização de cards com documentação detalhada inline, exigindo uma abordagem mais modular de documentação e delegação.

