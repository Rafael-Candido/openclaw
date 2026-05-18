#!/usr/bin/env bash
# Business-News: coleta deterministica de noticias e gera payload JSON para WhatsApp.

set -euo pipefail

WHATSAPP_NUMBER="${BUSINESS_NEWS_WHATSAPP_NUMBER:-+5516992793422}"
DATE="$(TZ="${TZ:-America/Sao_Paulo}" date '+%d/%m/%Y')"
GENERATED_AT="$(TZ="${TZ:-America/Sao_Paulo}" date '+%Y-%m-%dT%H:%M:%S%z')"

python3 - "$WHATSAPP_NUMBER" "$DATE" "$GENERATED_AT" <<'PY'
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

whatsapp_number, date_label, generated_at = sys.argv[1:4]

TOP_N = 10
SUMMARY_LIMIT = 500

QUERIES = [
    ("Economia", '("mercado financeiro" OR economia OR bolsa OR dólar OR Selic OR juros) when:1d'),
    ("Mercados", '(Ibovespa OR dólar OR "Bolsa brasileira" OR "mercados globais" OR commodities) when:1d'),
    ("Tecnologia", '("inteligência artificial" OR "IA generativa" OR tecnologia OR software OR cloud OR cibersegurança) (negócios OR empresas OR mercado) when:1d'),
    ("Startups", '(startups OR fintech OR "venture capital" OR "captação" OR unicórnio) Brasil when:7d'),
    ("Negócios", '("fusões e aquisições" OR M&A OR varejo OR indústria OR energia OR bancos) Brasil negócios when:1d'),
]

SOURCE_SCORE = {
    "valor econômico": 12,
    "infomoney": 11,
    "money times": 11,
    "bloomberg línea": 11,
    "bloomberg linea": 11,
    "reuters": 11,
    "brazil journal": 10,
    "exame": 10,
    "neofeed": 10,
    "seu dinheiro": 10,
    "investnews": 9,
    "cnn brasil": 8,
    "forbes brasil": 8,
    "estadão": 7,
    "estadao": 7,
    "folha": 7,
    "techcrunch": 7,
    "mit technology review": 7,
    "wired": 7,
}

SECTION_KEYWORDS = {
    "Economia": [
        "mercado",
        "bolsa",
        "dólar",
        "dolar",
        "selic",
        "juros",
        "ipca",
        "fed",
        "banco central",
        "ações",
        "acoes",
        "investidores",
        "petróleo",
        "petroleo",
    ],
    "Tecnologia": [
        "inteligência artificial",
        "inteligencia artificial",
        "ia",
        "software",
        "cloud",
        "dados",
        "chip",
        "cibersegurança",
        "ciberseguranca",
        "automação",
        "automacao",
        "empresa",
        "negócios",
        "negocios",
    ],
    "Startups": [
        "startup",
        "startups",
        "fintech",
        "aporte",
        "rodada",
        "venture",
        "capital",
        "unicórnio",
        "unicornio",
        "funding",
        "investimento",
        "empreendedor",
    ],
    "Mercados": [
        "ibovespa",
        "bolsa",
        "dólar",
        "dolar",
        "commodities",
        "petróleo",
        "petroleo",
        "ações",
        "acoes",
        "mercados",
        "investidores",
    ],
    "Negócios": [
        "empresa",
        "negócios",
        "negocios",
        "varejo",
        "banco",
        "energia",
        "indústria",
        "industria",
        "m&a",
        "fusão",
        "fusao",
        "aquisição",
        "aquisicao",
        "lucro",
        "receita",
    ],
}

NEGATIVE_KEYWORDS = [
    "curso",
    "inscri",
    "concurso",
    "processo seletivo",
    "prefeitura",
    "câmara",
    "camara",
    "edital",
    "vaga",
    "vagas",
    "emprego",
    "empregos",
    "carreira",
    "salário",
    "salario",
    "trainee",
    "estágio",
    "estagio",
    "oportunidades",
    "processo seletivo",
    "horóscopo",
    "horoscopo",
    "novela",
    "futebol",
    "apostas esportivas",
]

