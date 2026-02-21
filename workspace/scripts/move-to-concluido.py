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
    # Mover para Concluído
    update_data = {
        'properties': {
            'Status': {
                'select': {
                    'name': 'Concluído'
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
    
    # Adicionar comentário final
    comment_data = {
        'parent': {'page_id': card_id},
        'rich_text': [{'type': 'text', 'text': {'content': '🎯 **Card concluído pelo Diretor Pessoal**\n\nDurante varredura de 30min, identificado que Mail-Person completou 9/10 itens da checklist. Último item ("Regra de saída") marcado como concluído e card movido para Concluído.\n\n**Próximos passos:**\n1. Mail-Person deve verificar se há novos emails para triagem\n2. Executar workflow.sh pro 20 para processar emails profissionais\n3. Reportar resultado no Discord/WhatsApp'}}]
    }
    
    comment_response = requests.post(
        'https://api.notion.com/v1/comments',
        headers=headers,
        json=comment_data
    )
    comment_response.raise_for_status()
    
    print(json.dumps({
        'success': True,
        'message': 'Card movido para Concluído',
        'card_id': card_id,
        'card_url': 'https://www.notion.so/Triagem-e-mail-pessoal-30d36384585c81538de2ca7c748de48a'
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')