#!/usr/bin/env python3
import json
import os
import sys
import requests

# Carregar API key
api_key = os.getenv('NOTION_PERSONAL_API_KEY')
if not api_key:
    print('{"error": "API key NOTION_PERSONAL_API_KEY not found"}')
    sys.exit(1)

# ID do card travado
card_id = "30d36384-585c-8159-b856-e6b31fbbca96"

# Headers
headers = {
    'Authorization': f'Bearer {api_key}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

# Mensagem do comentário
comment_text = """📋 **Varredura Diretor Pessoal - 2026-02-20 21:58**

**Status:** Card identificado como travado há 7.5 horas em Priorizado.

**Análise:**
- Problema recorrente do Mail-Pro (3ª ocorrência)
- Acumulação de contexto na sessão (346+ mensagens)
- Rate limits da Gmail API
- Cron a cada 10min pode ser muito agressivo

**Ação necessária:** Engenheiro de Prompt precisa implementar:
1. Cleanup proativo de sessão (não apenas quando trava)
2. Ajuste de frequência do cron Mail-Pro
3. Rate limiting inteligente para Gmail API

**Próxima verificação:** 30 minutos"""

try:
    # Adicionar comentário
    comment_data = {
        'parent': {'page_id': card_id},
        'rich_text': [{'type': 'text', 'text': {'content': comment_text}}]
    }
    
    response = requests.post(
        'https://api.notion.com/v1/comments',
        headers=headers,
        json=comment_data
    )
    response.raise_for_status()
    
    print(json.dumps({
        'success': True,
        'message': 'Comentário adicionado com sucesso',
        'card_id': card_id
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')