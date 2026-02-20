# TOOLS.md - Einstein

## SmartEnvios MCP

Cliente para consultar a API SmartEnvios (cotações, CEP, etc.) via MCP.

**Script:** `/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh`

```bash
# Login (faz automaticamente se token não existir)
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh login

# Listar ferramentas disponíveis
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh tools

# Consultar CEP
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call cep_lookup '{"cep":"14025710"}'

# Cotação de frete
/var/www/openclaw/workspace/scripts/smartenvios-mcp.sh call smartenvios_quote_freight '{"zip_code_start":"14025710","zip_code_end":"01001010","volumes":[{"quantity":1,"length":20,"height":20,"weight":0.2,"width":20}]}'
```

**Quando usar:** sempre que alguém pedir cotação, consultar CEP, ou qualquer operação SmartEnvios que o MCP suporte.

## Notion SmartEnvios (skill: notion)

Acesso ao workspace Notion SmartEnvios para criar cards de escalonamento.

**Database ID:** `adec12e735dc41a3bb7c274b287f3a10`

**Quando usar:** quando Einstein **não conseguir resolver** algo sozinho (falta de acesso, limitação técnica, necessidade de implementação).

## Gmail Scripts

Scripts de e-mail para referência (Einstein não executa diretamente, mas pode orientar):

```bash
/var/www/openclaw/workspace/scripts/gmail/gmail.sh pro labels
/var/www/openclaw/workspace/scripts/gmail/gmail.sh pro list "is:unread"
```
