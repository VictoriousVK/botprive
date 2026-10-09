"""Knowledge base of the Mentor: only content Victor owns (ICT definitions in the skills, the
academy's courses, transcripts and sheets added by the team). Lexical search (BM25 on
normalised terms, title boost), filtered by the member's access rights before ranking, so a
paid module never leaks into a free member's answer.

The corpus is small (a few thousand passages); BM25 in Python is enough and needs no extra
service. A vector index (pgvector) can be added when faithfulness plateaus (ADR-010).
"""

from __future__ import annotations

import json
import math
import re
import unicodedata
from collections import Counter
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field
from sqlalchemy import delete, insert, select

from hedgefund.saas.db import knowledge_chunks, knowledge_docs, new_id, now_ms

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".claude" / "skills"
STOP = set("""
a au aux avec ce ces cet cette dans de des du elle en et est il ils je la le les leur lui ma mais me meme mes moi mon ne nos notre nous on ou par pas pour qu que qui sa se ses son sur ta te tes toi ton tu un une vos votre vous y
d l c j n s t qu est sont etre avoir fait faire plus tres tout tous toute toutes quand comme donc alors aussi entre sans sous vers chez ici la
the a an of to in on for and or is are be with as at by it this that from what how why when
""".split())
KEEP_SHORT = {"fvg", "ob", "bos", "mss", "ote", "smt", "amd", "adr", "bpr", "sb", "mb", "ny", "rr", "pd", "ce", "h1", "h4", "m1", "m5", "d1", "bsl", "ssl", "pdh", "pdl"}


