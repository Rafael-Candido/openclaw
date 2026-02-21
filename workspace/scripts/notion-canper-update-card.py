#!/usr/bin/env python3
"""
Script para atualizar card específico no Notion Canper.
"""
import os
import json
import requests
from datetime import datetime

# Configurações
DATABASE_ID = "14abf9163c9680ff822bc2e32f6bec4b"
API_KEY = os.getenv("NOTION_CANPER_API_KEY")
CARD_ID = "30dbf9163c968023bfbef33e864b9843"  # ID do card encontrado (sem hífens)

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
        print(response.text)
        return None
    
    return response.json()

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

def add_comment_to_card(card_id, text):
    """Adiciona um comentário/bloco a um card"""
    url = f"https://api.notion.com/v1/blocks/{card_id}/children"
    
    payload = {
        "children": [
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [
                        {
                            "type": "text",
                            "text": {
                                "content": text
                            }
                        }
                    ]
                }
            }
        ]
    }
    
    response = requests.patch(url, headers=headers, json=payload)
    
    if response.status_code != 200:
        print(f"ERRO ao adicionar comentário: {response.status_code}")
        print(response.text)
        return False
    
    return True

def main():
    print("=== Diretor de Negócios - Atualização de Card ===")
    print(f"Data/hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Card ID: {CARD_ID}")
    print()
    
    # 1. Obter detalhes do card
    print("1. Obtendo detalhes do card...")
    card = get_card_details(CARD_ID)
    
    if not card:
        print("   ❌ Não foi possível obter detalhes do card.")
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
    
    # Tipo
    tipo_obj = props.get("Tipo", {})
    tipo_select = tipo_obj.get("select") if tipo_obj else {}
    tipo = tipo_select.get("name", "Sem tipo") if tipo_select else "Sem tipo"
    
    # Agente
    agente_obj = props.get("Agente", {})
    agente_select = agente_obj.get("select") if agente_obj else {}
    agente = agente_select.get("name", "Sem agente") if agente_select else "Sem agente"
    
    # Descrição
    desc_obj = props.get("Descrição", {})
    desc_list = desc_obj.get("rich_text", [{}]) if desc_obj else [{}]
    descricao = desc_list[0].get("text", {}).get("content", "") if desc_list else ""
    
    print(f"   Título: {title}")
    print(f"   Status: {status}")
    print(f"   Tipo: {tipo}")
    print(f"   Agente: {agente}")
    print(f"   Descrição: {descricao[:200]}..." if descricao else "   Descrição: (vazia)")
    print()
    
    # 2. Verificar se precisa de normalização
    print("2. Verificando necessidade de normalização...")
    
    needs_update = False
    update_properties = {}
    
    # Verificar Status (deve ser Priorizado)
    if status != "Priorizado":
        print(f"   ⚠️  Status incorreto: {status} → deve ser 'Priorizado'")
        update_properties["Status"] = {"select": {"name": "Priorizado"}}
        needs_update = True
    else:
        print(f"   ✅ Status correto: Priorizado")
    
    # Verificar Tipo (deve ser OpenClaw)
    if tipo != "OpenClaw":
        print(f"   ⚠️  Tipo incorreto: {tipo} → deve ser 'OpenClaw'")
        update_properties["Tipo"] = {"select": {"name": "OpenClaw"}}
        needs_update = True
    else:
        print(f"   ✅ Tipo correto: OpenClaw")
    
    # Verificar Agente (deve ser Tech temporariamente)
    if agente != "Tech":
        print(f"   ⚠️  Agente incorreto: {agente} → deve ser 'Tech' (temporário)")
        update_properties["Agente"] = {"select": {"name": "Tech"}}
        needs_update = True
    else:
        print(f"   ✅ Agente correto: Tech")
    
    # 3. Atualizar card se necessário
    if needs_update:
        print(f"\n3. Atualizando card...")
        print(f"   Propriedades a atualizar: {list(update_properties.keys())}")
        
        if update_card(CARD_ID, update_properties):
            print(f"   ✅ Card atualizado com sucesso.")
        else:
            print(f"   ❌ Falha ao atualizar card.")
            return
    else:
        print(f"\n3. Card já normalizado, nenhuma atualização necessária.")
    
    # 4. Verificar/atualizar descrição
    print(f"\n4. Verificando descrição...")
    
    # Descrição técnica completa para o especialista Tech
    nova_descricao = """## Contexto
Pesquisa de mercado para identificar as maiores empresas B2B do Brasil com modelo de negócio semelhante ao da SmartEnvios (logística, e-commerce, SaaS).

## O que fazer (passos)
1. Pesquisar listas de maiores empresas B2B do Brasil por receita/faturamento
2. Filtrar empresas com modelo semelhante a SmartEnvios (logística, tecnologia para e-commerce, SaaS)
3. Coletar informações principais: nome, faturamento, segmento, modelo de negócio
4. Analisar concorrência direta e indireta
5. Identificar oportunidades de mercado e diferenciais competitivos

## Critérios de conclusão
- Lista com pelo menos 10 empresas B2B brasileiras relevantes
- Análise comparativa com SmartEnvios (semelhanças/diferenças)
- Identificação de oportunidades de mercado
- Documento estruturado com insights

## Notion / recurso
- Skill: notion-canper
- Database ID: 14abf9163c9680ff822bc2e32f6bec4b

## Checklist obrigatório (strict)
- [ ] Status inicial em Priorizado
- [ ] Agente correto (Tech temporário)
- [ ] Objetivo e escopo explícitos
- [ ] Passos executáveis sem ambiguidade
- [ ] Fontes de pesquisa confiáveis
- [ ] Análise estruturada e insights acionáveis"""
    
    if not descricao or len(descricao) < 100:
        print(f"   ⚠️  Descrição muito curta ou vazia.")
        print(f"   Adicionando descrição técnica completa...")
        
        # Atualizar descrição
        desc_properties = {
            "Descrição": {
                "rich_text": [
                    {
                        "type": "text",
                        "text": {
                            "content": nova_descricao
                        }
                    }
                ]
            }
        }
        
        if update_card(CARD_ID, desc_properties):
            print(f"   ✅ Descrição atualizada com sucesso.")
        else:
            print(f"   ❌ Falha ao atualizar descrição.")
    else:
        print(f"   ✅ Descrição já existe ({len(descricao)} caracteres).")
        print(f"   Verificar se está completa e técnica...")
        print(f"   Descrição atual: {descricao[:300]}...")
    
    # 5. Adicionar comentário de atualização
    print(f"\n5. Adicionando comentário de atualização...")
    
    comentario = f"""[{datetime.now().strftime('%H:%M')}] 🎯 Diretor de Negócios - Card normalizado
- Status: Priorizado ✓
- Tipo: OpenClaw ✓  
- Agente: Tech (temporário, aguardando especialista de negócios) ✓
- Descrição: {"Atualizada" if not descricao or len(descricao) < 100 else "Verificada"}
Próximo: Especialista Tech capta card e executa pesquisa."""
    
    if add_comment_to_card(CARD_ID, comentario):
        print(f"   ✅ Comentário adicionado com sucesso.")
    else:
        print(f"   ⚠️  Não foi possível adicionar comentário (pode exigir permissões adicionais).")
    
    print(f"\n=== Atualização concluída ===")
    print(f"Card '{title}' está pronto para o especialista Tech.")

if __name__ == "__main__":
    main()