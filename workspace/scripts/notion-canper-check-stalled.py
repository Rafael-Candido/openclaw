#!/usr/bin/env python3
"""
Script para verificar se cards estão parados/travados no Notion Canper.
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

def get_card_details(card_id):
    """Obtém detalhes de um card específico"""
    url = f"https://api.notion.com/v1/pages/{card_id}"
    
    response = requests.get(url, headers=headers)
    
    if response.status_code != 200:
        print(f"ERRO ao buscar card {card_id}: {response.status_code}")
        return None
    
    return response.json()

def main():
    print("=== Diretor de Negócios - Verificação de Cards Parados ===")
    print(f"Data/hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Card ativo em Priorizado
    CARD_ID = "30dbf9163c968023bfbef33e864b9843"  # Sem hífens
    print(f"Verificando card ativo: {CARD_ID}")
    print()
    
    # Obter detalhes do card
    card = get_card_details(CARD_ID)
    
    if not card:
        print("❌ Não foi possível obter detalhes do card.")
        return
    
    # Extrair informações
    props = card.get("properties", {})
    
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
    
    print(f"📋 Card: {title}")
    print(f"   ID: {CARD_ID}")
    print(f"   Status: {status}")
    print(f"   Agente: {agente}")
    
    if created_time:
        created_dt = datetime.fromisoformat(created_time.replace('Z', '+00:00'))
        print(f"   Criado em: {created_dt.strftime('%Y-%m-%d %H:%M:%S')}")
    
    if last_edited:
        last_edited_dt = datetime.fromisoformat(last_edited.replace('Z', '+00:00'))
        now = datetime.utcnow().replace(tzinfo=last_edited_dt.tzinfo)
        hours_since_edit = (now - last_edited_dt).total_seconds() / 3600
        
        print(f"   Última edição: {last_edited_dt.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"   Tempo desde última edição: {hours_since_edit:.1f} horas")
        print()
        
        # Verificar se está parado
        if status == "Priorizado":
            if hours_since_edit > 2:
                print(f"⚠️  ALERTA: Card em Priorizado há {hours_since_edit:.1f} horas")
                print(f"   • Especialista Tech deveria ter captado")
                print(f"   • Possíveis causas:")
                print(f"     - Cron do especialista Tech não está rodando")
                print(f"     - Especialista Tech com problemas de configuração")
                print(f"     - Card não está sendo detectado pelo filtro")
                print()
                
                # Ações recomendadas
                print(f"🎯 Ações recomendadas:")
                print(f"   1. Verificar cron do especialista Tech")
                print(f"   2. Notificar via Discord/WhatsApp")
                print(f"   3. Forçar execução manual se necessário")
            elif hours_since_edit > 1:
                print(f"📊 Monitoramento: Card em Priorizado há {hours_since_edit:.1f} horas")
                print(f"   • Ainda dentro do tempo esperado")
                print(f"   • Próxima verificação em 30 minutos")
            else:
                print(f"✅ Normal: Card em Priorizado há {hours_since_edit:.1f} horas")
                print(f"   • Dentro do tempo normal de processamento")
        
        elif status == "Em andamento":
            if hours_since_edit > 4:
                print(f"🚨 CRÍTICO: Card em Em andamento há {hours_since_edit:.1f} horas")
                print(f"   • Execução pode estar travada")
                print(f"   • Especialista pode ter encontrado erro")
            elif hours_since_edit > 2:
                print(f"⚠️  ALERTA: Card em Em andamento há {hours_since_edit:.1f} horas")
                print(f"   • Execução pode estar lenta")
            else:
                print(f"✅ Normal: Card em Em andamento há {hours_since_edit:.1f} horas")
    
    # Verificar conteúdo do card
    print()
    print(f"🔍 Verificando conteúdo do card...")
    
    # Buscar blocos do card
    url = f"https://api.notion.com/v1/blocks/{CARD_ID}/children"
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        blocks_data = response.json()
        blocks = blocks_data.get("results", [])
        
        print(f"   Total de blocos: {len(blocks)}")
        
        # Verificar se há instruções técnicas
        has_instructions = False
        for block in blocks:
            block_type = block.get("type", "")
            if block_type in ["heading_2", "heading_3", "paragraph", "numbered_list_item", "bulleted_list_item"]:
                has_instructions = True
                break
        
        if has_instructions:
            print(f"   ✅ Instruções técnicas presentes")
        else:
            print(f"   ⚠️  Instruções técnicas ausentes ou incompletas")
    else:
        print(f"   ⚠️  Não foi possível verificar conteúdo (erro {response.status_code})")
    
    print()
    print(f"=== Conclusão ===")
    
    # Resumo do estado
    if status == "Priorizado" and last_edited:
        last_edited_dt = datetime.fromisoformat(last_edited.replace('Z', '+00:00'))
        now = datetime.utcnow().replace(tzinfo=last_edited_dt.tzinfo)
        hours_since_edit = (now - last_edited_dt).total_seconds() / 3600
        
        if hours_since_edit > 2:
            print(f"🚨 INTERVENÇÃO NECESSÁRIA")
            print(f"• Card parado há {hours_since_edit:.1f} horas")
            print(f"• Especialista Tech não captou")
            print(f"• Ação: Investigar cron do especialista")
        elif hours_since_edit > 1:
            print(f"📊 MONITORAMENTO ATIVO")
            print(f"• Card aguardando captura há {hours_since_edit:.1f} horas")
            print(f"• Próxima verificação em 30 minutos")
        else:
            print(f"✅ OPERACIONAL")
            print(f"• Card no fluxo normal")
            print(f"• Aguardando captura do especialista")
    else:
        print(f"✅ SITUAÇÃO NORMAL")
        print(f"• Card no status: {status}")
        print(f"• Agente: {agente}")
    
    print()
    print(f"📅 Próxima varredura do Diretor: Em 30 minutos")

if __name__ == "__main__":
    main()