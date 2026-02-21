# Exemplos de Uso da API SmartEnvios

## 1. Consulta de CEP via MCP

```bash
# Login no MCP
./scripts/smartenvios-mcp.sh login

# Listar ferramentas disponíveis
./scripts/smartenvios-mcp.sh tools

# Consultar CEP
./scripts/smartenvios-mcp.sh call cep_lookup '{"cep":"14020510"}'
```

**Resposta esperada:**
```json
{
  "cep": "14020510",
  "logradouro": "Rua São Sebastião",
  "bairro": "Jardim Paulistano",
  "cidade": "Ribeirão Preto",
  "estado": "SP",
  "complemento": "",
  "unidade": "",
  "ibge": "3543402",
  "gia": "5824",
  "ddd": "16",
  "siafi": "6969"
}
```

## 2. Criação de Envio (Exemplo)

**Endpoint:** `POST /api/v1/envios`

**Request:**
```json
{
  "destinatario": {
    "nome": "Maria Silva",
    "email": "maria@exemplo.com",
    "telefone": "11999999999",
    "documento": "123.456.789-00",
    "cep": "01310-100",
    "endereco": "Av. Paulista, 1000",
    "numero": "1000",
    "complemento": "Sala 101",
    "bairro": "Bela Vista",
    "cidade": "São Paulo",
    "estado": "SP"
  },
  "pacote": {
    "peso": 2.5,
    "comprimento": 30,
    "largura": 20,
    "altura": 10,
    "valor_declarado": 150.00,
    "descricao": "Livros e materiais"
  },
  "servico": "expresso",
  "transportadora": "correios"
}
```

**Response:**
```json
{
  "id": "env_abc123def456",
  "tracking_code": "BR123456789BR",
  "etiqueta_url": "https://api.smartenvios.com/etiquetas/env_abc123def456.pdf",
  "valor_frete": 25.90,
  "prazo_entrega": 3,
  "status": "criado",
  "created_at": "2026-02-21T16:20:00Z"
}
```

## 3. Rastreamento de Envio

**Endpoint:** `GET /api/v1/envios/{id}`

**Response:**
```json
{
  "id": "env_abc123def456",
  "tracking_code": "BR123456789BR",
  "status": "em_transito",
  "historico": [
    {
      "data": "2026-02-21T10:30:00Z",
      "status": "postado",
      "local": "Centro de Distribuição SP",
      "descricao": "Objeto postado"
    },
    {
      "data": "2026-02-21T14:45:00Z",
      "status": "em_transito",
      "local": "Unidade de Tratamento RJ",
      "descricao": "Objeto em trânsito"
    }
  ],
  "previsao_entrega": "2026-02-24",
  "destinatario": {
    "nome": "Maria Silva",
    "cidade": "São Paulo",
    "estado": "SP"
  }
}
```

## 4. Listagem de Transportadoras

**Endpoint:** `GET /api/v1/transportadoras`

**Response:**
```json
[
  {
    "id": "correios",
    "nome": "Correios",
    "servicos": [
      {
        "codigo": "04014",
        "nome": "SEDEX",
        "descricao": "Entrega expressa",
        "prazo_min": 1,
        "prazo_max": 3
      },
      {
        "codigo": "04510",
        "nome": "PAC",
        "descricao": "Entrega econômica",
        "prazo_min": 3,
        "prazo_max": 10
      }
    ]
  },
  {
    "id": "jadlog",
    "nome": "Jadlog",
    "servicos": [
      {
        "codigo": "expresso",
        "nome": "Jadlog Expresso",
        "descricao": "Entrega rápida",
        "prazo_min": 1,
        "prazo_max": 2
      }
    ]
  }
]
```

## 5. Geração de Etiqueta

**Endpoint:** `POST /api/v1/etiquetas`

**Request:**
```json
{
  "envio_id": "env_abc123def456",
  "formato": "pdf",
  "layout": "padrao"
}
```

**Response:**
```json
{
  "url": "https://api.smartenvios.com/etiquetas/env_abc123def456.pdf",
  "expira_em": "2026-02-28T16:20:00Z"
}
```

## 6. Tratamento de Erros Comuns

### CEP Inválido
```json
{
  "error": "cep_invalido",
  "message": "CEP não encontrado ou formato inválido",
  "details": {
    "cep": "00000000",
    "suggestion": "Verifique o formato: XXXXX-XXX"
  }
}
```

### Autenticação Falhou
```json
{
  "error": "unauthorized",
  "message": "Token de autenticação inválido ou expirado"
}
```

### Limite de Requisições
```json
{
  "error": "rate_limit_exceeded",
  "message": "Limite de requisições excedido",
  "retry_after": 60
}
```

## 7. Scripts de Exemplo

### test-api.sh
```bash
#!/bin/bash
# Teste básico da API SmartEnvios

API_URL="https://api.smartenvios.com"
API_TOKEN="${SMARTENVIOS_API_TOKEN}"

# Consultar CEP
curl -s -X GET "${API_URL}/api/v1/cep/01310100" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  | jq .

# Listar transportadoras
curl -s -X GET "${API_URL}/api/v1/transportadoras" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  | jq .
```

### monitor-envio.sh
```bash
#!/bin/bash
# Monitorar status de envio

ENVIO_ID="$1"

curl -s -X GET "${API_URL}/api/v1/envios/${ENVIO_ID}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  | jq '.status, .historico[]'
```

## 8. Boas Práticas

1. **Cache de CEPs:** Armazene resultados de consulta de CEP por 24h
2. **Tratamento de Erros:** Sempre verifique códigos de erro HTTP
3. **Rate Limiting:** Respeite limites de 100 requisições/minuto
4. **Logging:** Registre todas as requisições para debugging
5. **Retry:** Implemente retry com backoff exponencial para erros transitórios
6. **Validação:** Valide dados antes de enviar para a API