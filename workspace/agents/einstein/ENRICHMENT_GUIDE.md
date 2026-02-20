# Guia de Enriquecimento - Einstein

Este guia explica como adicionar conhecimento e contexto ao Einstein para torná-lo mais eficaz.

## Estrutura de Arquivos

```
agents/einstein/
├── SOUL.md                 # Identidade e comportamento (não editar sem necessidade)
├── KNOWLEDGE.md            # Base de conhecimento (ENRIQUEÇA AQUI)
├── README.md               # Overview (documentação interna)
├── ENRICHMENT_GUIDE.md     # Este arquivo
└── [adicionar mais arquivos conforme necessário]
```

## Como Enriquecer

### 1. Adicionar FAQs

Edite `KNOWLEDGE.md`, seção **FAQ - Perguntas Frequentes**:

```markdown
## FAQ - Perguntas Frequentes

### Como criar um envio via API?

**Endpoint:** `POST /api/v1/envios`

**Request:**
\`\`\`json
{
  "destinatario": {
    "nome": "João Silva",
    "cep": "01310-100",
    "endereco": "Av. Paulista, 1000"
  },
  "pacote": {
    "peso": 2.5,
    "dimensoes": {
      "altura": 10,
      "largura": 20,
      "comprimento": 30
    }
  }
}
\`\`\`

**Response:**
\`\`\`json
{
  "id": "ENV-123456",
  "status": "aguardando_coleta",
  "rastreio": "BR123456789"
}
\`\`\`
```

### 2. Documentar Troubleshooting

Edite `KNOWLEDGE.md`, seção **Troubleshooting Comum**:

```markdown
## Troubleshooting Comum

### Erro: "CEP inválido"

**Causa:** CEP fora do padrão ou não encontrado na base dos Correios.

**Solução:**
1. Validar formato: `XXXXX-XXX` (8 dígitos)
2. Consultar CEP em https://buscacepinter.correios.com.br
3. Se CEP válido mas erro persiste, reportar ao suporte

### Webhook não recebe notificações

**Causa:** URL webhook inválida ou firewall bloqueando.

**Solução:**
1. Testar URL com curl:
   \`\`\`bash
   curl -X POST https://seu-webhook.com/path \
     -H "Content-Type: application/json" \
     -d '{"test": true}'
   \`\`\`
2. Verificar logs no painel SmartEnvios
3. Garantir que servidor aceita HTTPS
```

### 3. Adicionar Exemplos de Integrações

Crie novos arquivos no workspace:

```bash
# Exemplo: Node.js
mkdir -p agents/einstein/examples/nodejs
cat > agents/einstein/examples/nodejs/create-shipment.js << 'EOF'
const axios = require('axios');

async function createShipment(data) {
  const response = await axios.post('https://api.smartenvios.com/v1/envios', data, {
    headers: {
      'Authorization': `Bearer ${process.env.SMARTENVIOS_API_KEY}`,
      'Content-Type': 'application/json'
    }
  });
  return response.data;
}

module.exports = { createShipment };
EOF
```

### 4. Adicionar Documentação de API

Crie arquivo `API_REFERENCE.md`:

```bash
cat > agents/einstein/API_REFERENCE.md << 'EOF'
# SmartEnvios API Reference

## Autenticação

Todas as requisições requerem um Bearer token:

\`\`\`
Authorization: Bearer YOUR_API_KEY
\`\`\`

## Endpoints

### POST /api/v1/envios
Criar um novo envio

### GET /api/v1/envios/:id
Consultar status de um envio

### PATCH /api/v1/envios/:id
Atualizar informações de um envio

### GET /api/v1/rastreio/:codigo
Rastrear envio por código

(continuar com todos os endpoints...)
EOF
```

### 5. Adicionar Changelog

Edite `KNOWLEDGE.md`, seção **Changelog e Updates**:

```markdown
## Changelog e Updates

### 2026-02-20
- **[Novo]** Endpoint `/api/v1/etiquetas/bulk` para gerar múltiplas etiquetas
- **[Fix]** Corrigido cálculo de frete para regiões remotas
- **[Deprecated]** Endpoint `/api/v1/old-envios` será removido em março/2026

### 2026-02-15
- **[Novo]** Suporte a Webhook v2 com assinatura HMAC
- **[Breaking]** Campo `peso` agora obrigatório em todos os envios
```

## Fontes de Informação

### Onde buscar conteúdo para enriquecer

1. **Documentação oficial SmartEnvios:**
   - https://docs.smartenvios.com (se disponível)
   - Swagger/OpenAPI specs
   - Postman collections

2. **Tickets de suporte:**
   - Revisar tickets resolvidos
   - Extrair padrões de perguntas comuns
   - Documentar soluções que funcionaram

3. **Discord/Chat histórico:**
   - Buscar conversas sobre SmartEnvios
   - Identificar dúvidas recorrentes
   - Copiar respostas bem-sucedidas

4. **Código-fonte:**
   - READMEs de repositórios
   - Comentários em código de integrações
   - Testes unitários (exemplos de uso)

5. **Changelogs e Release Notes:**
   - Git commits
   - PRs merged
   - Announcements em canais internos

## Automação de Enriquecimento

### Script para adicionar FAQ automaticamente

```bash
#!/bin/bash
# add-faq.sh

QUESTION="$1"
ANSWER="$2"

cat >> agents/einstein/KNOWLEDGE.md << EOF

### ${QUESTION}

${ANSWER}

EOF

echo "✅ FAQ adicionada com sucesso!"
```

**Uso:**
```bash
./add-faq.sh "Como cancelar um envio?" "Para cancelar, use DELETE /api/v1/envios/:id"
```

## Validação de Conhecimento

Antes de commitar mudanças no KNOWLEDGE.md:

1. **Revisar com especialista:** Validar informações técnicas
2. **Testar exemplos:** Garantir que código funciona
3. **Verificar links:** URLs devem estar acessíveis
4. **Formatar corretamente:** Markdown válido

## Manutenção

- **Frequência:** Revisar KNOWLEDGE.md semanalmente
- **Remover obsoleto:** Deletar informações desatualizadas
- **Priorizar recorrências:** FAQs mais perguntadas no topo
- **Versionar:** Commit após cada enriquecimento significativo

---

**Lembre-se:** Quanto mais rico o contexto, melhores as respostas do Einstein! 🧠
