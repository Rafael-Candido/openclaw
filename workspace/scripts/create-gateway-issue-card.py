#!/usr/bin/env python3
import json
import os
import sys
import requests
from datetime import datetime

# Carregar API key
api_key = os.getenv('NOTION_PERSONAL_API_KEY')
if not api_key:
    print('{"error": "API key NOTION_PERSONAL_API_KEY not found"}')
    sys.exit(1)

# Headers
headers = {
    'Authorization': f'Bearer {api_key}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

# Dados do novo card
card_data = {
    'parent': {'database_id': 'bfcbe7a7a3a745489e605e0762af12a9'},
    'properties': {
        'Name': {
            'title': [
                {
                    'type': 'text',
                    'text': {'content': '[Governança] Problema recorrente: Gateway travado para operações cron'}
                }
            ]
        },
        'Status': {
            'select': {'name': 'Aguardando'}
        },
        'Tipo': {
            'select': {'name': 'OpenClaw'}
        },
        'Agente': {
            'select': {'name': 'Diretor Pessoal'}
        },
        'Prioridade': {
            'select': {'name': 'Alta'}
        }
    },
    'children': [
        {
            'object': 'block',
            'type': 'paragraph',
            'paragraph': {
                'rich_text': [{
                    'type': 'text',
                    'text': {
                        'content': '🔴 **Problema recorrente identificado pela Governança**\n\nGateway está travado para operações cron desde ~22:00. Todas as tentativas de listar/executar crons resultam em timeout de 60s, mesmo com gateway respondendo na porta 18789.'
                    }
                }]
            }
        },
        {
            'object': 'block',
            'type': 'bulleted_list_item',
            'bulleted_list_item': {
                'rich_text': [{
                    'type': 'text',
                    'text': {
                        'content': '2026-02-20 22:00-23:04: Gateway timeout persistente para operações cron'
                    }
                }]
            }
        },
        {
            'object': 'block',
            'type': 'bulleted_list_item',
            'bulleted_list_item': {
                'rich_text': [{
                    'type': 'text',
                    'text': {
                        'content': 'Sintoma: cron list/run retorna "gateway timeout after 60000ms"'
                    }
                }]
            }
        },
        {
            'object': 'block',
            'type': 'bulleted_list_item',
            'bulleted_list_item': {
                'rich_text': [{
                    'type': 'text',
                    'text': {
                        'content': 'Gateway responde na porta 18789 (interface web funciona)'
                    }
                }]
            }
        },
        {
            'object': 'block',
            'type': 'bulleted_list_item',
            'bulleted_list_item': {
                'rich_text': [{
                    'type': 'text',
                    'text': {
                        'content': 'SIGUSR1 enviado sem efeito (restart desabilitado no config)'
                    }
                }]
            }
        },
        {
            'object': 'block',
            'type': 'bulleted_list_item',
            'bulleted_list_item': {
                'rich_text': [{
                    'type': 'text',
                    'text': {
                        'content': 'Impacto: Engenheiro de Prompt, Mail-Person, Mail-Pro não conseguem executar via cron'
                    }
                }]
            }
        },
        {
            'object': 'block',
            'type': 'paragraph',
            'paragraph': {
                'rich_text': [{
                    'type': 'text',
                    'text': {
                        'content': '**Causa provável:** Deadlock ou resource exhaustion no módulo de cron do gateway.'
                    }
                }]
            }
        },
        {
            'object': 'block',
            'type': 'paragraph',
            'paragraph': {
                'rich_text': [{
                    'type': 'text',
                    'text': {
                        'content': '**Sugestão de fix:**\n1. Habilitar restart no config (commands.restart=true)\n2. Implementar health check mais agressivo para módulo cron\n3. Criar fallback manual para operações críticas quando API falhar\n4. Monitorar memory/CPU do processo gateway'
                    }
                }]
            }
        }
    ]
}

try:
    response = requests.post(
        'https://api.notion.com/v1/pages',
        headers=headers,
        json=card_data
    )
    response.raise_for_status()
    
    card = response.json()
    
    print(json.dumps({
        'success': True,
        'message': 'Card de problema do gateway criado em Aguardando',
        'card_id': card.get('id'),
        'card_url': card.get('url', ''),
        'title': '[Governança] Problema recorrente: Gateway travado para operações cron'
    }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')