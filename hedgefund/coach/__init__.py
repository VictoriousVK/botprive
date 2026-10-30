"""IA Trading Coach: answers members' questions on ICT (order blocks, FVG, liquidity, market
structure, killzones, Silver Bullet...) from a written knowledge base.

Faithfulness comes from three rules:

1. The whole knowledge base (``knowledge/*.md``, one file per topic) is sent with every
   question, in a cached system prompt. The model doesn't have to "remember" ICT: it reads the
   reference text each time.
2. The prompt tells it to answer from that text first, to say plainly when a point is not in
   the base, never to invent times, numbers or quotes, and never to give a trade signal.
3. Each answer ends with the topics it used (``SOURCES:``), shown to the member, so anyone
   can check the answer against the reference.

To teach the coach something new or correct it: edit or add a Markdown file in
``hedgefund/coach/knowledge/`` (see its README.md), then restart the platform.
"""

from __future__ import annotations

import logging
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

log = logging.getLogger("hedgefund.coach")

KNOWLEDGE_DIR = Path(__file__).parent / "knowledge"
OUT_OF_BASE = "hors-base"
_SOURCES = re.compile(r"\n?\s*SOURCES\s*:\s*(.*)\s*$", re.IGNORECASE)

SCHEMA = """
CREATE TABLE IF NOT EXISTS coach_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id INTEGER NOT NULL,
    ts INTEGER NOT NULL,
    day TEXT NOT NULL,
    question TEXT NOT NULL,
    sources TEXT NOT NULL,
    out_of_base INTEGER NOT NULL DEFAULT 0,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_coach_member_day ON coach_questions(member_id, day);
"""


class CoachError(RuntimeError):
    pass


@dataclass(frozen=True)
class Fiche:
    id: str
    title: str
    body: str


def load_knowledge(directory: Path = KNOWLEDGE_DIR) -> list[Fiche]:
    """Every ``NN-topic.md`` file: the first ``# `` line is the title, the file name is the id."""
    out = []
    for p in sorted(directory.glob("*.md")):
        if p.name.lower() == "readme.md":
            continue
        text = p.read_text(encoding="utf-8").strip()
        first = text.splitlines()[0] if text else ""
        title = first[2:].strip() if first.startswith("# ") else p.stem
        out.append(Fiche(id=p.stem, title=title, body=text))
    if not out:
        raise CoachError(f"base de connaissances vide : {directory}")
    return out


RULES = """\
Tu es « Coach ICT », l'assistant pédagogique de la plateforme Liberté Financière (formation \
Victorious Trader de Victor Faye). Tu réponds aux questions des membres sur la méthodologie \
ICT (Inner Circle Trader, Michael J. Huddleston) et sur le trading en général.

Règles, par ordre de priorité :
1. Source de vérité : la BASE DE CONNAISSANCES ci-dessous. Appuie chaque définition, horaire, \
niveau ou règle sur elle, avec ses termes. Si la base et ta mémoire divergent, la base gagne.
2. Si la question sort de la base : dis-le en une phrase (« Ce point n'est pas dans ma base de \
référence »), puis réponds seulement si c'est un concept ICT bien établi, en restant prudent, \
et invite le membre à vérifier en live ou avec Victor. Sinon, dis que tu ne sais pas.
3. N'invente jamais : pas d'horaire, de pourcentage, de citation d'ICT, de règle ou de \
« modèle secret » qui ne soit pas dans la base. Quand les enseignements d'ICT varient selon les \
années, dis-le.
4. Pas de conseil en investissement ni de signal : ne dis jamais d'acheter ou de vendre un actif \
maintenant, ne donne pas de niveau d'entrée sur le marché du jour, ne promets aucun gain. Tu \
peux expliquer une méthode, un exemple chiffré fictif, ou aider à analyser un scénario que le \
membre décrit, en rappelant que la décision et le risque lui appartiennent.
5. Pédagogie : réponds dans la langue du membre (français par défaut), clairement, du plus \
simple au plus précis. Donne la définition, comment le repérer sur le graphique, comment \
l'utiliser, et l'erreur fréquente à éviter. Un exemple chiffré court aide souvent. Environ \
250 mots sauf si on te demande plus de détails. Markdown simple (titres courts, listes, gras).
6. Horaires : ICT raisonne en heure de New York. Donne aussi l'heure GMT (Dakar) avec la table \
de conversion de la base, en précisant heure d'été / heure d'hiver de New York.
7. Dernière ligne, obligatoire et seule sur sa ligne : « SOURCES: » suivi des identifiants des \
fiches utilisées, séparés par des virgules (ex. « SOURCES: 04-order-block, 05-fvg-et-desequilibres »), \
ou « SOURCES: hors-base » si la base ne couvre pas la question.
"""


def system_prompt(fiches: list[Fiche]) -> str:
    parts = [RULES, "\n<base_de_connaissances>"]
    for f in fiches:
        parts.append(f'\n<fiche id="{f.id}">\n{f.body}\n</fiche>')
    parts.append("\n</base_de_connaissances>")
    return "".join(parts)


def split_sources(text: str, known: set[str]) -> tuple[str, list[str], bool]:
    """Removes the SOURCES line; returns (answer, fiche ids, out_of_base)."""
    m = _SOURCES.search(text)
    if not m:
        return text.strip(), [], False
    ids = [s.strip().strip("`*.").lower() for s in m.group(1).split(",") if s.strip()]
    out_of_base = OUT_OF_BASE in ids
    return text[: m.start()].strip(), [i for i in ids if i in known], out_of_base


@dataclass
class Coach:
    client: Any
    model: str = "claude-sonnet-5-5"
    daily_limit: int = 30
    max_tokens: int = 2000
    fiches: list[Fiche] = field(default_factory=load_knowledge)

    def __post_init__(self) -> None:
        self.system = system_prompt(self.fiches)
        self.titles = {f.id: f.title for f in self.fiches}

    @classmethod
    def from_settings(cls, settings: Any) -> Coach:
        try:
            import anthropic
        except ImportError as e:
            raise CoachError("le coach IA a besoin du paquet anthropic : pip install -e \".[research]\"") from e
        return cls(anthropic.Anthropic(max_retries=2, timeout=90.0), model=settings.coach_model, daily_limit=settings.coach_daily_limit)

    # ---------------- quota ----------------
    @staticmethod
    def _day(now: float) -> str:
        return time.strftime("%Y-%m-%d", time.gmtime(now))

    def used_today(self, store: Any, member_id: int, now: float | None = None) -> int:
        store.executescript(SCHEMA)
        return store.execute("SELECT COUNT(*) AS n FROM coach_questions WHERE member_id = ? AND day = ?", (member_id, self._day(now or time.time())))[0]["n"]

    def remaining(self, store: Any, member_id: int) -> int:
        return max(0, self.daily_limit - self.used_today(store, member_id))

    # ---------------- answering ----------------
    def ask(self, question: str, history: list[dict[str, str]] | None = None) -> dict[str, Any]:
        messages = [{"role": h["role"], "content": h["content"]} for h in (history or [])[-8:] if h.get("role") in ("user", "assistant") and h.get("content")]
        while messages and messages[0]["role"] != "user":  # a conversation must start with the member
            messages.pop(0)
        messages.append({"role": "user", "content": question})
        try:
            msg = self.client.messages.create(
                model=self.model,
                max_tokens=self.max_tokens,
                system=[{"type": "text", "text": self.system, "cache_control": {"type": "ephemeral"}}],
                messages=messages,
            )
        except Exception as e:
            log.exception("coach IA : appel au modèle impossible")
            raise CoachError("le coach est momentanément indisponible : réessayez dans quelques minutes") from e
        if getattr(msg, "stop_reason", None) == "refusal":
            return {"answer": "Je ne peux pas répondre à cette question. Reformulez-la autour d'un concept de trading ou d'ICT.", "sources": [], "out_of_base": True, "usage": {}}
        text = "".join(getattr(b, "text", "") for b in msg.content if getattr(b, "type", None) == "text")
        answer, ids, out = split_sources(text, set(self.titles))
        u = getattr(msg, "usage", None)
        usage = {"input_tokens": getattr(u, "input_tokens", 0) or 0, "output_tokens": getattr(u, "output_tokens", 0) or 0}
        return {"answer": answer, "sources": [{"id": i, "title": self.titles[i]} for i in ids], "out_of_base": out, "usage": usage}

    def answer_for(self, store: Any, member_id: int, question: str, history: list[dict[str, str]] | None = None) -> dict[str, Any]:
        """Checks the daily quota, answers, and records the question (for the admin page)."""
        now = time.time()
        if self.used_today(store, member_id, now) >= self.daily_limit:
            raise CoachError(f"limite de {self.daily_limit} questions par jour atteinte : revenez demain")
        res = self.ask(question, history)
        store.execute(
            "INSERT INTO coach_questions (member_id, ts, day, question, sources, out_of_base, input_tokens, output_tokens) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (member_id, int(now), self._day(now), question[:2000], ",".join(s["id"] for s in res["sources"]), int(res["out_of_base"]), res["usage"].get("input_tokens", 0), res["usage"].get("output_tokens", 0)),
        )
        res["remaining"] = max(0, self.daily_limit - self.used_today(store, member_id, now))
        res.pop("usage", None)
        return res

    @staticmethod
    def recent_questions(store: Any, limit: int = 200) -> list[dict[str, Any]]:
        store.executescript(SCHEMA)
        rows = store.execute(
            "SELECT q.id, q.ts, q.question, q.sources, q.out_of_base, m.email FROM coach_questions q LEFT JOIN members m ON m.id = q.member_id ORDER BY q.ts DESC LIMIT ?", (limit,)
        )
        return [{**dict(r), "out_of_base": bool(r["out_of_base"]), "sources": [s for s in r["sources"].split(",") if s]} for r in rows]
