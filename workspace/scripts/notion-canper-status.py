#!/usr/bin/env python3
"""
Script para verificar status geral do Notion Canper.
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

def query_all_cards():
    """Consulta todos os cards do database"""
    url = f"https://api.notion.com/v1/databases/{DATABASE_ID}/query"
    
    all_results = []
    has_more = True
    next_cursor = None
    
    while has_more:
        payload = {}
        if next_cursor:
            payload["start_cursor"] = next_cursor
        
        response = requests.post(url, headers=headers, json=payload)
        
        if response.status_code != 200:
            print(f"ERRO na consulta: {response.status_code}")
            print(response.text)
            return None
        
        data = response.json()
        all_results.extend(data.get("results", []))
        
        has_more = data.get("has_more", False)
        next_cursor = data.get("next_cursor")
    
    return all_results

def main():
    print("=== Status Geral - Notion Canper ===")
    print(f"Data/hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Buscar todos os cards
    print("Buscando todos os cards...")
    cards = query_all_cards()
    
    if not cards:
        print("Nenhum card encontrado ou erro na consulta.")
        return
    
    print(f"Total de cards no database: {len(cards)}")
    print()
    
    # Estatísticas por Status
    status_counts = {}
    tipo_counts = {}
    agente_counts = {}
    
    openclaw_cards = []
    
    for card in cards:
        props = card.get("properties", {})
        
        # Status
        status_obj = props.get("Status", {})
        status_select = status_obj.get("select") if status_obj else {}
        status = status_select.get("name", "Sem status") if status_select else "Sem status"
        
        # Tipo
        tipo_obj = props.get("Tipo", {})
        tipo_select = tipo_obj.get("select") if tipo_obj else {}
        tipo = tipo_select.get("name", "Sem tipo") if tipo_select else "Sem tipo"
        
        # Agente
        agente_obj = props.get("Agente", {})
        agente_select = agente_obj.get("select") if agente_obj else {}
        agente = agente_select.get("name", "Sem agente") if agente_select else "Sem agente"
        
        # Título
        title_obj = props.get("Name", {})
        title_list = title_obj.get("title", [{}]) if title_obj else [{}]
        title = title_list[0].get("text", {}).get("content", "Sem título") if title_list else "Sem título"
        
        # Contagens
        status_counts[status] = status_counts.get(status, 0) + 1
        tipo_counts[tipo] = tipo_counts.get(tipo, 0) + 1
        agente_counts[agente] = agente_counts.get(agente, 0) + 1
        
        # Filtrar cards OpenClaw
        if tipo == "OpenClaw":
            openclaw_cards.append({
                "id": card["id"],
                "title": title,
                "status": status,
                "agente": agente,
                "last_edited": card.get("last_edited_time", "")
            })
    
    print("=== Estatísticas Gerais ===")
    print("\nPor Status:")
    for status, count in sorted(status_counts.items()):
        print(f"  {status}: {count}")
    
    print("\nPor Tipo:")
    for tipo, count in sorted(tipo_counts.items()):
        print(f"  {tipo}: {count}")
    
    print("\nPor Agente:")
    for agente, count in sorted(agente_counts.items()):
        print(f"  {agente}: {count}")
    
    print(f"\n=== Cards OpenClaw ({len(openclaw_cards)}) ===")
    
    if not openclaw_cards:
        print("Nenhum card do tipo OpenClaw encontrado.")
        return
    
    # Agrupar por status
    openclaw_by_status = {}
    for card in openclaw_cards:
        status = card["status"]
        if status not in openclaw_by_status:
            openclaw_by_status[status] = []
        openclaw_by_status[status].append(card)
    
    for status in ["Aguardando", "Priorizado", "Em andamento", "Concluído"]:
        cards_in_status = openclaw_by_status.get(status, [])
        print(f"\n{status} ({len(cards_in_status)}):")
        
        for card in cards_in_status:
            print(f"  • {card['title']}")
            print(f"    ID: {card['id']}")
            print(f"    Agente: {card['agente']}")
            if card['last_edited']:
                last_edited = datetime.fromisoformat(card['last_edited'].replace('Z', '+00:00'))
                print(f"    Última edição: {last_edited.strftime('%Y-%m-%d %H:%M:%S')}")
            print()

if __name__ == "__main__":
    main()