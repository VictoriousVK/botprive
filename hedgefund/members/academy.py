"""Academy: courses made of video parts (long videos welcome), chapters, progress.

Videos are not stored here: they live on a video host that streams them adaptively (a 40-minute
video is too heavy to serve from the platform). The admin pastes the link given by the host;
the platform recognises the provider, keeps only its identifiers and rebuilds the player URL
from a fixed list of domains, so a member can never be sent to an arbitrary page.
Supported: Bunny Stream, Cloudflare Stream, Mux, Vimeo, YouTube (privacy-enhanced mode), and
MP4/WebM files on hosts listed in LF_MEDIA_HOSTS. Restrict playback to your domain in the
host's settings, since an embed link can otherwise be shared.
"""

from __future__ import annotations

import json
import re
import secrets
import time
from typing import Any
from urllib.parse import parse_qs, urlparse

from hedgefund.members.site import MemberSettings, SiteConfig

SCHEMA = """
CREATE TABLE IF NOT EXISTS courses (
    id TEXT PRIMARY KEY,
    slug TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    subtitle TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    level TEXT NOT NULL DEFAULT '',
    access TEXT NOT NULL DEFAULT 'academy_member',
    status TEXT NOT NULL DEFAULT 'draft',
    position INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS course_parts (
    id TEXT PRIMARY KEY,
    course_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    title TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '',
    duration_s INTEGER NOT NULL DEFAULT 0,
    provider TEXT NOT NULL,
    video_ref TEXT NOT NULL,
    chapters TEXT NOT NULL DEFAULT '[]',
    free_preview INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_parts_course ON course_parts(course_id, position);
CREATE TABLE IF NOT EXISTS course_progress (
    member_id INTEGER NOT NULL,
    part_id TEXT NOT NULL,
    position_s INTEGER NOT NULL DEFAULT 0,
    completed INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (member_id, part_id)
);
"""

ACCESS = {
    "academy_free": "Gratuit",
    "academy_member": "Abonnés",
    "formation_ict": "Formation ICT Victorious Trader",
    "formation_ea": "Formation EA MT5",
    "formation_quant": "Formation Quant et IA",
}
STATUSES = {"draft": "Brouillon", "soon": "En préparation", "published": "Publié"}
PROVIDERS = {"bunny": "Bunny Stream", "cloudflare": "Cloudflare Stream", "mux": "Mux", "vimeo": "Vimeo", "youtube": "YouTube", "file": "Fichier vidéo"}
# Domains the site may frame (Content-Security-Policy frame-src).
FRAME_SOURCES = (
    "https://iframe.mediadelivery.net",
    "https://*.cloudflarestream.com",
    "https://player.mux.com",
    "https://player.vimeo.com",
    "https://www.youtube-nocookie.com",
)
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
MAX_DURATION_S = 4 * 3600


class AcademyError(ValueError):
    pass


def _clean(s: Any, n: int) -> str:
    return str(s or "").strip()[:n]


def parse_video(link: str, provider: str = "", media_hosts: tuple[str, ...] = ()) -> tuple[str, str]:
    """Recognises a video link (or a bare identifier with an explicit provider) -> (provider, ref)."""
    link = link.strip()
    if not link or len(link) > 500:
        raise AcademyError("lien vidéo manquant ou trop long")
    u = urlparse(link if "://" in link else "")
    host = (u.hostname or "").lower()
    path = [p for p in u.path.split("/") if p]
    if host:
        if u.scheme != "https":
            raise AcademyError("le lien vidéo doit commencer par https://")
        if host in ("iframe.mediadelivery.net", "video.bunnycdn.com") and len(path) >= 3 and path[0] in ("embed", "play"):
            provider, ref = "bunny", f"{path[1]}/{path[2]}"
        elif host.endswith(".cloudflarestream.com") and host.startswith("customer-") and path:
            provider, ref = "cloudflare", f"{host.split('.')[0]}/{path[0]}"
        elif host in ("player.mux.com", "stream.mux.com") and path:
            provider, ref = "mux", path[0].split(".")[0]
        elif host in ("vimeo.com", "www.vimeo.com", "player.vimeo.com"):
            ids = [p for p in path if p != "video"]
            h = parse_qs(u.query).get("h", [""])[0]
            provider, ref = "vimeo", "/".join(x for x in (ids[0] if ids else "", h or (ids[1] if len(ids) > 1 else "")) if x)
        elif host in ("youtu.be",) and path:
            provider, ref = "youtube", path[0]
        elif host in ("youtube.com", "www.youtube.com", "m.youtube.com", "www.youtube-nocookie.com"):
            if path[:1] in (["embed"], ["shorts"], ["live"]) and len(path) > 1:
                provider, ref = "youtube", path[1]
            else:
                provider, ref = "youtube", parse_qs(u.query).get("v", [""])[0]
        elif host in media_hosts:
            if not u.path.lower().endswith((".mp4", ".webm")):
                raise AcademyError("fichier vidéo : formats .mp4 ou .webm uniquement")
            provider, ref = "file", link
        else:
            raise AcademyError("hébergeur vidéo non reconnu (Bunny, Cloudflare Stream, Mux, Vimeo, YouTube, ou un domaine de LF_MEDIA_HOSTS)")
    elif provider not in PROVIDERS or provider == "file":
        raise AcademyError("collez le lien complet de la vidéo")
    else:
        ref = link
    checks = {
        "bunny": r"^\d{1,12}/[0-9a-fA-F-]{36}$",
        "cloudflare": r"^customer-[a-z0-9]{4,40}/[0-9a-f]{32}$",
        "mux": r"^[A-Za-z0-9]{10,80}$",
        "vimeo": r"^\d{4,12}(/[0-9a-f]{6,20})?$",
        "youtube": r"^[A-Za-z0-9_-]{11}$",
        "file": r"^https://\S+$",
    }
    if not re.match(checks[provider], ref):
        raise AcademyError(f"identifiant {PROVIDERS[provider]} invalide")
    return provider, ref


