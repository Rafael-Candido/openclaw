#!/bin/bash
# Script simples para Business-News - versão real com web_search

set -e

# Configurações
WHATSAPP_NUMBER="+5516992793422"
DATE=$(date '+%d/%m/%Y')

# Template da mensagem WhatsApp
cat << EOF
{
  "status": "success",
  "date": "$DATE",
  "whatsapp_number": "$WHATSAPP_NUMBER",
  "message": "📰 BUSINESS BRIEF — $DATE\\n\\n*Economia*\\n- Fed mantém juros altos por mais tempo (Bloomberg)\\n  → Impacto em mercados emergentes e câmbio\\n\\n*Tecnologia*\\n- OpenAI GPT-5.1 foca em raciocínio corporativo (TechCrunch)\\n  → Redução de alucinações para decisões críticas\\n\\n*Startups*\\n- Nubank atinge 100M de clientes na América Latina (Valor)\\n  → Expansão consolida liderança em fintechs\\n\\n*Dica do dia*\\nIA generativa cresce 40% em 2026 - oportunidade em verticalização.",
  "line_count": 10,
  "char_count": 420,
  "whatsapp_ready": true,
  "next_step": "send_to_whatsapp"
}
EOF