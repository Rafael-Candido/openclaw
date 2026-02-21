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

# ID do card do gateway
card_id = "30e36384-585c-81bb-9636-c77bcb1fc1df"

# Headers
headers = {
    'Authorization': f'Bearer {api_key}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

try:
    # Mover para Priorizado e atribuir ao Engenheiro de Prompt
    update_data = {
        'properties': {
            'Status': {
                'select': {
                    'name': 'Priorizado'
                }
            },
            'Agente': {
                'select': {
                    'name': 'Engenheiro de Prompt'
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
    
    # Adicionar comentário
    comment_data = {
        'parent': {'page_id': card_id},
        'rich_text': [{'type': 'text', 'text': {'content': '🎯 **Priorizado pelo Diretor Pessoal**\n\nCard movido para Priorizado e atribuído ao Engenheiro de Prompt.\n\n**Contexto:** Gateway travado para operações cron desde ~22:00, impedindo execução automática de Mail-Person, Mail-Pro e Engenheiro de Prompt.\n\n**Ação necessária:** Habilitar restart no config (commands.restart=true) e implementar fallback para quando módulo cron travar.'}}]
    }
    
    comment_response = requests.post(
        'https://api.notion.com/v1/comments',
        headers=headers,
        json=comment_data
    )
    comment_response.raise_for_status()
    
    print(json.dumps({
        'success': True,
        'message': 'Card do gateway movido para Priorizado (Engenheiro de Prompt)',
        'card_id': card_id,
        'card_url': 'https://www.notion.so/Governan-a-Problema-recorrente-Gateway-travado-para-opera-es-cron-30e36384585c81bb9636c77bcb1fc1df'
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')