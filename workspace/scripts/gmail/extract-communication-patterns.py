#!/usr/bin/env python3
"""
Read email-samples-sent.json (from export-sent-samples.py) and produce a summary
of communication styles by context for use in rafael-dna or prompts.

Usage:
  python3 workspace/scripts/gmail/extract-communication-patterns.py workspace/docs/email-samples-sent.json [--out workspace/docs/communication-patterns-from-samples.md]
"""

import argparse
import json
import re
import sys
from pathlib import Path


# Assuntos/contextos comuns (SmartEnvios) para classificação
SUBJECT_CONTEXTS = [
    ("magalog|atualização de pedidos", "Transportadora / Magalog"),
    ("gptw|empresa.*prompta", "RH / GPTW"),
    ("teste técnico|estágio.*desenvolvimento|estágio.*automação|estágio.*marketing", "RH / Processo seletivo"),
    ("entrevista de desligamento|desligamento", "RH / Desligamento"),
    ("extra cx|trabalho extra", "Operação / Extra CX"),
    ("integração.*alvo|alvo.*smartenvios", "Parceiro / Integração Alvo"),
    ("integração.*magento|smart.*magento", "Parceiro / Integração Magento"),
    ("magazord|parceria magazord", "Parceiro / Magazord"),
    ("diálogo|reunião.*diálogo", "Parceiro / Diálogo"),
    ("j&t|j&t.*franquia", "Transportadora / J&T"),
    ("jadlog|tabela de abrangência", "Transportadora / JADLOG"),
    ("serra es|abrangência.*serra", "Transportadora / Abrangência"),
    ("registro de marca", "Jurídico / Marca"),
    ("pontos de coleta|contrato.*temporário", "Operação / Pontos de coleta"),
    ("action required|amazon|aws|eks|kubernetes|lambda", "Infra / AWS"),
    ("digital experience|digital experience brasil", "Evento / Marketing"),
    ("redução de escopo", "Comercial / Escopo"),
    ("solicitação de suporte|solicitação de indenização|entrega", "Suporte / Solicitações"),
    ("formalização de alinhamentos", "Comercial / Alinhamentos"),
]

def infer_context(sample: dict) -> str:
    to = (sample.get("to") or "").lower()
    subject = (sample.get("subject") or "").lower()
    combined = f"{to} {subject}"
    for pattern, label in SUBJECT_CONTEXTS:
        if re.search(pattern, combined, re.IGNORECASE):
            return label
    if "smartenvios" in to or "smartenvios" in subject:
        return "Cliente / SmartEnvios"
    if "equipe" in to or "time" in subject or "interno" in subject:
        return "Time interno"
    if any(x in to for x in ["gmail.com", "hotmail", "yahoo", "outlook"]):
        return "Pessoal / externo"
    if "suporte" in to or "support" in to or "atendimento" in subject:
        return "Suporte / atendimento"
    return "Outros"


def style_notes(body: str) -> list[str]:
    notes = []
    body_lower = body.lower()
    lines = [l.strip() for l in body.splitlines() if l.strip()]
    if len(body) < 200:
        notes.append("Resposta curta")
    elif len(body) < 600:
        notes.append("Resposta média")
    else:
        notes.append("Resposta longa")
    if re.search(r"\b(próximo|próximos|amanhã|segunda|prazo|deadline|até)\b", body_lower):
        notes.append("Próximo passo ou prazo explícito")
    if re.search(r"^(oi|olá|bom dia|boa tarde|opa)\b", body_lower):
        notes.append("Saudação informal")
    if re.search(r"(atenciosamente|abs|abraço|att\.?|att,)\s*$", body_lower):
        notes.append("Assinatura curta")
    if re.search(r"^\s*-\s*$|^\s*—\s*$", body, re.MULTILINE):
        notes.append("Assinatura com traço")
    if re.search(r"\?\s*$", body.strip()):
        notes.append("Termina com pergunta")
    if re.search(r"\b(obrigado|valeu|grato)\b", body_lower):
        notes.append("Agradecimento")
    if re.search(r"\b(conforme|segundo|como combinado)\b", body_lower):
        notes.append("Referência a acordo/combinado")
    return notes


def main():
    parser = argparse.ArgumentParser(description="Extract communication patterns from sent email samples")
    parser.add_argument("json_file", type=str, help="Path to email-samples-sent.json")
    parser.add_argument("--out", type=str, default=None, help="Output markdown path")
    args = parser.parse_args()

    p = Path(args.json_file)
    if not p.exists():
        print(f"File not found: {p}", file=sys.stderr)
        print("Run export-sent-samples.py first to generate it.", file=sys.stderr)
        sys.exit(1)

    with open(p, encoding="utf-8") as f:
        samples = json.load(f)

    by_context = {}
    for s in samples:
        ctx = infer_context(s)
        by_context.setdefault(ctx, []).append(s)

    lines = [
        "# Padrões de comunicação extraídos de e-mails enviados",
        "",
        "Gerado a partir de `email-samples-sent.json`. Use para alinhar rascunhos e respostas ao estilo real.",
        "",
        "---",
        "",
    ]

    for ctx in sorted(by_context.keys()):
        items = by_context[ctx]
        lines.append(f"## {ctx}")
        lines.append("")
        for s in items:
            subj = (s.get("subject") or "")[:60]
            to = (s.get("to") or "")[:50]
            body = (s.get("body") or "")[:500]
            notes = style_notes(s.get("body") or "")
            lines.append(f"- **Para:** {to}  ")
            lines.append(f"  **Assunto:** {subj}")
            lines.append(f"  **Estilo:** {', '.join(notes)}")
            if body:
                preview = body.replace("\n", " ").strip()[:200] + ("..." if len(body) > 200 else "")
                lines.append(f"  **Trecho:** {preview}")
            lines.append("")
        lines.append("")

    out_path = args.out or str(p.parent / "communication-patterns-from-samples.md")
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"Wrote {len(lines)} lines to {out_path}", file=sys.stderr)
    print(out_path)


if __name__ == "__main__":
    main()
