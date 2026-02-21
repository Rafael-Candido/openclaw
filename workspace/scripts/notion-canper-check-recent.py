#!/usr/bin/env python3
"""
Script para verificar cards recentes no Notion Canper.
"""
import os
import json
import requests
from datetime import datetime, timedelta

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

def query_recent_cards(hours=24):
    """Consulta cards criados/atualizados recentemente"""
    url = f"https://api.notion.com/v1/databases/{DATABASE_ID}/query"
    
    # Calcular timestamp (Notion usa ISO 8601)
    since_time = (datetime.utcnow() - timedelta(hours=hours)).isoformat() + "Z"
    
    # Ordenar por última edição (mais recente primeiro)
    payload = {
        "sorts": [
            {
                "property": "last_edited_time",
                "direction": "descending"
            }
        ],
        "filter": {
            "timestamp": "last_edited_time",
            "last_edited_time": {
                "on_or_after": since_time
            }
        }
    }
    
    response = requests.post(url, headers=headers, json=payload)
    
    if response.status_code != 200:
        print(f"ERRO na consulta: {response.status_code}")
        print(response.text)
        return None
    
    return response.json()

def main():
    print("=== Diretor de Negócios - Verificação de Cards Recentes ===")
    print(f"Data/hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Período: últimas 24 horas")
    print()
    
    # Buscar cards recentes
    print("Buscando cards editados nas últimas 24 horas...")
    result = query_recent_cards(24)
    
    if not result:
        print("Nenhum card encontrado ou erro na consulta.")
        return
    
    cards = result.get("results", [])
    print(f"Encontrados {len(cards)} card(s) editados recentemente.")
    print()
    
    if not cards:
        print("Nenhum card editado recentemente.")
        return
    
    # Filtrar apenas cards OpenClaw
    openclaw_cards = []
    
    for card in cards:
        props = card.get("properties", {})
        
        # Tipo
        tipo_obj = props.get("Tipo", {})
        tipo_select = tipo_obj.get("select") if tipo_obj else {}
        tipo = tipo_select.get("name", "") if tipo_select else ""
        
        if tipo == "OpenClaw":
            # Título
            title_obj = props.get("Name", {})
            title_list = title_obj.get("title", [{}]) if title_obj else [{}]
            title = title_list[0].get("text", {}).get("content", "Sem título") if title_list else "Sem título"
            
            # Status
            status_obj = props.get("Status", {})
            status_select = status_obj.get("select") if status_obj else {}
            status = status_select.get("name", "Sem status") if status_select else "Sem status"
            
            # Agente
            agente_obj = props.get("Agente", {})
            agente_select = agente_obj.get("select") if agente_obj else {}
            agente = agente_select.get("name", "Sem agente") if agente_select else "Sem agente"
            
            # Timestamps
            created_time = card.get("created_time", "")
            last_edited = card.get("last_edited_time", "")
            
            openclaw_cards.append({
                "id": card["id"],
                "title": title,
                "status": status,
                "agente": agente,
                "created": created_time,
                "last_edited": last_edited
            })
    
    print(f"=== Cards OpenClaw Recentes ({len(openclaw_cards)}) ===")
    
    if not openclaw_cards:
        print("Nenhum card OpenClaw editado recentemente.")
        return
    
    for card in openclaw_cards:
        print(f"\n📋 {card['title']}")
        print(f"   ID: {card['id']}")
        print(f"   Status: {card['status']}")
        print(f"   Agente: {card['agente']}")
        
        if card['last_edited']:
            last_edited_dt = datetime.fromisoformat(card['last_edited'].replace('Z', '+00:00'))
            now = datetime.utcnow().replace(tzinfo=last_edited_dt.tzinfo)
            hours_ago = (now - last_edited_dt).total_seconds() / 3600
            print(f"   Última edição: {last_edited_dt.strftime('%Y-%m-%d %H:%M:%S')} ({hours_ago:.1f} horas atrás)")
        
        # Verificar se precisa de atenção do Diretor
        needs_attention = False
        issues = []
        
        if card['status'] == "Aguardando":
            needs_attention = True
            issues.append("🔄 Precisa ser priorizado")
        
        if card['agente'] == "Sem agente" and card['status'] in ["Aguardando", "Priorizado"]:
            needs_attention = True
            issues.append("👤 Agente não definido")
        
        if card['status'] == "Priorizado" and card['agente'] == "Tech":
            # Verificar se está parado há muito tempo
            if card['last_edited']:
                last_edited_dt = datetime.fromisoformat(card['last_edited'].replace('Z', '+00:00'))
                now = datetime.utcnow().replace(tzinfo=last_edited_dt.tzinfo)
                hours_since_edit = (now - last_edited_dt).total_seconds() / 3600
                
                if hours_since_edit > 2:  # Mais de 2 horas sem movimento
                    needs_attention = True
                    issues.append(f"⏰ Parado há {hours_since_edit:.1f} horas")
        
        if needs_attention:
            print(f"   ⚠️  ATENÇÃO: {', '.join(issues)}")
        else:
            print(f"   ✅ Estado OK")
    
    print(f"\n=== Resumo ===")
    
    # Contar cards por status
    status_counts = {}
    for card in openclaw_cards:
        status = card['status']
        status_counts[status] = status_counts.get(status, 0) + 1
    
    for status, count in sorted(status_counts.items()):
        print(f"  {status}: {count} card(s)")
    
    # Verificar se há cards em Aguardando
    aguardando_cards = [c for c in openclaw_cards if c['status'] == "Aguardando"]
    
    if aguardando_cards:
        print(f"\n🎯 Ação necessária: {len(aguardando_cards)} card(s) em Aguardando para priorizar.")
        for card in aguardando_cards:
            print(f"   • {card['title']}")
    else:
        print(f"\n✅ Nenhum card em Aguardando para processar.")

if __name__ == "__main__":
    main()