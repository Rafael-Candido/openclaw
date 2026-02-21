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

# ID do novo card
card_id = "30e36384-585c-81d2-b95e-c175a95f5407"

# Headers
headers = {
    'Authorization': f'Bearer {api_key}',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json'
}

try:
    # 1. Primeiro verificar se já existe card similar em Priorizado
    # Consultar cards Mail-Person em Priorizado
    filter_data = {
        'filter': {
            'and': [
                {'property': 'Status', 'select': {'equals': 'Priorizado'}},
                {'property': 'Agente', 'select': {'equals': 'Mail-Person'}},
                {'property': 'Tipo', 'select': {'equals': 'OpenClaw'}}
            ]
        }
    }
    
    response = requests.post(
        f'https://api.notion.com/v1/databases/bfcbe7a7a3a745489e605e0762af12a9/query',
        headers=headers,
        json=filter_data
    )
    response.raise_for_status()
    
    existing_cards = response.json().get('results', [])
    
    if existing_cards:
        print(json.dumps({
            'warning': True,
            'message': 'Já existe card Mail-Person em Priorizado. Aguardando execução.',
            'existing_cards_count': len(existing_cards),
            'card_ids': [card.get('id') for card in existing_cards]
        }, indent=2))
    else:
        # 2. Mover para Priorizado
        update_data = {
            'properties': {
                'Status': {
                    'select': {
                        'name': 'Priorizado'
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
        
        # 3. Adicionar descrição técnica/funcional completa
        # Primeiro, obter os blocos atuais
        blocks_response = requests.get(
            f'https://api.notion.com/v1/blocks/{card_id}/children',
            headers=headers
        )
        blocks_response.raise_for_status()
        
        blocks = blocks_response.json()
        
        # Verificar se já tem conteúdo
        has_content = len(blocks.get('results', [])) > 0
        
        if not has_content:
            # Adicionar descrição técnica
            descricao_data = {
                'children': [
                    {
                        'object': 'block',
                        'type': 'paragraph',
                        'paragraph': {
                            'rich_text': [{
                                'type': 'text',
                                'text': {
                                    'content': '📧 **Rotina periódica de triagem da caixa de e-mail pessoal**\n\nCriado automaticamente pelo Presidente para garantir processamento contínuo de emails pessoais.'
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
                                    'content': '**Objetivo:** Processar emails não lidos da caixa pessoal (rafael.silva.pereira10@gmail.com) com triagem inteligente, aplicação de labels, arquivamento e criação de rascunhos quando necessário.'
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
                                    'content': '**Escopo:**\n- Ler até 100 emails não lidos com histórico de thread\n- Triar por relevância usando workflow.sh (análise inteligente)\n- Aplicar/reusar labels: Mail-Person-Aguardando, Mail-Person-BaixoValor, Mail-Person-Importante\n- Arquivar emails processados\n- Criar rascunhos contextualizados para emails importantes (score >= 50)'
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
                                    'content': '**Critérios de conclusão:**\n- Executar /var/www/openclaw/workspace/scripts/gmail/workflow.sh personal 100\n- Registrar resultado em comentário nativo no card\n- Mover card para Concluído\n- Comunicar resultado no Discord/WhatsApp se houver emails importantes'
                                }
                            }]
                        }
                    },
                    {
                        'object': 'block',
                        'type': 'to_do',
                        'to_do': {
                            'rich_text': [{
                                'type': 'text',
                                'text': {
                                    'content': 'Status inicial em Priorizado'
                                }
                            }],
                            'checked': True
                        }
                    },
                    {
                        'object': 'block',
                        'type': 'to_do',
                        'to_do': {
                            'rich_text': [{
                                'type': 'text',
                                'text': {
                                    'content': 'Agente correto (Mail-Person)'
                                }
                            }],
                            'checked': True
                        }
                    },
                    {
                        'object': 'block',
                        'type': 'to_do',
                        'to_do': {
                            'rich_text': [{
                                'type': 'text',
                                'text': {
                                    'content': 'Objetivo e escopo explícitos'
                                }
                            }],
                            'checked': True
                        }
                    },
                    {
                        'object': 'block',
                        'type': 'to_do',
                        'to_do': {
                            'rich_text': [{
                                'type': 'text',
                                'text': {
                                    'content': 'Passos executáveis sem ambiguidade'
                                }
                            }],
                            'checked': True
                        }
                    },
                    {
                        'object': 'block',
                        'type': 'to_do',
                        'to_do': {
                            'rich_text': [{
                                'type': 'text',
                                'text': {
                                    'content': 'Regra de labels (reusar antes de criar)'
                                }
                            }],
                            'checked': True
                        }
                    },
                    {
                        'object': 'block',
                        'type': 'to_do',
                        'to_do': {
                            'rich_text': [{
                                'type': 'text',
                                'text': {
                                    'content': 'Regra de saída (comunicar no Discord/WhatsApp + mover para Concluído)'
                                }
                            }],
                            'checked': False
                        }
                    }
                ]
            }
            
            descricao_response = requests.patch(
                f'https://api.notion.com/v1/blocks/{card_id}/children',
                headers=headers,
                json=descricao_data
            )
            descricao_response.raise_for_status()
        
        print(json.dumps({
            'success': True,
            'message': 'Card movido para Priorizado com descrição técnica completa',
            'card_id': card_id,
            'card_url': 'https://www.notion.so/Rotina-Mail-Person-Triagem-e-rascunhos-de-e-mail-pessoal-30e36384585c81d2b95ec175a95f5407',
            'has_existing_cards': False,
            'description_added': not has_content
        }, indent=2))
    
except requests.exceptions.RequestException as e:
    print(f'{{"error": "Request failed: {str(e)}"}}')
except Exception as e:
    print(f'{{"error": "{str(e)}"}}')