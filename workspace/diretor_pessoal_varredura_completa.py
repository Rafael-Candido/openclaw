#!/usr/bin/env python3
"""
Script de varredura do Diretor Pessoal
Executa a função padrão: captar cards OpenClaw em Aguardando, normalizar para Priorizado
com agente correto e adicionar descrição técnica.
"""
import os
import requests
import json
import sys
from datetime import datetime

# Database ID do Notion Personal
DATABASE_ID = "bfcbe7a7a3a745489e605e0762af12a9"

# API Key do Notion Personal
NOTION_API_KEY = os.environ.get("NOTION_PERSONAL_API_KEY")
if not NOTION_API_KEY:
    print("ERRO: NOTION_PERSONAL_API_KEY não encontrada no ambiente")
    sys.exit(1)

# Headers para a API
headers = {
    "Authorization": f"Bearer {NOTION_API_KEY}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json"
}

def log(message, level="INFO"):
    """Função de logging com timestamp"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}] [{level}] {message}")

def query_notion_with_retry(filter_data, description, max_retries=2):
    """
    Consulta o Notion com tratamento de erros e retry para validation_error
    """
    query = {
        "filter": filter_data,
        "sorts": [
            {
                "property": "Date Created",
                "direction": "ascending"
            }
        ]
    }
    
    for attempt in range(max_retries):
        try:
            response = requests.post(
                f"https://api.notion.com/v1/databases/{DATABASE_ID}/query",
                headers=headers,
                json=query,
                timeout=10
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                error_data = response.json()
                error_code = error_data.get("code", "")
                
                if error_code == "validation_error" and attempt < max_retries - 1:
                    log(f"Validation_error na {description} (tentativa {attempt + 1}/{max_retries}), ajustando filtro...", "WARN")
                    # Tentar ajustar o filtro - simplificar para apenas Status
                    if "and" in filter_data and len(filter_data["and"]) > 1:
                        # Tentar apenas com Status primeiro
                        simple_filter = {
                            "property": "Status",
                            "select": {"equals": filter_data["and"][0]["select"]["equals"]}
                        }
                        query["filter"] = simple_filter
                        continue
                else:
                    log(f"ERRO {response.status_code} na {description}: {response.text}", "ERROR")
                    return None
                    
        except Exception as e:
            log(f"Exceção na {description}: {str(e)}", "ERROR")
            if attempt == max_retries - 1:
                return None
    
    return None

def get_cards_aguardando():
    """Obtém cards OpenClaw em Aguardando"""
    log("Consultando cards OpenClaw em Aguardando...")
    
    filter_data = {
        "and": [
            {
                "property": "Status",
                "select": {
                    "equals": "Aguardando"
                }
            },
            {
                "property": "Tipo",
                "select": {
                    "equals": "OpenClaw"
                }
            }
        ]
    }
    
    result = query_notion_with_retry(filter_data, "consulta Aguardando")
    if result is None:
        log("Falha na consulta de cards Aguardando", "ERROR")
        return []
    
    cards = result.get("results", [])
    log(f"Encontrados {len(cards)} cards em Aguardando (Tipo: OpenClaw)")
    return cards

def get_cards_priorizado():
    """Obtém cards OpenClaw em Priorizado para verificação de duplicação"""
    log("Consultando cards em Priorizado para verificação de duplicação...")
    
    filter_data = {
        "and": [
            {
                "property": "Status",
                "select": {
                    "equals": "Priorizado"
                }
            },
            {
                "property": "Tipo",
                "select": {
                    "equals": "OpenClaw"
                }
            }
        ]
    }
    
    result = query_notion_with_retry(filter_data, "consulta Priorizado")
    if result is None:
        log("Falha na consulta de cards Priorizado", "ERROR")
        return []
    
    cards = result.get("results", [])
    log(f"Encontrados {len(cards)} cards em Priorizado (Tipo: OpenClaw)")
    return cards

def extract_card_info(card):
    """Extrai informações do card"""
    props = card.get("properties", {})
    
    # Título
    title_prop = props.get("Name", {}).get("title", [])
    title = "".join([t.get("plain_text", "") for t in title_prop]) if title_prop else "Sem título"
    
    # Agente atual
    agent_prop = props.get("Agente", {}).get("select", {})
    current_agent = agent_prop.get("name", "Não definido") if agent_prop else "Não definido"
    
    # Page ID
    page_id = card.get("id", "")
    
    # Data de criação
    created_time = card.get("created_time", "")
    
    return title, current_agent, page_id, created_time

def determine_agent(title, current_agent):
    """
    Determina o agente correto baseado no título
    Regras:
    - E-mail pessoal -> Mail-Person
    - Manutenção OpenClaw -> Engenheiro de Prompt
    - NUNCA Diretor Pessoal após triagem
    """
    title_lower = title.lower()
    
    # Se já for um especialista válido, manter
    if current_agent in ["Mail-Person", "Engenheiro de Prompt"]:
        return current_agent
    
    # E-mail pessoal
    email_keywords = ["e-mail", "email", "gmail", "caixa", "inbox", "mail", "correio"]
    if any(keyword in title_lower for keyword in email_keywords):
        return "Mail-Person"
    
    # Manutenção OpenClaw
    openclaw_keywords = ["openclaw", "agente", "prompt", "einstein", "governança", 
                         "cron", "config", "setup", "documentação", "knowledge",
                         "manutenção", "manutencao", "problema", "erro", "bug"]
    if any(keyword in title_lower for keyword in openclaw_keywords):
        return "Engenheiro de Prompt"
    
    # Padrão: Engenheiro de Prompt (mais versátil)
    return "Engenheiro de Prompt"

def is_duplicate(title, agent, priorizado_cards):
    """Verifica se já existe card com mesmo título e mesmo agente em Priorizado"""
    for card in priorizado_cards:
        card_title, card_agent, _, _ = extract_card_info(card)
        
        # Comparação case-insensitive
        if title.lower() == card_title.lower() and agent == card_agent:
            return True
    
    return False

def update_card_to_priorizado(page_id, title, agent):
    """Atualiza card para Priorizado com agente correto"""
    log(f"Atualizando card '{title}' para Priorizado (Agente: {agent})...")
    
    update_data = {
        "properties": {
            "Status": {
                "select": {
                    "name": "Priorizado"
                }
            },
            "Agente": {
                "select": {
                    "name": agent
                }
            },
            "Tipo": {
                "select": {
                    "name": "OpenClaw"
                }
            }
        }
    }
    
    try:
        response = requests.patch(
            f"https://api.notion.com/v1/pages/{page_id}",
            headers=headers,
            json=update_data,
            timeout=10
        )
        
        if response.status_code == 200:
            log(f"Card '{title}' atualizado para Priorizado com Agente={agent}", "SUCCESS")
            return True
        else:
            log(f"ERRO {response.status_code} ao atualizar card '{title}': {response.text}", "ERROR")
            return False
            
    except Exception as e:
        log(f"Exceção ao atualizar card '{title}': {str(e)}", "ERROR")
        return False

def add_technical_description(page_id, title, agent):
    """Adiciona descrição técnica completa ao card"""
    log(f"Adicionando descrição técnica ao card '{title}'...")
    
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    
    # Descrição baseada no agente
    if agent == "Mail-Person":
        description_blocks = [
            {
                "object": "block",
                "type": "heading_2",
                "heading_2": {
                    "rich_text": [{"type": "text", "text": {"content": "Contexto"}}]
                }
            },
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": f"Tarefa de triagem de e-mail pessoal. Priorizado pelo Diretor Pessoal em {now}."
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "heading_2",
                "heading_2": {
                    "rich_text": [{"type": "text", "text": {"content": "O que fazer (passos)"}}]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Conectar à caixa de e-mail pessoal (rafael.silva.pereira10@gmail.com) usando credenciais Gmail pessoal"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Buscar e-mails não lidos (limite: últimos 100 e-mails)"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Ler cada e-mail com contexto completo da conversa (thread/histórico)"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Classificar por relevância pessoal usando análise inteligente (filtra auto-replies, prioriza menções diretas)"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Criar rascunhos contextualizados apenas para e-mails importantes (score >= 50)"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Aplicar labels com reuso inteligente (criar apenas se não existir): Mail-Person-Aguardando, Mail-Person-BaixoValor, Mail-Person-Importante"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Arquivar e-mails após processamento"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "heading_2",
                "heading_2": {
                    "rich_text": [{"type": "text", "text": {"content": "Critérios de conclusão"}}]
                }
            },
            {
                "object": "block",
                "type": "bulleted_list_item",
                "bulleted_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Todos os e-mails não lidos triados e classificados"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "bulleted_list_item",
                "bulleted_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Rascunhos criados para e-mails importantes (score >= 50)"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "bulleted_list_item",
                "bulleted_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Labels aplicados conforme necessidade"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "bulleted_list_item",
                "bulleted_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "E-mails processados arquivados"
                            }
                        }
                    ]
                }
            }
        ]
    else:  # Engenheiro de Prompt
        description_blocks = [
            {
                "object": "block",
                "type": "heading_2",
                "heading_2": {
                    "rich_text": [{"type": "text", "text": {"content": "Contexto"}}]
                }
            },
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": f"Tarefa de manutenção ou evolução da estrutura OpenClaw. Priorizado pelo Diretor Pessoal em {now}."
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "heading_2",
                "heading_2": {
                    "rich_text": [{"type": "text", "text": {"content": "O que fazer (passos)"}}]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Analisar a demanda específica do card"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Consultar documentação relevante (AGENTS.md, FLUXO_AGENTES.md, KNOWLEDGE.md)"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Executar as ações necessárias para manutenção ou evolução"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Documentar alterações e aprendizados"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "numbered_ list_item",
                "numbered_list_item": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Testar a implementação"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "heading_2",
                "heading_2": {
                    "rich_text": [{"type": "text", "text": {"content": "Recursos"}}]
                }
            },
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Workspace: /var/www/openclaw/workspace"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Documentação: AGENTS.md, FLUXO_AGENTES.md, KNOWLEDGE.md, TOOLS.md"
                            }
                        }
                    ]
                }
            },
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": "Scripts: scripts/ directory"
                            }
                        }
                    ]
                }
            }
        ]
    
    # Adicionar blocos à página
    try:
