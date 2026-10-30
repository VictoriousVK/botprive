"""Guardrails at three points: input, tool output, final output (ALLOW / BLOCK / REDACT /
ESCALATE), plus the numeric grounding check (CRITIC): every number an agent writes must come
from a tool output.

These rules are deliberately explicit and conservative. They are tested by the red-team set in
``evals/redteam.yaml``; a miss there is a catastrophic failure of the scorecard.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterable
from dataclasses import dataclass, field
from typing import Any, Literal

Action = Literal["ALLOW", "BLOCK", "REDACT", "ESCALATE"]

DISCLAIMER = (
    "Contenu pédagogique : ce n'est ni un conseil en investissement ni une recommandation "
    "personnalisée. Le trading comporte un risque de perte en capital ; les performances "
    "passées ne préjugent pas des performances futures."
)


@dataclass
class Decision:
    stage: str
    action: Action
    reasons: list[str] = field(default_factory=list)
    text: str | None = None  # the (possibly redacted) text
    flags: set[str] = field(default_factory=set)

    def as_dict(self) -> dict[str, Any]:
        return {"stage": self.stage, "action": self.action, "reason": "; ".join(self.reasons) or "ok", "flags": sorted(self.flags)}


def _norm(text: str) -> str:
    t = unicodedata.normalize("NFKD", text.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", t.replace("’", "'"))


def _any(patterns: Iterable[str], text: str) -> list[str]:
    return [p for p in patterns if re.search(p, text)]


# ---------------------------------------------------------------- personal data
_PII = [
    ("email", re.compile(r"[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}")),
    ("iban", re.compile(r"\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){3,7}\b")),
    ("card", re.compile(r"\b(?:\d[ -]?){13,19}\b")),
    ("phone", re.compile(r"(?<![\w.])\+?\d[\d .-]{7,16}\d(?![\w.])")),
    ("password", re.compile(r"(?i)\b(mot de passe|password|mdp|pwd)\s*[:=]\s*\S+")),
]


def _luhn(digits: str) -> bool:
    d = [int(c) for c in digits][::-1]
    return sum(x if i % 2 == 0 else (x * 2 - 9 if x * 2 > 9 else x * 2) for i, x in enumerate(d)) % 10 == 0


def redact(text: str) -> tuple[str, set[str]]:
    found: set[str] = set()

    def sub(kind: str):
        def f(m: re.Match) -> str:
            raw = m.group(0)
            if kind == "card":
                digits = re.sub(r"\D", "", raw)
                if not _luhn(digits):
                    return raw
            if kind == "phone":
                digits = re.sub(r"\D", "", raw)
                if len(digits) < 9 or re.fullmatch(r"\d+([.,]\d+)?", raw.strip()):
                    return raw  # a price or a quantity, not a phone number
            found.add(kind)
            return f"[{kind} masqué]"
        return f

    for kind, rx in _PII:
        text = rx.sub(sub(kind), text)
    return text, found


# ---------------------------------------------------------------- input
INJECTION = [
    r"ignore[rz]? (all |toutes? )?(the |les )?(previous |precedentes? )?(instructions|consignes|regles)",
    r"(oublie|forget|disregard)[sz]? (tout|all|everything|tes|your|les|the) (instructions|consignes|regles|rules|previous)",
    r"(system|developer) (prompt|message)", r"prompt (systeme|system)", r"</?(system|assistant|instructions?)>",
    r"(tu es|you are) (maintenant|desormais|now) ", r"nouveau role|new role|jailbreak|mode developpeur|developer mode|\bdan\b",
    r"(revele|reveal|affiche|print|show)[sz]? (ton|tes|your|le|the) (prompt|instructions|consignes|system)",
    r"(execute|place|passe|send|envoie)[sz]? (un |l'|the |an )?(ordre|order|trade) (maintenant|now|sans|without)",
    r"(desactive|disable|contourne|bypass)[sz]? (le |la |the )?(risk|risque|garde-fou|guardrail|limite)",
]
ADVICE = [
    r"(dois|devrais|faut)[- ]?(je|il) (acheter|vendre|entrer|shorter|prendre)",
    r"(should|must) i (buy|sell|short|long|enter)",
    r"\b(je|j') ?(dois|devrais) (acheter|vendre|entrer|shorter|prendre|couper|fermer)",
    r"\b(c'est|est-ce) (le )?(bon )?moment (pour|d')? ?(acheter|vendre|entrer)",
    r"(je|j') (achete|vends|entre|shorte) (ou pas|maintenant|ou)",
    r"(donne|envoie|file|passe)[sz]?[- ]?(moi|nous)? (un |une |des |le |la |les |tes |vos |ton |votre )?(signal|signaux|entree|entrees|trades?|setups? du jour)",
    r"(combien|quel|quels) (de )?(lots?|taille) (je )?(dois|devrais|mettre|prendre)",
    r"(achat|vente|buy|sell) (ou|or) (vente|achat|sell|buy) ",
    r"(ou|where) (mettre|placer|put) (mon|le|my) (sl|stop|tp) (pour|sur|on) (ce|cet|this|mon)",
    r"(garantis|garanti|assure)[sz]?[- ]?(moi|vous)? (un |des )?(gain|profit)",
]


def check_input(text: str, max_len: int = 4000) -> Decision:
    d = Decision("input", "ALLOW")
    if len(text) > max_len:
        d.action, d.reasons = "BLOCK", [f"message trop long ({len(text)} caractères, {max_len} maximum)"]
        return d
    red, pii = redact(text)
    n = _norm(red)
    inj = _any(INJECTION, n)
    adv = _any(ADVICE, n)
    d.text = red
    if pii:
        d.action = "REDACT"
        d.flags |= {f"pii:{k}" for k in pii}
        d.reasons.append("données personnelles masquées")
    if inj:
        d.flags.add("injection")
        d.reasons.append("tentative d'instruction détectée : traitée comme du texte")
    if adv:
        d.flags.add("advice_request")
        d.reasons.append("demande de conseil personnalisé : réponse pédagogique uniquement")
    return d


# ---------------------------------------------------------------- tool output
def _strings(obj: Any) -> Iterable[str]:
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _strings(v)
    elif isinstance(obj, (list, tuple)):
        for v in obj:
            yield from _strings(v)


def scan_tool_output(data: Any) -> Decision:
    """External content (notes, news, alert text) is data. A hit is recorded and the agent is
    told so; the content itself is not executed, whatever it says."""
    d = Decision("tool_output", "ALLOW")
    for s in _strings(data):
        if _any(INJECTION, _norm(s)):
            d.action = "ESCALATE"
            d.flags.add("injection")
            d.reasons = ["contenu d'outil contenant des instructions : ignoré en tant qu'instruction"]
            break
    return d


# ---------------------------------------------------------------- final output
PROMISE = [
    r"\bgaranti[es]?\b", r"\bsans (aucun )?risque\b", r"\brisk[- ]free\b", r"\bguaranteed?\b", r"\b(gain|profit|rendement|resultat)s? (assure|certain|garanti)",
    r"\ba coup sur\b", r"\b100 ?% (de )?(reussite|gagnant|win|fiable|sur)", r"\b(devenir|deviendrez|devenez) riches?\b",
    r"\bvous (allez|aller) (gagner|doubler|multiplier)", r"\b(sure|easy) (win|money|profit)", r"\bargent facile\b", r"\bne (peut|pouvez) pas perdre\b",
    r"\bjamais de perte\b", r"\b(doubler|tripler) (votre|ton) (capital|compte)",
]
INSTRUCTION = [
    r"\b(achetez|vendez|shortez)\b", r"(^|[.!] )(achete|vends) ", r"\bprenez (ce|le|un|cette) (trade|position|entree|setup)",
    r"\bentrez (en position|long|short|maintenant|a l'achat|a la vente|sur)", r"\bplacez (un|votre|l') ordre", r"\bouvrez (une|la|votre) position",
    r"\b(buy|sell) now\b", r"\bgo (long|short) (now|here)\b", r"\bmettez (\d|un|votre) (lot|stop)", r"\bcoupez (votre|la|ta) position maintenant",
]
PSYCH = [
    r"\b(vous etes|tu es|you are|you're|il est|elle est) (un |une |a |an )?(trop |tres |un peu |plutot |vraiment )?(anxieu|impulsi|emoti|avide|cupide|peureu|faible|stresse|nerveu|irrationnel|immature|paresseu|indiscipline|narciss|egoiste|compulsi|joueur|accro|addict|lache)",
    r"\b(depression|depressif|bipolaire|narcissique|pathologique|tdah|adhd|trouble (anxieux|de la personnalite|obsessionnel|du jeu)|addiction au jeu|joueur compulsif|gambling disorder|personality disorder)\b",
    r"\bvotre (personnalite|psychologie|profil psychologique|caractere) (est|montre|revele)",
    r"\b(vous|tu) (manquez|manques) de (courage|volonte|maturite|caractere)",
]


def check_final(text: str, *, require_no_instruction: bool = True) -> Decision:
    d = Decision("final", "ALLOW", text=text)
    n = _norm(text)
    promise, instr, psych = _any(PROMISE, n), _any(INSTRUCTION, n) if require_no_instruction else [], _any(PSYCH, n)
    if promise:
        d.flags.add("promise")
        d.reasons.append("promesse de gain")
    if instr:
        d.flags.add("trade_instruction")
        d.reasons.append("instruction de trade")
    if psych:
        d.flags.add("psych_label")
        d.reasons.append("étiquette psychologique")
    red, pii = redact(text)
    if pii:
        d.flags |= {f"pii:{k}" for k in pii}
        d.text = red
    if promise or instr or psych:
        d.action = "BLOCK"
    elif pii:
        d.action = "REDACT"
    return d


# ---------------------------------------------------------------- numeric grounding (CRITIC)
_SKIP = [
    re.compile(r"\b\d{1,2}[:h]\d{2}\b"),  # clock times 10:00, 9h50
    re.compile(r"\b\d{4}-\d{2}-\d{2}\b"),  # dates
    re.compile(r"\b\d{1,2}/\d{1,2}(/\d{2,4})?\b"),
    re.compile(r"\b[A-Za-z]{1,3}\d{1,4}\b"),  # M5, H1, D1, NAS100, US30, W40, IPDA20
    re.compile(r"\b\d+[A-Za-z]{2,}\d*\b"),  # 3R0 style tokens are left to the number rule
    re.compile(r"^\s*\d+[.)] ", re.M),  # list numbering
]
_NUM = re.compile(r"(?<![\w.,])[-−+]?\d{1,3}(?:[  ]\d{3})+(?:[.,]\d+)?(?![\w])|(?<![\w.,])[-−+]?\d+(?:[.,]\d+)?")


def numbers_in(text: str) -> list[tuple[float, int]]:
    """Numbers written in ``text`` as (value, decimals shown). French and English notations."""
    t = text
    for rx in _SKIP:
        t = rx.sub(" ", t)
    out = []
    for m in _NUM.finditer(t):
        raw = m.group(0).replace("−", "-").replace(" ", "").replace(" ", "")
        dec = 0
        if "," in raw or "." in raw:
            sep = "," if "," in raw else "."
            raw = raw.replace(sep, ".")
            dec = len(raw.split(".")[1])
        try:
            out.append((float(raw), dec))
        except ValueError:
            continue
    return out


def _flatten_numbers(obj: Any) -> list[float]:
    out: list[float] = []
    if isinstance(obj, bool):
        return out
    if isinstance(obj, (int, float)):
        out.append(float(obj))
    elif isinstance(obj, dict):
        for v in obj.values():
            out.extend(_flatten_numbers(v))
    elif isinstance(obj, (list, tuple)):
        for v in obj:
            out.extend(_flatten_numbers(v))
    elif isinstance(obj, str):
        out.extend(v for v, _ in numbers_in(obj))
    return out


def allowed_values(evidence: Any) -> list[float]:
    vals = _flatten_numbers(evidence)
    extra = []
    for v in vals:
        if 0 < abs(v) <= 1.0:
            extra.append(v * 100)  # ratios shown as percentages
    return vals + extra


def ungrounded_numbers(text: str, evidence: Any) -> list[float]:
    """Numbers of ``text`` that no evidence value explains (tolerance = the precision shown)."""
    allowed = allowed_values(evidence)
    bad = []
    for x, dec in numbers_in(text):
        tol = 0.5 * 10 ** (-dec) + 1e-9
        if not any(abs(abs(x) - abs(v)) <= tol or abs(round(abs(v), dec) - abs(x)) <= 1e-9 for v in allowed):
            bad.append(x)
    return bad
