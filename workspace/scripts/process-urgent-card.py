#!/usr/bin/env python3
import json
import os
import sys
import requests
from datetime import datetime, timezone

# Carregar API key
api_key = os.getenv('NOTION_PERSONAL_API_KEY')
if not api_key:
    print('{"error": "API key NOTION_PERSONAL_API_KEY not found"}')
    sys.exit(1)

# ID do card mais urgente
card_id = "30d36384-585c-81c2-adf0-f9ad4e6ba1da"  # [URGENTE] Mail-Pro travado

# Headers
headers = {
    'Authorization': f'Bearer {api_key}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

try:
    # 1. Mover para Em andamento
    update_data = {
        'properties': {
            'Status': {
                'select': {
                    'name': 'Em andamento'
                }
            }
        }
    }
    
    update_response = requests.patch(
        f'https://api.notion.com/v1/pages/{card_id}',
        headers=headers,
        json=update_data
    )
    update_response.raise_for_status()
    
    # 2. Adicionar comentário de início
    comment_data = {
        'parent': {'page_id': card_id},
        'rich_text': [{'type': 'text', 'text': {'content': '🚨 **Execução forçada pelo Diretor Pessoal**\n\nGateway travado para crons. Executando ação manual para resolver problema do Mail-Pro.\n\n**Problema:** Mail-Pro travando após acumular contexto (346+ mensagens), rate limits da Gmail API.\n\n**Ação:** Ajustar frequência do cron Mail-Pro de 10min para 30min e implementar cleanup proativo.'}}]
    }
    
    comment_response = requests.post(
        'https://api.notion.com/v1/comments',
        headers=headers,
        json=comment_data
    )
    comment_response.raise_for_status()
    
    print(json.dumps({
        'success': True,
        'message': 'Card movido para Em andamento',
        'card_id': card_id,
        'step': '1/3 - Início da execução'
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')