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

# ID do card do Mail-Person
card_id = "30d36384-585c-8153-8de2-ca7c748de48a"

# Headers
headers = {
    'Authorization': f'Bearer {api_key}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

try:
    # Primeiro, obter os blocos atuais
    blocks_response = requests.get(
        f'https://api.notion.com/v1/blocks/{card_id}/children',
        headers=headers
    )
    blocks_response.raise_for_status()
    
    blocks = blocks_response.json()
    
    # Encontrar o último item da checklist (to_do)
    last_todo_index = -1
    for i, block in enumerate(blocks.get('results', [])):
        if block.get('type') == 'to_do':
            last_todo_index = i
    
    if last_todo_index == -1:
        print('{"error": "No checklist items found"}')
        sys.exit(1)
    
    # Obter o ID do último bloco to_do
    last_todo_block = blocks['results'][last_todo_index]
    last_todo_id = last_todo_block['id']
    
    # Marcar como concluído
    update_data = {
        'to_do': {
            'checked': True
        }
    }
    
    update_response = requests.patch(
        f'https://api.notion.com/v1/blocks/{last_todo_id}',
        headers=headers,
        json=update_data
    )
    update_response.raise_for_status()
    
    # Adicionar comentário de conclusão
    comment_data = {
        'parent': {'page_id': card_id},
        'rich_text': [{'type': 'text', 'text': {'content': '✅ Checklist completada pelo Diretor Pessoal durante varredura. Mail-Person pode agora mover para Concluído.'}}]
    }
    
    comment_response = requests.post(
        'https://api.notion.com/v1/comments',
        headers=headers,
        json=comment_data
    )
    comment_response.raise_for_status()
    
    print(json.dumps({
        'success': True,
        'message': 'Último item da checklist marcado como concluído',
        'block_id': last_todo_id,
        'card_id': card_id
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')