SUMMARY_RULES = [
    (
        ["ibovespa", "bolsa", "dólar", "dolar", "mercado", "ações", "acoes"],
        "Movimento de mercado relevante para acompanhar câmbio, juros e apetite por risco. Pode influenciar custo de capital, valuation de empresas, decisões de caixa e timing de investimentos, principalmente em negócios expostos a importação, crédito ou commodities.",
    ),
    (
        ["juros", "selic", "fed", "banco central", "inflação", "inflacao", "ipca"],
        "Sinal importante para custo de capital, crédito e precificação. Mudanças na leitura de juros ou inflação tendem a afetar consumo, financiamento, margem das empresas e decisões de investimento nos próximos ciclos.",
    ),
    (
        ["inteligência artificial", "inteligencia artificial", " ia ", "ia generativa", "software", "cloud", "dados"],
        "Tecnologia com impacto direto em produtividade, automação e custos operacionais. Vale observar como empresas estão convertendo IA, software, cloud e dados em vantagem competitiva, eficiência interna e novas receitas.",
    ),
    (
        ["cibersegurança", "ciberseguranca", "segurança", "seguranca", "vazamento"],
        "Tema de risco operacional que pode exigir revisão de governança, fornecedores, dados e continuidade de negócio. O impacto costuma aparecer em compliance, reputação, custos de resposta e confiança de clientes.",
    ),
    (
        ["startup", "startups", "fintech", "aporte", "rodada", "venture", "unicórnio", "unicornio"],
        "Movimento mostra apetite de capital e setores com tração. Ajuda a ler onde investidores enxergam crescimento, quais modelos ganham escala e onde podem surgir concorrentes, parcerias ou oportunidades de aquisição.",
    ),
    (
        ["varejo", "indústria", "industria", "banco", "energia", "lucro", "receita"],
        "Notícia corporativa relevante para acompanhar demanda, margens, concorrência e estratégia setorial. O dado pode indicar mudança de ciclo, pressão de custos, reposicionamento comercial ou alteração na força competitiva do segmento.",
    ),
    (
        ["fusão", "fusao", "aquisição", "aquisicao", "m&a", "compra", "venda"],
        "Transação que pode alterar dinâmica competitiva, consolidação de mercado e prioridades estratégicas do setor. M&A costuma sinalizar busca por escala, ganho de eficiência, expansão de canais ou defesa contra novos entrantes.",
    ),
    (
        ["oriente médio", "oriente medio", "china", "eua", "estados unidos", "tarifa", "guerra"],
        "Fator macro ou geopolítico com potencial de pressionar cadeias, câmbio, commodities e decisões de risco. Empresas com exposição internacional podem sentir impacto em preço, prazo, disponibilidade de insumos e planejamento financeiro.",
    ),
]


def google_news_url(query: str) -> str:
    params = urllib.parse.urlencode(
        {
            "q": query,
            "hl": "pt-BR",
            "gl": "BR",
            "ceid": "BR:pt-419",
        }
    )
    return f"https://news.google.com/rss/search?{params}"


def clean_title(raw: str, source: str) -> str:
    title = html.unescape(raw or "").strip()
    title = re.sub(r"\s+", " ", title)
    if source and title.endswith(f" - {source}"):
        title = title[: -(len(source) + 3)].strip()
    if len(title) > 105:
        title = title[:102].rstrip() + "..."
    return title


def clean_text(raw: str) -> str:
    text = re.sub(r"<[^>]+>", " ", raw or "")
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def clip(text: str, limit: int) -> str:
    text = re.sub(r"\s+", " ", text or "").strip()
    if len(text) <= limit:
        return text
    cut = text[: limit - 1].rstrip()
    last_space = cut.rfind(" ")
    if last_space > 120:
        cut = cut[:last_space]
    return cut.rstrip(" .,;:") + "…"


def norm(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (text or "").lower()).strip()


def score_item(section: str, title: str, source: str, position: int) -> float:
    haystack = f"{title} {source}".lower()
    score = 50.0 - min(position, 25) * 0.4
    for source_name, source_score in SOURCE_SCORE.items():
        if source_name in source.lower():
            score += source_score
            break
    for keyword in SECTION_KEYWORDS.get(section, []):
        if keyword in haystack:
            score += 3
    for keyword in NEGATIVE_KEYWORDS:
        if keyword in haystack:
            score -= 20
    return score