def player(provider: str, ref: str, media_hosts: tuple[str, ...] = ()) -> dict[str, str] | None:
    """Player URL rebuilt from the stored identifiers only."""
    if provider == "bunny":
        lib, vid = ref.split("/")
        return {"kind": "iframe", "src": f"https://iframe.mediadelivery.net/embed/{lib}/{vid}?autoplay=false&preload=true&responsive=true"}
    if provider == "cloudflare":
        cust, uid = ref.split("/")
        return {"kind": "iframe", "src": f"https://{cust}.cloudflarestream.com/{uid}/iframe"}
    if provider == "mux":
        return {"kind": "iframe", "src": f"https://player.mux.com/{ref}"}
    if provider == "vimeo":
        vid, _, h = ref.partition("/")
        return {"kind": "iframe", "src": f"https://player.vimeo.com/video/{vid}?dnt=1" + (f"&h={h}" if h else "")}
    if provider == "youtube":
        return {"kind": "iframe", "src": f"https://www.youtube-nocookie.com/embed/{ref}?rel=0&modestbranding=1"}
    if provider == "file" and (urlparse(ref).hostname or "").lower() in media_hosts:
        return {"kind": "video", "src": ref}
    return None


def parse_chapters(raw: Any, duration_s: int) -> list[dict[str, Any]]:
    """Chapters as a list of {t, title}, or text lines like "12:30 Le Silver Bullet"."""
    items: list[dict[str, Any]] = []
    if isinstance(raw, str):
        for line in raw.splitlines():
            m = re.match(r"^\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\s+(.+)$", line)
            if line.strip() and not m:
                raise AcademyError(f"chapitre illisible : « {line.strip()[:40]} » (format 12:30 Titre)")
            if m:
                h, mi, s, title = m.groups()
                items.append({"t": int(h or 0) * 3600 + int(mi) * 60 + int(s), "title": title.strip()[:120]})
    elif isinstance(raw, list):
        for c in raw:
            items.append({"t": int(c.get("t", 0)), "title": _clean(c.get("title"), 120)})
    items.sort(key=lambda c: c["t"])
    if len(items) > 60 or any(c["t"] < 0 or (duration_s and c["t"] > duration_s) or not c["title"] for c in items):
        raise AcademyError("chapitres invalides (60 maximum, dans la durée de la vidéo)")
    return items


