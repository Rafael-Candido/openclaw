#!/usr/bin/env python3
"""
Script para verificar schema do database Notion Canper.
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

def get_database_schema():
    """Obtém o schema do database"""
    url = f"https://api.notion.com/v1/databases/{DATABASE_ID}"
    
    response = requests.get(url, headers=headers)
    
    if response.status_code != 200:
        print(f"ERRO ao buscar schema: {response.status_code}")
        print(response.text)
        return None
    
    return response.json()

def main():
    print("=== Schema - Database Notion Canper ===")
    print(f"Data/hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Database ID: {DATABASE_ID}")
    print()
    
    # Obter schema
    print("Obtendo schema do database...")
    database = get_database_schema()
    
    if not database:
        print("Não foi possível obter schema.")
        return
    
    # Extrair propriedades
    properties = database.get("properties", {})
    
    print(f"Total de propriedades: {len(properties)}")
    print()
    
    print("=== Lista de Propriedades ===")
    for prop_name, prop_details in properties.items():
        prop_type = prop_details.get("type", "desconhecido")
        
        print(f"\n{prop_name} ({prop_type}):")
        
        if prop_type == "select":
            options = prop_details.get("select", {}).get("options", [])
            print(f"  Opções: {[opt.get('name') for opt in options]}")
        
        elif prop_type == "multi_select":
            options = prop_details.get("multi_select", {}).get("options", [])
            print(f"  Opções: {[opt.get('name') for opt in options]}")
        
        elif prop_type == "status":
            options = prop_details.get("status", {}).get("options", [])
            print(f"  Opções: {[opt.get('name') for opt in options]}")
        
        elif prop_type == "people":
            print(f"  Tipo: people (usuários do workspace)")
        
        elif prop_type == "rich_text":
            print(f"  Tipo: rich_text (texto formatado)")
        
        elif prop_type == "title":
            print(f"  Tipo: title (título da página)")
        
        elif prop_type == "date":
            print(f"  Tipo: date (data)")
        
        elif prop_type == "checkbox":
            print(f"  Tipo: checkbox (verdadeiro/falso)")
        
        elif prop_type == "number":
            number_format = prop_details.get("number", {}).get("format", "number")
            print(f"  Tipo: number (formato: {number_format})")
        
        elif prop_type == "url":
            print(f"  Tipo: url (link)")
        
        elif prop_type == "email":
            print(f"  Tipo: email (endereço de e-mail)")
        
        elif prop_type == "phone_number":
            print(f"  Tipo: phone_number (número de telefone)")
        
        else:
            print(f"  Detalhes: {json.dumps(prop_details, indent=2)[:200]}...")

if __name__ == "__main__":
    main()