def build_summary(section: str, title: str, source: str, description: str) -> str:
    desc = clean_text(description)
    title_n = norm(title)
    desc_n = norm(desc)
    source_n = norm(source)

    # Google News RSS descriptions often repeat only title + source. Use them
    # only when there is real extra context.
    if desc and len(desc) >= 80 and title_n not in desc_n and source_n not in desc_n:
        return clip(desc, SUMMARY_LIMIT)

    haystack = f" {title.lower()} {source.lower()} "
    for keywords, summary in SUMMARY_RULES:
        if any(f" {keyword} " in haystack or keyword in haystack for keyword in keywords):
            return clip(summary, SUMMARY_LIMIT)

    return clip(
        f"Notícia de {section.lower()} relevante para acompanhar impactos em receita, custos, demanda, risco e estratégia. O item merece atenção pelo potencial de influenciar decisões comerciais, planejamento financeiro ou leitura competitiva nos próximos dias.",
        SUMMARY_LIMIT,
    )


def fetch_candidates(section, query):
    url = google_news_url(query)
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "OpenClaw Business-News/1.0 (+https://openclaw.local)",
            "Accept": "application/rss+xml, application/xml;q=0.9, */*;q=0.8",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            raw = resp.read()
        root = ET.fromstring(raw)
    except Exception as exc:
        return [], f"{type(exc).__name__}: {exc}"

    candidates = []
    for position, item in enumerate(root.findall("./channel/item"), start=1):
        source_el = item.find("source")
        source = (source_el.text or "").strip() if source_el is not None else ""
        title = clean_title(item.findtext("title", ""), source)
        description = item.findtext("description", "") or ""
        key = norm(title)
        if not title:
            continue
        source_display = source or "Google News"
        summary = build_summary(section, title, source_display, description)
        candidates.append(
            (
                score_item(section, title, source_display, position),
                key,
                {
                    "section": section,
                    "title": title,
                    "source": source_display,
                    "summary": summary,
                    "summary_char_count": len(summary),
                },
            )
        )

    return candidates, None if candidates else "no_items"


seen_titles = set()
scored_items = []
errors = {}

for section, query in QUERIES:
    candidates, err = fetch_candidates(section, query)
    if err:
        errors[section] = err or "unknown"
    for score, key, item in candidates:
        if key in seen_titles:
            continue
        seen_titles.add(key)
        item["score"] = round(score, 2)
        scored_items.append((score, item))
    time.sleep(0.2)

scored_items.sort(key=lambda row: row[0], reverse=True)
top_items = [item for _score, item in scored_items[:TOP_N]]

lines = [f"📰 BUSINESS BRIEF — {date_label}", f"Top {len(top_items)} notícias de negócios", ""]
item_messages = []
for index, item in enumerate(top_items, start=1):
    source = item.get("source") or "Fonte"
    section = item.get("section") or "Negócios"
    item_message = "\n".join(
        [
            f"📰 BUSINESS BRIEF — {date_label}",
            f"Notícia {index}/{len(top_items)}",
            "",
            f"{item['title']} ({source} | {section})",
            f"Resumo: {item['summary']}",
        ]
    )
    item["message"] = item_message
    item["message_char_count"] = len(item_message)
    item_messages.append(item_message)
    lines.extend(
        [
            f"{index}. {item['title']} ({source} | {section})",
            f"Resumo: {item['summary']}",
            "",
        ]
    )

if top_items:
    message = "\n".join(lines).rstrip()
else:
    message = "\n".join(
        [
            f"📰 BUSINESS BRIEF — {date_label}",
            "Nao consegui coletar noticias suficientes agora. Verifique conexao/rede e fontes RSS.",
        ]
    )

payload = {
    "status": "success" if len(top_items) >= TOP_N and not errors else "degraded",
    "date": date_label,
    "generated_at": generated_at,
    "whatsapp_number": whatsapp_number,
    "source_mode": "google_news_rss",
    "top_count": len(top_items),
    "summary_char_limit": SUMMARY_LIMIT,
    "items": top_items,
    "messages": item_messages,
    "message_mode": "one_message_per_news",
    "errors": errors,
    "message": message,
    "line_count": len(message.splitlines()),
    "char_count": len(message),
    "whatsapp_ready": bool(top_items),
    "next_step": "send_to_whatsapp",
}

print(json.dumps(payload, ensure_ascii=False))
PY