class Academy:
    def __init__(self, store: Any, site: SiteConfig, settings: MemberSettings, now=time.time):
        self.store, self.site, self.settings, self.now = store, site, settings, now
        store.executescript(SCHEMA)

    # ---------------- admin: courses ----------------
    def save_course(self, data: dict[str, Any], course_id: str | None = None) -> dict[str, Any]:
        slug = _clean(data.get("slug"), 60).lower()
        title = _clean(data.get("title"), 120)
        access = data.get("access", "academy_member")
        status = data.get("status", "draft")
        if not SLUG_RE.match(slug):
            raise AcademyError("adresse (slug) : lettres minuscules, chiffres et tirets, ex. methode-ict")
        if len(title) < 3:
            raise AcademyError("titre trop court")
        if access not in ACCESS or status not in STATUSES:
            raise AcademyError("accès ou statut inconnu")
        now = int(self.now())
        clash = self.store.execute("SELECT id FROM courses WHERE slug = ?", (slug,))
        if clash and clash[0]["id"] != course_id:
            raise AcademyError("un autre cours utilise déjà cette adresse")
        fields = (slug, title, _clean(data.get("subtitle"), 200), _clean(data.get("description"), 4000), _clean(data.get("level"), 40), access, status, int(data.get("position", 0) or 0))
        if course_id:
            if not self.store.execute("SELECT 1 FROM courses WHERE id = ?", (course_id,)):
                raise AcademyError("cours introuvable")
            self.store.execute("UPDATE courses SET slug=?, title=?, subtitle=?, description=?, level=?, access=?, status=?, position=?, updated_at=? WHERE id=?", (*fields, now, course_id))
        else:
            course_id = "crs_" + secrets.token_hex(6)
            self.store.execute("INSERT INTO courses (slug, title, subtitle, description, level, access, status, position, created_at, updated_at, id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", (*fields, now, now, course_id))
        return self.course_admin(course_id)

    def delete_course(self, course_id: str) -> None:
        with self.store.atomic():
            parts = [r["id"] for r in self.store.execute("SELECT id FROM course_parts WHERE course_id = ?", (course_id,))]
            for pid in parts:
                self.store.execute("DELETE FROM course_progress WHERE part_id = ?", (pid,))
            self.store.execute("DELETE FROM course_parts WHERE course_id = ?", (course_id,))
            self.store.execute("DELETE FROM courses WHERE id = ?", (course_id,))

    # ---------------- admin: parts ----------------
    def save_part(self, course_id: str, data: dict[str, Any], part_id: str | None = None) -> dict[str, Any]:
        if not self.store.execute("SELECT 1 FROM courses WHERE id = ?", (course_id,)):
            raise AcademyError("cours introuvable")
        title = _clean(data.get("title"), 160)
        if len(title) < 2:
            raise AcademyError("titre de la partie trop court")
        duration = int(data.get("duration_s") or 0)
        if not 0 <= duration <= MAX_DURATION_S:
            raise AcademyError("durée invalide (4 heures maximum)")
        provider, ref = parse_video(str(data.get("video", "")), str(data.get("provider", "")), self.settings.media_hosts)
        chapters = json.dumps(parse_chapters(data.get("chapters", []), duration), ensure_ascii=False)
        now = int(self.now())
        free = int(bool(data.get("free_preview")))
        summary = _clean(data.get("summary"), 2000)
        if part_id:
            rows = self.store.execute("SELECT course_id FROM course_parts WHERE id = ?", (part_id,))
            if not rows or rows[0]["course_id"] != course_id:
                raise AcademyError("partie introuvable")
            self.store.execute(
                "UPDATE course_parts SET title=?, summary=?, duration_s=?, provider=?, video_ref=?, chapters=?, free_preview=?, updated_at=? WHERE id=?",
                (title, summary, duration, provider, ref, chapters, free, now, part_id),
            )
        else:
            pos = self.store.execute("SELECT COALESCE(MAX(position), 0) + 1 AS p FROM course_parts WHERE course_id = ?", (course_id,))[0]["p"]
            part_id = "prt_" + secrets.token_hex(6)
            self.store.execute(
                "INSERT INTO course_parts (id, course_id, position, title, summary, duration_s, provider, video_ref, chapters, free_preview, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (part_id, course_id, pos, title, summary, duration, provider, ref, chapters, free, now, now),
            )
        self.store.execute("UPDATE courses SET updated_at = ? WHERE id = ?", (now, course_id))
        return self.course_admin(course_id)

    def delete_part(self, course_id: str, part_id: str) -> dict[str, Any]:
        with self.store.atomic():
            self.store.execute("DELETE FROM course_progress WHERE part_id = ?", (part_id,))
            self.store.execute("DELETE FROM course_parts WHERE id = ? AND course_id = ?", (part_id, course_id))
            self._renumber(course_id)
        return self.course_admin(course_id)

    def move_part(self, course_id: str, part_id: str, delta: int) -> dict[str, Any]:
        with self.store.atomic():
            ids = [r["id"] for r in self.store.execute("SELECT id FROM course_parts WHERE course_id = ? ORDER BY position", (course_id,))]
            if part_id not in ids:
                raise AcademyError("partie introuvable")
            i = ids.index(part_id)
            j = max(0, min(len(ids) - 1, i + (1 if delta > 0 else -1)))
            ids[i], ids[j] = ids[j], ids[i]
            for pos, pid in enumerate(ids, 1):
                self.store.execute("UPDATE course_parts SET position = ? WHERE id = ?", (pos, pid))
        return self.course_admin(course_id)

    def _renumber(self, course_id: str) -> None:
        for pos, r in enumerate(self.store.execute("SELECT id FROM course_parts WHERE course_id = ? ORDER BY position", (course_id,)), 1):
            self.store.execute("UPDATE course_parts SET position = ? WHERE id = ?", (pos, r["id"]))

    def _parts(self, course_id: str) -> list[dict[str, Any]]:
        return [dict(r) for r in self.store.execute("SELECT * FROM course_parts WHERE course_id = ? ORDER BY position", (course_id,))]

    def course_admin(self, course_id: str) -> dict[str, Any]:
        rows = self.store.execute("SELECT * FROM courses WHERE id = ?", (course_id,))
        if not rows:
            raise AcademyError("cours introuvable")
        c = dict(rows[0])
        c["parts"] = [{**p, "chapters": json.loads(p["chapters"]), "provider_label": PROVIDERS.get(p["provider"], p["provider"]), "player": player(p["provider"], p["video_ref"], self.settings.media_hosts)} for p in self._parts(course_id)]
        return c

    def list_admin(self) -> list[dict[str, Any]]:
        rows = self.store.execute("SELECT c.*, (SELECT COUNT(*) FROM course_parts p WHERE p.course_id = c.id) AS parts, (SELECT COALESCE(SUM(duration_s), 0) FROM course_parts p WHERE p.course_id = c.id) AS duration_s FROM courses c ORDER BY position, created_at")
        return [dict(r) for r in rows]

    # ---------------- public / members ----------------
    def catalog(self) -> list[dict[str, Any]]:
        rows = self.store.execute(
            "SELECT c.*, (SELECT COUNT(*) FROM course_parts p WHERE p.course_id = c.id) AS parts, (SELECT COALESCE(SUM(duration_s), 0) FROM course_parts p WHERE p.course_id = c.id) AS duration_s, "
            "(SELECT COUNT(*) FROM course_parts p WHERE p.course_id = c.id AND p.free_preview = 1) AS free_parts FROM courses c WHERE c.status IN ('published', 'soon') ORDER BY position, created_at"
        )
        out = [{k: r[k] for k in ("slug", "title", "subtitle", "level", "access", "status", "parts", "duration_s", "free_parts")} | {"access_label": ACCESS[r["access"]]} for r in rows]
        taken = {c["slug"] for c in out}
        for p in self.site.academy.get("planned", []):
            if p.get("slug") not in taken:
                acc = p.get("access", "academy_member")
                out.append({"slug": p["slug"], "title": p.get("title", ""), "subtitle": p.get("subtitle", ""), "level": p.get("level", ""), "access": acc, "access_label": ACCESS.get(acc, acc), "status": "soon", "parts": 0, "duration_s": 0, "free_parts": 0, "planned": True})
        return out

    def course(self, slug: str, entitlements: set[str], member_id: int | None) -> dict[str, Any] | None:
        rows = self.store.execute("SELECT * FROM courses WHERE slug = ? AND status IN ('published', 'soon')", (slug,))
        if not rows:
            return None
        c = dict(rows[0])
        unlocked = c["access"] in entitlements
        progress = {}
        if member_id is not None:
            progress = {r["part_id"]: dict(r) for r in self.store.execute("SELECT * FROM course_progress WHERE member_id = ?", (member_id,))}
        parts = []
        if c["status"] == "published":
            for p in self._parts(c["id"]):
                open_ = unlocked or bool(p["free_preview"])
                pr = progress.get(p["id"])
                parts.append({
                    "id": p["id"], "position": p["position"], "title": p["title"], "summary": p["summary"], "duration_s": p["duration_s"],
                    "free_preview": bool(p["free_preview"]), "locked": not open_, "chapters": json.loads(p["chapters"]) if open_ else [],
                    "player": player(p["provider"], p["video_ref"], self.settings.media_hosts) if open_ else None,
                    "progress": {"position_s": pr["position_s"], "completed": bool(pr["completed"])} if pr else None,
                })
        return {
            "slug": c["slug"], "title": c["title"], "subtitle": c["subtitle"], "description": c["description"], "level": c["level"], "status": c["status"],
            "access": c["access"], "access_label": ACCESS[c["access"]], "unlocked": unlocked, "parts": parts,
        }

    def save_progress(self, member_id: int, part_id: str, position_s: int, completed: bool, entitlements: set[str]) -> None:
        rows = self.store.execute("SELECT p.free_preview, p.duration_s, c.access, c.status FROM course_parts p JOIN courses c ON c.id = p.course_id WHERE p.id = ?", (part_id,))
        if not rows or rows[0]["status"] != "published" or not (rows[0]["free_preview"] or rows[0]["access"] in entitlements):
            raise AcademyError("partie introuvable")
        pos = max(0, min(int(position_s), rows[0]["duration_s"] or MAX_DURATION_S))
        self.store.execute(
            "INSERT INTO course_progress (member_id, part_id, position_s, completed, updated_at) VALUES (?, ?, ?, ?, ?) "
            "ON CONFLICT(member_id, part_id) DO UPDATE SET position_s = excluded.position_s, completed = MAX(completed, excluded.completed), updated_at = excluded.updated_at",
            (member_id, part_id, pos, int(completed), int(self.now())),
        )
