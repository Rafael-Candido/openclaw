# Playbook de Release do MCP SmartEnvios

> Última revisão: 2026-02-21 08:55 BRT

Este playbook descreve o fluxo obrigatório para publicar uma nova versão do repositório [`SmartEnvios/mcp`](https://github.com/SmartEnvios/mcp). Ele cobre desde o PR inicial até a criação da tag e da release de produção. Siga estes passos sempre que o Diretor Tech solicitar uma entrega do MCP.

## Pré-requisitos

- Branch de trabalho atualizada (ex.: `jira-soft`).
- Acesso de escrita no repositório `SmartEnvios/mcp`.
- Git configurado com a sua chave SSH.
- Credenciais para publicar releases e tags.
- Ambiente local com Node 22+ e dependências instaladas (`npm install`).

## Fluxo completo

1. **Sincronizar a branch de trabalho**
   ```bash
   cd /var/www/mcp
   git fetch origin
   git checkout jira-soft        # ou a branch que estiver trabalhando
   git pull --rebase origin jira-soft
   npm ci && npm test            # ou "npm run test" se aplicável
   ```
   Garanta que os testes/unit checks passem antes de abrir o PR.

2. **Abrir PR para `develop`**
   - Push da branch: `git push origin jira-soft`.
   - Abra o PR usando o link sugerido pelo Rafael: <https://github.com/SmartEnvios/mcp/pull/new/jira-soft> (base = `develop`).
   - Preencha o template com: contexto, checklist, testes e link do card Notion.
   - Aguarde review/aprovação ➝ após aprovação, faça o merge (squash ou merge normal conforme política atual; padrão: **merge commit**).

3. **Atualizar `develop` localmente**
   ```bash
   git checkout develop
   git pull origin develop
   ```

4. **Criar PR de release `develop → main`**
   - Abra novo PR com base `main` e compare `develop`.
   - Nome sugerido: `Release MCP - <data>`.
   - Inclua changelog resumido + cards impactados.
   - Após aprovação, faça o merge em `main`.

5. **Preparar tag sequencial**
   - Descubra a última tag:
     ```bash
     git checkout main
     git pull origin main
     git tag --sort=-version:refname | head -n5
     ```
   - Use a próxima versão sequencial:
     - Se o último release foi `v1.7.0`, a sequência padrão é `v1.7.1`.
     - Suba o **patch** (terceiro número) para hotfixes; suba o **minor** quando houver features relevantes.
   - Crie a tag anotada:
     ```bash
     export NEXT_TAG=v1.7.1     # ajuste conforme o passo anterior
     git tag -a "$NEXT_TAG" -m "Release $NEXT_TAG"
     git push origin "$NEXT_TAG"
     ```

6. **Criar release de produção**
   - Abra <https://github.com/SmartEnvios/mcp/releases/new>.
   - Selecione a tag recém criada (`$NEXT_TAG`).
   - Título: `Release $NEXT_TAG`.
   - Corpo (sugestão):
     ```
     ## Changes
     - <resumo das principais funções/bugfixes>

     ## QA
     - [ ] Testes unitários
     - [ ] Smoke test no ambiente de staging
     ```
   - Clique em **Publish release** (não marcar pre-release).

7. **Registrar na Notion**
   - Comente no card original: versão liberada, link do PR para `main`, link da release, tag criada.
   - Mova o card para `Concluído` após QA/staging.

8. **Comunicar status**
   - Avise o Diretor Tech (ou canal correspondente) com o resumo: PRs, tag e release publicados.

## Dicas e validações

- Sempre rode `npm test` antes de abrir o PR para evitar retrabalho.
- Se houver migrações/ajustes de infra, descreva no PR `develop → main`.
- Caso o pipeline CI falhe após o merge, corrija antes de criar a tag.
- Para automatizar o cálculo da próxima tag:
  ```bash
  LAST=$(git tag --sort=-v:refname | head -n1)
  ./scripts/bump-tag.sh "$LAST" patch   # (implementar script se necessário)
  ```
- Guarde o link dos PRs e releases no comentário final do card para facilitar auditorias futuras.

Seguindo este playbook, o Engenheiro SmartEnvios garante que o MCP chega à produção sempre passando pelos PRs de `develop`, `main`, tag e release documentada.
