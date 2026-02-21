#!/usr/bin/env python3
"""
Script robusto para verificação do estado do Notion Canper como Diretor de Negócios.
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

def query_all_cards_simple():
    """Consulta simples todos os cards do database"""
    url = f"https://api.notion.com/v1/databases/{DATABASE_ID}/query"
    
    all_results = []
    has_more = True
    next_cursor = None
    
    while has_more:
        payload = {}
        if next_cursor:
            payload["start_cursor"] = next_cursor
        
        try:
            response = requests.post(url, headers=headers, json=payload, timeout=10)
            
            if response.status_code != 200:
                print(f"ERRO na consulta: {response.status_code}")
                print(response.text)
                return None
            
            data = response.json()
            all_results.extend(data.get("results", []))
            
            has_more = data.get("has_more", False)
            next_cursor = data.get("next_cursor")
            
        except Exception as e:
            print(f"Exceção na consulta: {e}")
            return None
    
    return all_results

def check_card_needs_attention(card):
    """Verifica se um card precisa de atenção do Diretor"""
    props = card.get("properties", {})
    
    # Status
    status_obj = props.get("Status", {})
    status_select = status_obj.get("select") if status_obj else {}
    status = status_select.get("name", "") if status_select else ""
    
    # Tipo
    tipo_obj = props.get("Tipo", {})
    tipo_select = tipo_obj.get("select") if tipo_obj else {}
    tipo = tipo_select.get("name", "") if tipo_select else ""
    
    # Agente
    agente_obj = props.get("Agente", {})
    agente_select = agente_obj.get("select") if agente_obj else {}
    agente = agente_select.get("name", "") if agente_select else ""
    
    # Título
    title_obj = props.get("Name", {})
    title_list = title_obj.get("title", [{}]) if title_obj else [{}]
    title = title_list[0].get("text", {}).get("content", "Sem título") if title_list else "Sem título"
    
    # Verificar se é OpenClaw
    if tipo != "OpenClaw":
        return False, None, None
    
    issues = []
    
    # Regra 1: Card em Aguardando precisa ser priorizado
    if status == "Aguardando":
        issues.append("🔄 Precisa ser movido para Priorizado")
    
    # Regra 2: Card em Priorizado sem agente definido
    if status == "Priorizado" and not agente:
        issues.append("👤 Agente não definido (deve ser 'Tech' temporário)")
    
    # Regra 3: Card em Priorizado com agente diferente de Tech
    if status == "Priorizado" and agente and agente != "Tech":
        issues.append(f"🤔 Agente '{agente}' - deve ser 'Tech' temporário")
    
    # Regra 4: Card em Em andamento há muito tempo (verificar timestamp)
    if status == "Em andamento":
        last_edited = card.get("last_edited_time", "")
        if last_edited:
            last_edited_dt = datetime.fromisoformat(last_edited.replace('Z', '+00:00'))
            now = datetime.utcnow().replace(tzinfo=last_edited_dt.tzinfo)
            hours_since_edit = (now - last_edited_dt).total_seconds() / 3600
            
            if hours_since_edit > 4:  # Mais de 4 horas sem movimento
                issues.append(f"⏰ Parado há {hours_since_edit:.1f} horas")
    
    if issues:
        return True, title, issues
    
    return False, None, None

def main():
    print("=== Diretor de Negócios - Verificação Robusta ===")
    print(f"Data/hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Workspace: Notion Canper")
    print(f"Database ID: {DATABASE_ID}")
    print()
    
    # 1. Buscar todos os cards
    print("1. Buscando todos os cards do database...")
    cards = query_all_cards_simple()
    
    if not cards:
        print("   ❌ Não foi possível buscar cards.")
        return
    
    print(f"   ✅ Total de cards: {len(cards)}")
    print()
    
    # 2. Filtrar cards OpenClaw
    print("2. Filtrando cards do tipo 'OpenClaw'...")
    openclaw_cards = []
    
    for card in cards:
        props = card.get("properties", {})
        tipo_obj = props.get("Tipo", {})
        tipo_select = tipo_obj.get("select") if tipo_obj else {}
        tipo = tipo_select.get("name", "") if tipo_select else ""
        
        if tipo == "OpenClaw":
            openclaw_cards.append(card)
    
    print(f"   ✅ Cards OpenClaw: {len(openclaw_cards)}")
    print()
    
    if not openclaw_cards:
        print("🎉 Nenhum card OpenClaw encontrado. Sistema limpo.")
        return
    
    # 3. Analisar cada card OpenClaw
    print("3. Analisando cards OpenClaw...")
    print()
    
    cards_by_status = {}
    cards_needing_attention = []
    
    for card in openclaw_cards:
        props = card.get("properties", {})
        
        # Status
        status_obj = props.get("Status", {})
        status_select = status_obj.get("select") if status_obj else {}
        status = status_select.get("name", "Sem status") if status_select else "Sem status"
        
        # Agente
        agente_obj = props.get("Agente", {})
        agente_select = agente_obj.get("select") if agente_obj else {}
        agente = agente_select.get("name", "Sem agente") if agente_select else "Sem agente"
        
        # Título
        title_obj = props.get("Name", {})
        title_list = title_obj.get("title", [{}]) if title_obj else [{}]
        title = title_list[0].get("text", {}).get("content", "Sem título") if title_list else "Sem título"
        
        # Card ID
        card_id = card["id"]
        
        # Agrupar por status
        if status not in cards_by_status:
            cards_by_status[status] = []
        cards_by_status[status].append({
            "title": title,
            "agente": agente,
            "id": card_id
        })
        
        # Verificar se precisa de atenção
        needs_attention, card_title, issues = check_card_needs_attention(card)
        if needs_attention:
            cards_needing_attention.append({
                "title": card_title,
                "issues": issues,
                "id": card_id,
                "status": status,
                "agente": agente
            })
    
    # 4. Mostrar resumo por status
    print("4. Resumo por status:")
    for status in ["Aguardando", "Priorizado", "Em andamento", "Concluído", "Anotações", "Finalizado"]:
        if status in cards_by_status:
            cards_list = cards_by_status[status]
            print(f"   📊 {status}: {len(cards_list)} card(s)")
            
            for card in cards_list:
                print(f"      • {card['title']}")
                print(f"        Agente: {card['agente']}")
                print(f"        ID: {card['id']}")
            print()
    
    # 5. Mostrar cards que precisam de atenção
    print("5. Cards que precisam de atenção do Diretor:")
    
    if cards_needing_attention:
        print(f"   ⚠️  Total: {len(cards_needing_attention)} card(s) precisam de ação")
        print()
        
        for card in cards_needing_attention:
            print(f"   📋 {card['title']}")
            print(f"      Status: {card['status']}")
            print(f"      Agente: {card['agente']}")
            print(f"      ID: {card['id']}")
            print(f"      Problemas:")
            for issue in card['issues']:
                print(f"        • {issue}")
            print()
    else:
        print("   ✅ Nenhum card precisa de atenção imediata.")
        print()
    
    # 6. Verificar especificamente cards em Aguardando
    print("6. Verificação específica - Cards em 'Aguardando':")
    aguardando_cards = cards_by_status.get("Aguardando", [])
    
    if aguardando_cards:
        print(f"   🎯 Ação necessária: {len(aguardando_cards)} card(s) em Aguardando")
        print(f"   Fluxo: Aguardando → Priorizado (Agente=Tech)")
        print()
        
        for card in aguardando_cards:
            print(f"   📋 {card['title']}")
            print(f"      ID: {card['id']}")
            print(f"      Ação: Mover para Priorizado, definir Agente=Tech")
            print(f"      Adicionar descrição técnica completa")
            print()
    else:
        print("   ✅ Nenhum card em Aguardando para processar.")
        print()
    
    # 7. Conclusão
    print("=== Conclusão da Varredura ===")
    
    total_openclaw = len(openclaw_cards)
    total_needing_attention = len(cards_needing_attention)
    total_aguardando = len(aguardando_cards)
    
    print(f"📈 Estatísticas:")
    print(f"   • Total cards OpenClaw: {total_openclaw}")
    print(f"   • Cards precisando de atenção: {total_needing_attention}")
    print(f"   • Cards em Aguardando: {total_aguardando}")
    print()
    
    if total_aguardando > 0:
        print("🚨 AÇÃO REQUERIDA: Processar cards em Aguardando")
    elif total_needing_attention > 0:
        print("⚠️  VERIFICAÇÃO RECOMENDADA: Alguns cards precisam de ajustes")
    else:
        print("✅ SISTEMA OPERACIONAL: Todos os cards estão no fluxo correto")
    
    print(f"\n📅 Próxima varredura: Em 30 minutos")

if __name__ == "__main__":
    main()