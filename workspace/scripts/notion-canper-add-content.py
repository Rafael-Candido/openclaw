#!/usr/bin/env python3
"""
Script para adicionar conteúdo (descrição técnica) a um card no Notion Canper.
"""
import os
import json
import requests
from datetime import datetime

# Configurações
CARD_ID = "30dbf9163c968023bfbef33e864b9843"  # ID do card (sem hífens)
API_KEY = os.getenv("NOTION_CANPER_API_KEY")

if not API_KEY:
    print("ERRO: NOTION_CANPER_API_KEY não configurada")
    exit(1)

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json"
}

def add_content_to_card(card_id, content_blocks):
    """Adiciona blocos de conteúdo a um card"""
    url = f"https://api.notion.com/v1/blocks/{card_id}/children"
    
    payload = {
        "children": content_blocks
    }
    
    response = requests.patch(url, headers=headers, json=payload)
    
    if response.status_code != 200:
        print(f"ERRO ao adicionar conteúdo: {response.status_code}")
        print(response.text)
        return False
    
    return True

def main():
    print("=== Diretor de Negócios - Adicionar Conteúdo Técnico ===")
    print(f"Data/hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Card ID: {CARD_ID}")
    print()
    
    # Conteúdo técnico completo para o especialista Tech
    content_blocks = [
        {
            "object": "block",
            "type": "heading_2",
            "heading_2": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "📋 Instruções Técnicas para Execução"
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
                            "content": "Card priorizado pelo Diretor de Negócios. Especialista Tech deve executar a pesquisa conforme instruções abaixo."
                        }
                    }
                ]
            }
        },
        {
            "object": "block",
            "type": "heading_3",
            "heading_3": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "🎯 Contexto"
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
                            "content": "Pesquisa de mercado para identificar as maiores empresas B2B do Brasil com modelo de negócio semelhante ao da SmartEnvios (logística, e-commerce, SaaS)."
                        }
                    }
                ]
            }
        },
        {
            "object": "block",
            "type": "heading_3",
            "heading_3": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "🚀 O que fazer (passos)"
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
                            "content": "Pesquisar listas de maiores empresas B2B do Brasil por receita/faturamento (ex: Exame Melhores e Maiores, Valor 1000, Forbes)"
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
                            "content": "Filtrar empresas com modelo semelhante a SmartEnvios: logística, tecnologia para e-commerce, SaaS, marketplaces B2B"
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
                            "content": "Coletar informações principais: nome, faturamento aproximado, segmento, modelo de negócio, concorrentes diretos"
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
                            "content": "Analisar concorrência direta (ex: Frete.com, Melhor Envio, Jadlog) e indireta (ex: Totvs, TOTVS Protheus)"
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
                            "content": "Identificar oportunidades de mercado e diferenciais competitivos da SmartEnvios"
                        }
                    }
                ]
            }
        },
        {
            "object": "block",
            "type": "heading_3",
            "heading_3": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "✅ Critérios de conclusão"
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
                            "content": "Lista com pelo menos 10 empresas B2B brasileiras relevantes"
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
                            "content": "Análise comparativa com SmartEnvios (semelhanças/diferenças)"
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
                            "content": "Identificação de 3-5 oportunidades de mercado"
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
                            "content": "Documento estruturado com insights acionáveis"
                        }
                    }
                ]
            }
        },
        {
            "object": "block",
            "type": "heading_3",
            "heading_3": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "🔧 Recursos"
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
                            "content": "• Skill: notion-canper (este workspace)"
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
                            "content": "• Database ID: 14abf9163c9680ff822bc2e32f6bec4b"
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
                            "content": "• Ferramentas: web_search, web_fetch para pesquisa"
                        }
                    }
                ]
            }
        },
        {
            "object": "block",
            "type": "heading_3",
            "heading_3": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "📝 Checklist obrigatório"
                        }
                    }
                ]
            }
        },
        {
            "object": "block",
            "type": "to_do",
            "to_do": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "Status inicial em Priorizado"
                        }
                    }
                ],
                "checked": True
            }
        },
        {
            "object": "block",
            "type": "to_do",
            "to_do": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "Agente correto (Tech temporário)"
                        }
                    }
                ],
                "checked": True
            }
        },
        {
            "object": "block",
            "type": "to_do",
            "to_do": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "Objetivo e escopo explícitos"
                        }
                    }
                ],
                "checked": True
            }
        },
        {
            "object": "block",
            "type": "to_do",
            "to_do": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "Passos executáveis sem ambiguidade"
                        }
                    }
                ],
                "checked": False
            }
        },
        {
            "object": "block",
            "type": "to_do",
            "to_do": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "Fontes de pesquisa confiáveis"
                        }
                    }
                ],
                "checked": False
            }
        },
        {
            "object": "block",
            "type": "to_do",
            "to_do": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": "Análise estruturada e insights acionáveis"
                        }
                    }
                ],
                "checked": False
            }
        },
        {
            "object": "block",
            "type": "divider",
            "divider": {}
        },
        {
            "object": "block",
            "type": "paragraph",
            "paragraph": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": f"📅 Atualizado por Diretor de Negócios em {datetime.now().strftime('%d/%m/%Y %H:%M')}"
                        }
                    }
                ]
            }
        }
    ]
    
    print("Adicionando conteúdo técnico ao card...")
    
    if add_content_to_card(CARD_ID, content_blocks):
        print("✅ Conteúdo técnico adicionado com sucesso!")
        print("\nResumo do conteúdo adicionado:")
        print("- Instruções técnicas completas para execução")
        print("- Contexto, passos, critérios de conclusão")
        print("- Recursos e checklist obrigatório")
        print("- Total de blocos: 27")
    else:
        print("❌ Falha ao adicionar conteúdo técnico.")
    
    print(f"\n=== Concluído ===")

if __name__ == "__main__":
    main()