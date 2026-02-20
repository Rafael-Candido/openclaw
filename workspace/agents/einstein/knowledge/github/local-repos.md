# Repositórios Locais (/var/www)

Lista de repositórios SmartEnvios disponíveis localmente para consulta técnica.

## Microserviços SmartEnvios (ms.*)

### ms.atendimento
**Path:** `/var/www/ms.atendimento`
**Descrição:** Sistema de atendimento ao cliente

### ms.connectors
**Path:** `/var/www/ms.connectors`
**Descrição:** Conectores para integrações externas

### ms.crm
**Path:** `/var/www/ms.crm`
**Descrição:** Sistema de CRM (Customer Relationship Management)

### ms.customer-service
**Path:** `/var/www/ms.customer-service`
**Descrição:** Serviço de atendimento ao cliente

### ms.expedition-hub
**Path:** `/var/www/ms.expedition-hub`
**Descrição:** Hub de expedição de envios

### ms.label-processor
**Path:** `/var/www/ms.label-processor`
**Descrição:** Processador de etiquetas de envio

### ms.notifications
**Path:** `/var/www/ms.notifications`
**Descrição:** Sistema de notificações (webhooks, emails, etc)

### ms.points
**Path:** `/var/www/ms.points`
**Descrição:** Sistema de pontos de coleta/entrega

### ms.ticket-generator
**Path:** `/var/www/ms.ticket-generator`
**Descrição:** Gerador de tickets de suporte

### ms.zardbank
**Path:** `/var/www/ms.zardbank`
**Descrição:** Integração bancária

### ms.devolution-panel
**Path:** `/var/www/ms.devolution-panel`
**Descrição:** Painel de devoluções

---

## Outros Repos Relevantes

### mcp
**Path:** `/var/www/mcp`
**Descrição:** Model Context Protocol - Interface de dados estruturados

### smart-verso
**Path:** `/var/www/smart-verso`
**Descrição:** Backend principal SmartEnvios

### openclaw
**Path:** `/var/www/openclaw`
**Descrição:** Este sistema OpenClaw

---

## Como Usar para Troubleshooting

### 1. Buscar por erro/função específica
```bash
# Buscar em todos os repos
grep -r "erro específico" /var/www/ms.* 2>/dev/null | head -20

# Buscar em repo específico
grep -r "função" /var/www/ms.connectors/
```

### 2. Ver configurações (.env)
```bash
# Verificar variáveis de ambiente
cat /var/www/ms.connectors/.env

# Ver exemplo de config
cat /var/www/ms.connectors/.env.example
```

### 3. Consultar README/docs
```bash
# Ver documentação
cat /var/www/ms.connectors/README.md
cat /var/www/ms.connectors/docs/*.md
```

### 4. Ver dependências
```bash
# Node.js
cat /var/www/ms.connectors/package.json | jq '.dependencies'

# Python
cat /var/www/ms.connectors/requirements.txt
```

---

## Fluxos Comuns

### Rastreamento de Envio
**Repos envolvidos:**
- `ms.expedition-hub` - Cria envio
- `ms.label-processor` - Gera etiqueta
- `ms.notifications` - Notifica cliente
- `ms.connectors` - Integra com transportadoras

### Atendimento ao Cliente
**Repos envolvidos:**
- `ms.customer-service` - Interface de atendimento
- `ms.ticket-generator` - Cria tickets
- `ms.crm` - Gestão de clientes
- `ms.notifications` - Envia notificações

### Integrações
**Repos envolvidos:**
- `ms.connectors` - Conectores principais
- `mcp` - Interface de dados
- `smart-verso` - Backend core

---

## ⚠️ Atenção

- **Não expor .env em respostas públicas**
- **Não compartilhar código-fonte completo**
- Use apenas para entender funcionamento e troubleshooting
- Cite apenas conceitos, não implemente detalhes sensíveis

---

## Sugestão de Resposta

**Quando usuário perguntar sobre bug/erro:**

1. Verificar se é erro conhecido nos logs
2. Buscar no repo relevante
3. Consultar .env.example para ver se é config missing
4. Explicar causa provável + solução

**Exemplo:**
> "Esse erro normalmente acontece no `ms.connectors` quando a integração com a transportadora falha. Verifique se as credenciais estão configuradas corretamente no painel e se o endpoint da transportadora está respondendo. Documentação: [link Zendesk]"
