#!/usr/bin/env python3
"""
Script para consultar o Notion Canper como Diretor de Negócios.
"""
import os
import json
import requests
from datetime import datetime

# Configurações
DATABASE_ID = "14abf9163c9680ff822bc2e32f6bec4b"
API_KEY = os.getenv("NOTION_CANPER_API_KEY")

if not API_KEY:
    print("ERRO: NOTION_CANPER_API_KEY não configurada")
    exit(1)

headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json"
}

def query_database(filter_obj=None):
    """Consulta o database do Notion Canper"""
    url = f"https://api.notion.com/v1/databases/{DATABASE_ID}/query"
    
    payload = {}
    if filter_obj:
        payload["filter"] = filter_obj
    
    response = requests.post(url, headers=headers, json=payload)
    
    if response.status_code != 200:
        print(f"ERRO na consulta: {response.status_code}")
        print(response.text)
        return None
    
    return response.json()

def get_cards_aguardando():
    """Busca cards em Aguardando do tipo OpenClaw"""
    filter_obj = {
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
    
    return query_database(filter_obj)

def get_cards_priorizado():
    """Busca cards em Priorizado do tipo OpenClaw"""
    filter_obj = {
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
    
    return query_database(filter_obj)

def update_card(card_id, properties):
    """Atualiza um card no Notion"""
    url = f"https://api.notion.com/v1/pages/{card_id}"
    
    payload = {
        "properties": properties
    }
    
    response = requests.patch(url, headers=headers, json=payload)
    
    if response.status_code != 200:
        print(f"ERRO ao atualizar card {card_id}: {response.status_code}")
        print(response.text)
        return False
    
    return True

def main():
    print("=== Diretor de Negócios - Varredura Notion Canper ===")
    print(f"Data/hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # 1. Buscar cards em Aguardando
    print("1. Buscando cards em 'Aguardando' do tipo 'OpenClaw'...")
    result = get_cards_aguardando()
    
    if not result:
        print("   Nenhum card encontrado ou erro na consulta.")
        return
    
    cards = result.get("results", [])
    print(f"   Encontrados {len(cards)} card(s) em Aguardando.")
    
    if not cards:
        print("\nNenhuma ação necessária.")
        return
    
    # 2. Para cada card em Aguardando, verificar duplicidade em Priorizado
    print("\n2. Verificando duplicidade com cards em 'Priorizado'...")
    priorizado_cards = get_cards_priorizado()
    priorizado_list = priorizado_cards.get("results", []) if priorizado_cards else []
    
    # Criar mapa de duplicidade (título + agente)
    dup_map = {}
    for card in priorizado_list:
        title = card.get("properties", {}).get("Name", {}).get("title", [{}])[0].get("text", {}).get("content", "")
        agent = card.get("properties", {}).get("Agente", {}).get("select", {}).get("name", "")
        key = f"{title}|{agent}"
        dup_map[key] = True
    
    cards_to_process = []
    
    for card in cards:
        card_id = card["id"]
        title = card.get("properties", {}).get("Name", {}).get("title", [{}])[0].get("text", {}).get("content", "Sem título")
        current_agent = card.get("properties", {}).get("Agente", {}).get("select", {}).get("name", "")
        
        print(f"\n   Card: {title}")
        print(f"   ID: {card_id}")
        print(f"   Agente atual: {current_agent}")
        
        # Verificar duplicidade
        key = f"{title}|{current_agent}"
        if key in dup_map:
            print(f"   ⚠️  DUPLICADO: Já existe em Priorizado com mesmo título e agente.")
            print(f"   Ação: Aguardar próximo ciclo.")
            continue
        
        cards_to_process.append(card)
        print(f"   ✅ OK para processar.")
    
    if not cards_to_process:
        print("\nNenhum card para processar (todos duplicados ou sem cards).")
        return
    
    print(f"\n3. Processando {len(cards_to_process)} card(s)...")
    
    for card in cards_to_process:
        card_id = card["id"]
        title = card.get("properties", {}).get("Name", {}).get("title", [{}])[0].get("text", {}).get("content", "Sem título")
        description = card.get("properties", {}).get("Descrição", {}).get("rich_text", [{}])[0].get("text", {}).get("content", "")
        
        print(f"\n   📋 Processando: {title}")
        
        # Definir agente temporário (Tech enquanto não há especialistas de negócios)
        new_agent = "Tech"
        
        # Atualizar card para Priorizado
        properties = {
            "Status": {"select": {"name": "Priorizado"}},
            "Agente": {"select": {"name": new_agent}}
        }
        
        # Adicionar solicitante se não existir
        solicitante = card.get("properties", {}).get("Solicitante", {}).get("people", [])
        if not solicitante:
            # Tentar definir Rafael Pereira (pendente de ID correto)
            # Por enquanto, deixamos sem solicitante
            pass
        
        print(f"   Atualizando: Status → Priorizado, Agente → {new_agent}")
        
        if update_card(card_id, properties):
            print(f"   ✅ Card atualizado com sucesso.")
            
            # Adicionar comentário de atualização
            # (Nota: API de comentários requer bloco de discussão)
            print(f"   📝 Descrição atual: {description[:100]}...")
            print(f"   💡 Ação: Diretor deve escrever descrição técnica completa.")
        else:
            print(f"   ❌ Falha ao atualizar card.")
    
    print("\n=== Varredura concluída ===")

if __name__ == "__main__":
    main()