def normalize(text: str) -> list[str]:
    t = unicodedata.normalize("NFKD", text.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    out = []
    for w in re.findall(r"[a-z0-9]+", t):
        if w in STOP or (len(w) < 3 and w not in KEEP_SHORT):
            continue
        if len(w) > 4 and w.endswith("s") and not w.endswith("ss"):
            w = w[:-1]
        for suf in ("ement", "ations", "ation", "ements"):
            if len(w) > len(suf) + 3 and w.endswith(suf):
                w = w[: -len(suf)]
                break
        out.append(w)
    return out


def chunk(text: str, size: int = 700, overlap: int = 120) -> list[str]:
    paras = [p.strip() for p in re.split(r"\n\s*\n|(?=\n#{1,4} )", text) if p.strip()]
    out: list[str] = []
    cur = ""
    for p in paras:
        if len(cur) + len(p) + 2 <= size:
            cur = f"{cur}\n\n{p}" if cur else p
            continue
        if cur:
            out.append(cur)
        while len(p) > size:
            out.append(p[:size])
            p = p[size - overlap:]
        cur = p
    if cur:
        out.append(cur)
    return out


class DocIn(BaseModel):
    title: str = Field(min_length=3, max_length=200)
    source: str = Field(default="faq", pattern=r"^(faq|transcript|fiche|definition)$")
    access: str = Field(default="academy_member", max_length=30)
    ref: str | None = Field(default=None, max_length=200)
    text: str = Field(min_length=20, max_length=200_000)


class Knowledge:
    def __init__(self, saas: Any):
        self.saas = saas
        self._cache: tuple[int, list[dict[str, Any]], dict[str, dict[str, Any]], dict[str, int], float] | None = None

    # ---- indexing ----
    def _insert_doc(self, conn: Any, source: str, title: str, access: str, ref: str | None, text: str, timestamps: list[int | None] | None = None) -> str:
        did = new_id("doc")
        conn.execute(insert(knowledge_docs).values(id=did, source=source, title=title[:200], access=access, ref=ref, version=str(now_ms()), created_at=now_ms()))
        rows = []
        for i, c in enumerate(chunk(text)):
            rows.append({"id": new_id("chk"), "doc_id": did, "position": i, "text": c, "timestamp_s": (timestamps or [None] * 10_000)[i] if timestamps else None,
                         "tokens": normalize(title + " " + c), "embedding": None})
        if rows:
            conn.execute(insert(knowledge_chunks), rows)
        return did

    def _delete_sources(self, conn: Any, sources: tuple[str, ...]) -> None:
        ids = [r.id for r in conn.execute(select(knowledge_docs.c.id).where(knowledge_docs.c.source.in_(sources)))]
        if ids:
            conn.execute(delete(knowledge_chunks).where(knowledge_chunks.c.doc_id.in_(ids)))
            conn.execute(delete(knowledge_docs).where(knowledge_docs.c.id.in_(ids)))

    def reindex(self) -> dict[str, int]:
        """Rebuilds the automatic sources (skills and academy); team documents are kept."""
        counts = {"skill": 0, "course": 0}
        with self.saas.db.system() as conn:
            self._delete_sources(conn, ("skill", "course"))
            for f in sorted(SKILLS.glob("*/SKILL.md")):
                text = f.read_text(encoding="utf-8")
                body = re.sub(r"^---.*?---\s*", "", text, flags=re.S)
                title = next((line.lstrip("# ").strip() for line in body.splitlines() if line.startswith("#")), f.parent.name)
                self._insert_doc(conn, "skill", title, "journal", f"skill:{f.parent.name}", body)
                counts["skill"] += 1
            store = getattr(self.saas.platform, "store", None)
            if store is not None:
                try:
                    courses = store.execute("SELECT * FROM courses WHERE status IN ('published', 'soon')")
                except Exception:  # noqa: BLE001 - academy not installed
                    courses = []
                for c in courses:
                    parts = store.execute("SELECT * FROM course_parts WHERE course_id = ? ORDER BY position", (c["id"],))
                    lines = [f"# {c['title']}", c["subtitle"] or "", c["description"] or ""]
                    for p in parts:
                        lines.append(f"## {p['title']}\n{p['summary'] or ''}")
                        try:
                            chapters = json.loads(p["chapters"] or "[]")
                        except ValueError:
                            chapters = []
                        for ch in chapters:
                            lines.append(f"- {ch.get('title', '')}")
                    self._insert_doc(conn, "course", c["title"], c["access"], f"course:{c['slug']}", "\n\n".join(x for x in lines if x))
                    counts["course"] += 1
        self._cache = None
        return counts

    def add(self, body: DocIn) -> str:
        with self.saas.db.system() as conn:
            did = self._insert_doc(conn, body.source, body.title, body.access, body.ref, body.text)
        self._cache = None
        return did

    def remove(self, doc_id: str) -> None:
        with self.saas.db.system() as conn:
            conn.execute(delete(knowledge_chunks).where(knowledge_chunks.c.doc_id == doc_id))
            if conn.execute(delete(knowledge_docs).where(knowledge_docs.c.id == doc_id)).rowcount == 0:
                raise LookupError("document introuvable")
        self._cache = None

    def docs(self) -> list[dict[str, Any]]:
        from sqlalchemy import func

        with self.saas.db.system() as conn:
            n = {r.doc_id: r.n for r in conn.execute(select(knowledge_chunks.c.doc_id, func.count().label("n")).group_by(knowledge_chunks.c.doc_id))}
            return [{**dict(r._mapping), "chunks": n.get(r.id, 0)} for r in conn.execute(select(knowledge_docs).order_by(knowledge_docs.c.source, knowledge_docs.c.title))]

    # ---- search ----
    def _load(self) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]], dict[str, int], float]:
        if self._cache is None:
            with self.saas.db.system() as conn:
                docs = {r.id: dict(r._mapping) for r in conn.execute(select(knowledge_docs))}
                chunks = [dict(r._mapping) for r in conn.execute(select(knowledge_chunks))]
            df: Counter = Counter()
            for c in chunks:
                df.update(set(c["tokens"]))
            avg = sum(len(c["tokens"]) for c in chunks) / len(chunks) if chunks else 1.0
            self._cache = (len(chunks), chunks, docs, dict(df), avg)
        _, chunks, docs, df, avg = self._cache
        return chunks, docs, df, avg

    def search(self, query: str, entitlements: set[str] | frozenset[str], k: int = 6, min_score: float = 1.0) -> list[dict[str, Any]]:
        chunks, docs, df, avg = self._load()
        q = normalize(query)
        if not q or not chunks:
            return []
        n = len(chunks)
        scored = []
        for c in chunks:
            d = docs.get(c["doc_id"])
            if d is None or d["access"] not in entitlements:
                continue
            tf = Counter(c["tokens"])
            title = set(normalize(d["title"]))
            s = 0.0
            for term in q:
                f = tf.get(term, 0)
                if not f:
                    continue
                idf = math.log(1 + (n - df.get(term, 0) + 0.5) / (df.get(term, 0) + 0.5))
                s += idf * f * 2.2 / (f + 1.2 * (0.25 + 0.75 * len(c["tokens"]) / avg))
                if term in title:
                    s += 0.5 * idf
            if s >= min_score:
                scored.append((s, c, d))
        scored.sort(key=lambda x: -x[0])
        return [{"chunk_id": c["id"], "doc_id": d["id"], "title": d["title"], "ref": d["ref"], "source": d["source"], "timestamp_s": c["timestamp_s"],
                 "text": c["text"], "score": round(s, 3)} for s, c, d in scored[:k]]
