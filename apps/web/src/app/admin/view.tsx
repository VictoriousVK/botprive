"use client";

import { motion } from "framer-motion";
import { ArrowDown, ArrowUp, Check, CircleX, Plus, RefreshCw, Save, SquarePen, Trash } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Emblem } from "@/components/brand";
import { Notice, Spinner, Stat } from "@/components/ui";
import { api, ApiError, clock, dateFr, duration, fcfa, setCsrf, type Leader, type Me, type Payment } from "@/lib/api";

type Overview = {
  members: number; paying: Record<string, number>; to_review: number; revenue_30d_xof: number; leads: number; wave: string; copytrading: string;
  bots: { id: string; name: string; strategy: string }[];
  labels: { access: Record<string, string>; course_status: Record<string, string>; providers: Record<string, string>; leader_status: Record<string, string> };
  offers: { key: string; label: string; price_xof: number | null; category: string; period: string; purchasable: boolean }[];
};
type AdminPart = { id: string; position: number; title: string; summary: string; duration_s: number; provider: string; provider_label: string; video_ref: string; chapters: { t: number; title: string }[]; free_preview: number; player: { kind: string; src: string } | null };
type AdminCourse = { id: string; slug: string; title: string; subtitle: string; description: string; level: string; access: string; status: string; position: number; parts: AdminPart[] | number; duration_s?: number };

const TABS = [["overview", "Vue d'ensemble"], ["payments", "Paiements"], ["members", "Membres"], ["academy", "Académie"], ["copy", "Copytrading"], ["leads", "Prospects"], ["settings", "Réglages"]] as const;
type Tab = (typeof TABS)[number][0];
const op = <T,>(path: string, method = "GET", body?: unknown) => api<T>(path, { method, body, as: "operator" });

export function AdminView() {
  const [state, setState] = useState<"loading" | "out" | "in">("loading");
  const [user, setUser] = useState("");
  const [tab, setTab] = useState<Tab>("overview");
  const [ov, setOv] = useState<Overview | null>(null);

  const loadOv = useCallback(() => op<Overview>("/api/admin/overview").then(setOv).catch(() => {}), []);
  useEffect(() => {
    api<{ username: string; csrf: string }>("/api/auth/me", { as: "operator" })
      .then((r) => {
        setCsrf("operator", r.csrf);
        setUser(r.username);
        setState("in");
        loadOv();
      })
      .catch(() => setState("out"));
  }, [loadOv]);

  if (state === "loading") return <div className="container-x py-14"><Spinner /></div>;
  if (state === "out")
    return (
      <div className="container-x grid min-h-[60vh] place-items-center py-14">
        <div className="card max-w-md p-8 text-center">
          <Emblem size={56} className="mx-auto" />
          <h1 className="mt-5 font-[family-name:var(--font-display)] text-xl font-bold">Administration</h1>
          <p className="mt-2 text-sm text-muted">Réservée aux opérateurs. Connectez-vous d&apos;abord à la console (compte créé sur le serveur), puis revenez sur cette page.</p>
          <a href="/console" className="btn btn-primary mt-6">Ouvrir la console</a>
        </div>
      </div>
    );

  return (
    <div className="container-x py-10">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="eyebrow">Administration</p>
          <h1 className="h-section mt-2">Pilotage du site</h1>
        </div>
        <span className="chip">Opérateur : {user}</span>
      </div>
      <div className="scroll-x mt-6">
        <div className="flex w-max gap-1 rounded-2xl border border-white/10 bg-ink-900 p-1" role="tablist">
          {TABS.map(([k, label]) => (
            <button key={k} role="tab" aria-selected={tab === k} onClick={() => setTab(k)} className={`relative rounded-xl px-4 py-2 text-sm font-semibold ${tab === k ? "text-white" : "text-muted hover:text-white"}`}>
              {tab === k && <motion.span layoutId="admin-tab" className="absolute inset-0 rounded-xl bg-white/[0.07]" />}
              <span className="relative">
                {label}
                {k === "payments" && ov && ov.to_review > 0 && <span className="ml-1.5 rounded-full bg-gold-500 px-1.5 text-[10px] text-ink-950">{ov.to_review}</span>}
              </span>
            </button>
          ))}
        </div>
      </div>
      <div className="mt-8">
        {!ov ? <Spinner /> : tab === "overview" ? <OverviewTab ov={ov} /> : tab === "payments" ? <PaymentsTab onChange={loadOv} /> : tab === "members" ? <MembersTab ov={ov} /> : tab === "academy" ? <AcademyTab ov={ov} /> : tab === "copy" ? <CopyTab ov={ov} /> : tab === "leads" ? <LeadsTab /> : <SettingsTab />}
      </div>
    </div>
  );
}

function useAction() {
  const [err, setErr] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const run = async (fn: () => Promise<unknown>, success?: string) => {
    setErr(null);
    setOk(null);
    try {
      await fn();
      if (success) setOk(success);
      return true;
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : "Erreur");
      return false;
    }
  };
  const view = (
    <>
      {err && <Notice kind="error" className="mb-4">{err}</Notice>}
      {ok && <Notice kind="ok" className="mb-4">{ok}</Notice>}
    </>
  );
  return { run, view };
}

// ---------------- overview ----------------
function OverviewTab({ ov }: { ov: Overview }) {
  const paying = Object.values(ov.paying).reduce((a, b) => a + b, 0);
  return (
    <div className="grid gap-5">
      <div className="card grid grid-cols-2 gap-6 p-6 md:grid-cols-5">
        <Stat label="Membres" value={ov.members} />
        <Stat label="Abonnés actifs" value={paying} />
        <Stat label="Encaissé (30 j)" value={fcfa(ov.revenue_30d_xof)} />
        <Stat label="À vérifier" value={ov.to_review} tone={ov.to_review ? "text-gold-300" : ""} />
        <Stat label="Prospects" value={ov.leads} />
      </div>
      <div className="grid gap-4 md:grid-cols-2">
        <div className="card p-6 text-sm">
          <div className="font-semibold">Paiement Wave</div>
          <p className="mt-2 text-muted">
            {ov.wave === "api" ? "API Wave Checkout active : les paiements sont confirmés automatiquement." : "Mode manuel : les membres déclarent l'ID de transaction, vous validez dans l'onglet Paiements. Configurez LF_WAVE_API_KEY pour l'automatiser."}
          </p>
        </div>
        <div className="card p-6 text-sm">
          <div className="font-semibold">Copytrading</div>
          <p className="mt-2 text-muted">Mode : {ov.copytrading === "off" ? "fermé" : "démo (aucun ordre réel pour les membres)"}. La copie réelle attend l&apos;avis juridique.</p>
        </div>
      </div>
      <div className="card p-6">
        <div className="font-semibold">Accès actifs par offre</div>
        <div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
          {ov.offers.filter((o) => o.purchasable || ov.paying[o.key]).map((o) => <Stat key={o.key} label={o.label} value={ov.paying[o.key] ?? 0} />)}
        </div>
      </div>
    </div>
  );
}

// ---------------- payments ----------------
function PaymentsTab({ onChange }: { onChange: () => void }) {
  const [status, setStatus] = useState("declared");
  const [rows, setRows] = useState<Payment[] | null>(null);
  const { run, view } = useAction();
  const load = useCallback(() => op<Payment[]>(`/api/admin/payments?status=${status}`).then(setRows), [status]);
  useEffect(() => {
    load();
  }, [load]);
  const act = async (p: Payment, what: "approve" | "reject") => {
    const reason = what === "reject" ? window.prompt("Motif du refus (visible dans le journal) :") : null;
    if (what === "reject" && !reason) return;
    if (await run(() => op(`/api/admin/payments/${p.id}/${what}`, "POST", what === "reject" ? { reason } : undefined), what === "approve" ? "Paiement validé, accès activé." : "Paiement refusé.")) {
      load();
      onChange();
    }
  };
  return (
    <div>
      {view}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        {[["declared", "À vérifier"], ["pending", "En attente"], ["succeeded", "Payés"], ["rejected", "Refusés"], ["", "Tous"]].map(([k, l]) => (
          <button key={k} className={`chip ${status === k ? "chip-blue" : ""}`} onClick={() => setStatus(k)}>{l}</button>
        ))}
        <button className="btn btn-ghost btn-sm ml-auto" onClick={load}><RefreshCw className="size-4" /></button>
      </div>
      <div className="card scroll-x">
        {!rows ? <div className="p-6"><Spinner /></div> : rows.length === 0 ? <p className="p-6 text-sm text-muted">Aucun paiement.</p> : (
          <table className="table min-w-[860px]">
            <thead><tr><th>Date</th><th>Membre</th><th>Offre</th><th>Montant</th><th>Moyen</th><th>Transaction</th><th>Statut</th><th /></tr></thead>
            <tbody>
              {rows.map((p) => (
                <tr key={p.id}>
                  <td className="num text-muted">{dateFr(p.created_at)}</td>
                  <td><div>{p.name}</div><div className="text-xs text-faint">{p.email}</div></td>
                  <td>{p.offer_label}{p.months ? ` · ${p.months} mois` : " · à vie"}</td>
                  <td className="num">{p.amount ? fcfa(p.amount) : "—"}</td>
                  <td>{p.method_label}</td>
                  <td className="num text-xs">{p.transaction_ref ?? "—"}<div className="text-faint">{p.id}</div></td>
                  <td><span className="chip">{p.status_label}</span>{p.note && <div className="mt-1 max-w-[14rem] text-xs text-faint">{p.note}</div>}</td>
                  <td className="text-right">
                    {p.method === "wave_manual" && (p.status === "declared" || p.status === "pending") && (
                      <div className="flex justify-end gap-2">
                        <button className="btn btn-primary btn-sm" onClick={() => act(p, "approve")}><Check className="size-4" /> Valider</button>
                        <button className="btn btn-danger btn-sm" onClick={() => act(p, "reject")}><CircleX className="size-4" /></button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      <p className="mt-3 text-xs text-faint">Avant de valider un transfert manuel, retrouvez la transaction (montant et ID) dans votre application Wave Business.</p>
    </div>
  );
}

// ---------------- members ----------------
function MembersTab({ ov }: { ov: Overview }) {
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<(Me & { status: string })[] | null>(null);
  const [grant, setGrant] = useState<{ id: number; offer: string; months: number; reason: string } | null>(null);
  const { run, view } = useAction();
  const load = useCallback(() => op<(Me & { status: string })[]>(`/api/admin/members?q=${encodeURIComponent(q)}`).then(setRows), [q]);
  useEffect(() => {
    const t = setTimeout(load, 250);
    return () => clearTimeout(t);
  }, [load]);
  return (
    <div>
      {view}
      <input className="input mb-4 max-w-sm" placeholder="Rechercher (nom, e-mail)" value={q} onChange={(e) => setQ(e.target.value)} />
      <div className="card scroll-x">
        {!rows ? <div className="p-6"><Spinner /></div> : (
          <table className="table min-w-[760px]">
            <thead><tr><th>Membre</th><th>Téléphone</th><th>Offre</th><th>Inscrit le</th><th>Statut</th><th /></tr></thead>
            <tbody>
              {rows.map((m) => (
                <tr key={m.id}>
                  <td><div>{m.name}</div><div className="text-xs text-faint">{m.email}</div></td>
                  <td className="num text-xs">{m.phone ?? "—"}</td>
                  <td>
                    {m.access.length === 0 ? <span className="text-muted">Compte gratuit</span> : m.access.map((a) => (
                      <div key={a.product}>{a.label} <span className="text-xs text-faint">{a.expires_at ? `jusqu'au ${dateFr(a.expires_at)}` : "à vie"}</span></div>
                    ))}
                  </td>
                  <td className="num text-muted">{dateFr(m.created_at)}</td>
                  <td><span className={`chip ${m.status === "active" ? "chip-green" : "chip-red"}`}>{m.status === "active" ? "Actif" : "Suspendu"}</span></td>
                  <td className="text-right">
                    <div className="flex justify-end gap-2">
                      <button className="btn btn-ghost btn-sm" onClick={() => setGrant({ id: m.id, offer: "pro_trader", months: 1, reason: "" })}>Attribuer</button>
                      <button className="btn btn-ghost btn-sm" onClick={() => run(() => op(`/api/admin/members/${m.id}/status`, "POST", { status: m.status === "active" ? "suspended" : "active" })).then(load)}>
                        {m.status === "active" ? "Suspendre" : "Réactiver"}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      {grant && (
        <div className="card mt-5 grid gap-4 p-6 md:grid-cols-4">
          <label className="field"><span>Offre</span>
            <select className="input" value={grant.offer} onChange={(e) => setGrant({ ...grant, offer: e.target.value })}>
              {ov.offers.map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}
            </select>
          </label>
          <label className="field"><span>Mois (0 = à vie)</span><input className="input" type="number" min={0} max={24} value={grant.months} onChange={(e) => setGrant({ ...grant, months: Number(e.target.value) })} /></label>
          <label className="field md:col-span-2"><span>Motif (journal)</span><input className="input" placeholder="bêta-testeur, cofondateur…" value={grant.reason} onChange={(e) => setGrant({ ...grant, reason: e.target.value })} /></label>
          <div className="flex gap-2 md:col-span-4">
            <button className="btn btn-primary btn-sm" onClick={async () => { if (await run(() => op(`/api/admin/members/${grant.id}/grant`, "POST", grant), "Accès attribué.")) { setGrant(null); load(); } }}>Attribuer l&apos;accès</button>
            <button className="btn btn-ghost btn-sm" onClick={() => setGrant(null)}>Annuler</button>
          </div>
        </div>
      )}
    </div>
  );
}

// ---------------- academy ----------------
const emptyCourse = { slug: "", title: "", subtitle: "", description: "", level: "", access: "academy_member", status: "draft", position: 0 };

function parseDuration(s: string): number {
  const t = s.trim();
  if (!t) return 0;
  if (/^\d+$/.test(t)) return Number(t) * 60; // minutes
  const parts = t.split(":").map(Number);
  if (parts.some((n) => Number.isNaN(n))) return NaN;
  return parts.reduce((acc, n) => acc * 60 + n, 0);
}

function AcademyTab({ ov }: { ov: Overview }) {
  const [list, setList] = useState<AdminCourse[] | null>(null);
  const [sel, setSel] = useState<AdminCourse | null>(null);
  const [form, setForm] = useState<typeof emptyCourse>(emptyCourse);
  const { run, view } = useAction();
  const load = useCallback(() => op<AdminCourse[]>("/api/admin/courses").then(setList), []);
  useEffect(() => {
    load();
  }, [load]);
  const open = async (id: string) => {
    const c = await op<AdminCourse>(`/api/admin/courses/${id}`);
    setSel(c);
    setForm({ slug: c.slug, title: c.title, subtitle: c.subtitle, description: c.description, level: c.level, access: c.access, status: c.status, position: c.position });
  };
  const saveCourse = async () => {
    let out: AdminCourse | null = null;
    if (await run(async () => { out = await op<AdminCourse>(sel ? `/api/admin/courses/${sel.id}` : "/api/admin/courses", sel ? "PUT" : "POST", form); }, "Cours enregistré.")) {
      setSel(out);
      load();
    }
  };
  const del = async () => {
    if (!sel || !window.confirm(`Supprimer « ${sel.title} » et toutes ses parties ?`)) return;
    if (await run(() => op(`/api/admin/courses/${sel.id}`, "DELETE"), "Cours supprimé.")) {
      setSel(null);
      setForm(emptyCourse);
      load();
    }
  };
  const set = (k: keyof typeof emptyCourse) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => setForm({ ...form, [k]: k === "position" ? Number(e.target.value) : e.target.value });

  return (
    <div className="grid gap-6 lg:grid-cols-[18rem_1fr]">
      <div className="grid h-fit gap-2">
        <button className="btn btn-primary btn-sm" onClick={() => { setSel(null); setForm(emptyCourse); }}><Plus className="size-4" /> Nouveau cours</button>
        {!list ? <Spinner /> : list.map((c) => (
          <button key={c.id} onClick={() => open(c.id)} className={`card p-3 text-left text-sm ${sel?.id === c.id ? "border-brand-400/50" : ""}`}>
            <div className="font-semibold">{c.title}</div>
            <div className="text-xs text-faint">{ov.labels.course_status[c.status]} · {typeof c.parts === "number" ? c.parts : c.parts.length} parties · {duration(c.duration_s ?? 0)}</div>
          </button>
        ))}
      </div>
      <div className="min-w-0">
        {view}
        <div className="card grid gap-4 p-6 md:grid-cols-2">
          <h2 className="font-semibold md:col-span-2">{sel ? "Modifier le cours" : "Nouveau cours"}</h2>
          <label className="field"><span>Titre</span><input className="input" value={form.title} onChange={set("title")} /></label>
          <label className="field"><span>Adresse (slug)</span><input className="input num" placeholder="methode-ict" value={form.slug} onChange={set("slug")} /></label>
          <label className="field md:col-span-2"><span>Sous-titre</span><input className="input" value={form.subtitle} onChange={set("subtitle")} /></label>
          <label className="field md:col-span-2"><span>Description</span><textarea className="input" value={form.description} onChange={set("description")} /></label>
          <label className="field"><span>Niveau</span><input className="input" placeholder="Débutant, Avancé…" value={form.level} onChange={set("level")} /></label>
          <label className="field"><span>Ordre d&apos;affichage</span><input className="input" type="number" min={0} value={form.position} onChange={set("position")} /></label>
          <label className="field"><span>Accès</span>
            <select className="input" value={form.access} onChange={set("access")}>{Object.entries(ov.labels.access).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
          </label>
          <label className="field"><span>Statut</span>
            <select className="input" value={form.status} onChange={set("status")}>{Object.entries(ov.labels.course_status).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
          </label>
          <div className="flex flex-wrap gap-2 md:col-span-2">
            <button className="btn btn-primary btn-sm" onClick={saveCourse}><Save className="size-4" /> Enregistrer</button>
            {sel && <button className="btn btn-danger btn-sm" onClick={del}><Trash className="size-4" /> Supprimer</button>}
          </div>
        </div>
        {sel && Array.isArray(sel.parts) && <PartsEditor course={sel} onChange={(c) => { setSel(c); load(); }} run={run} />}
      </div>
    </div>
  );
}

function PartsEditor({ course, onChange, run }: { course: AdminCourse; onChange: (c: AdminCourse) => void; run: (fn: () => Promise<unknown>, ok?: string) => Promise<boolean> }) {
  const parts = course.parts as AdminPart[];
  const blank = { title: "", summary: "", video: "", dur: "", chapters: "", free_preview: false };
  const [f, setF] = useState(blank);
  const [editing, setEditing] = useState<string | null>(null);
  const edit = (p: AdminPart) => {
    setEditing(p.id);
    setF({ title: p.title, summary: p.summary, video: p.player?.src ?? p.video_ref, dur: clock(p.duration_s), chapters: p.chapters.map((c) => `${clock(c.t)} ${c.title}`).join("\n"), free_preview: !!p.free_preview });
  };
  const save = async () => {
    const d = parseDuration(f.dur);
    if (Number.isNaN(d)) return run(async () => { throw new ApiError(400, "Durée illisible : 40:00, 1:05:30 ou un nombre de minutes."); });
    const body = { title: f.title, summary: f.summary, video: f.video, duration_s: d, chapters: f.chapters, free_preview: f.free_preview };
    let out: AdminCourse | null = null;
    const ok = await run(async () => {
      out = await op<AdminCourse>(editing ? `/api/admin/courses/${course.id}/parts/${editing}` : `/api/admin/courses/${course.id}/parts`, editing ? "PUT" : "POST", body);
    }, editing ? "Partie mise à jour." : "Partie ajoutée.");
    if (ok && out) {
      onChange(out);
      setF(blank);
      setEditing(null);
    }
  };
  const mutate = async (fn: () => Promise<AdminCourse>) => {
    let out: AdminCourse | null = null;
    if (await run(async () => { out = await fn(); }) && out) onChange(out);
  };
  return (
    <div className="mt-6 grid gap-4">
      <h2 className="font-semibold">Parties ({parts.length})</h2>
      {parts.map((p, i) => (
        <div key={p.id} className="card flex flex-wrap items-center gap-3 p-4">
          <span className="num w-8 text-faint">{p.position}.</span>
          <div className="min-w-0 flex-1">
            <div className="font-medium">{p.title}</div>
            <div className="text-xs text-faint">{p.provider_label} · {duration(p.duration_s)} · {p.chapters.length} chapitres{p.free_preview ? " · gratuite" : ""}</div>
          </div>
          <div className="flex gap-1">
            <button className="btn btn-ghost btn-sm" disabled={i === 0} onClick={() => mutate(() => op(`/api/admin/courses/${course.id}/parts/${p.id}/move`, "POST", { delta: -1 }))} aria-label="Monter"><ArrowUp className="size-4" /></button>
            <button className="btn btn-ghost btn-sm" disabled={i === parts.length - 1} onClick={() => mutate(() => op(`/api/admin/courses/${course.id}/parts/${p.id}/move`, "POST", { delta: 1 }))} aria-label="Descendre"><ArrowDown className="size-4" /></button>
            <button className="btn btn-ghost btn-sm" onClick={() => edit(p)} aria-label="Modifier"><SquarePen className="size-4" /></button>
            <button className="btn btn-danger btn-sm" onClick={() => window.confirm(`Supprimer « ${p.title} » ?`) && mutate(() => op(`/api/admin/courses/${course.id}/parts/${p.id}`, "DELETE"))} aria-label="Supprimer"><Trash className="size-4" /></button>
          </div>
        </div>
      ))}
      <div className="card grid gap-4 p-6 md:grid-cols-2">
        <h3 className="font-semibold md:col-span-2">{editing ? "Modifier la partie" : "Ajouter une partie"}</h3>
        <label className="field md:col-span-2"><span>Titre</span><input className="input" placeholder="Partie 1 : la liquidité" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} /></label>
        <label className="field md:col-span-2"><span>Lien de la vidéo (Bunny Stream, Cloudflare Stream, Mux, Vimeo, YouTube)</span><input className="input" placeholder="https://iframe.mediadelivery.net/embed/…" value={f.video} onChange={(e) => setF({ ...f, video: e.target.value })} /></label>
        <label className="field"><span>Durée (40:00 ou minutes)</span><input className="input num" value={f.dur} onChange={(e) => setF({ ...f, dur: e.target.value })} /></label>
        <label className="flex items-center gap-3 self-end pb-3 text-sm"><input type="checkbox" className="size-4 accent-brand-500" checked={f.free_preview} onChange={(e) => setF({ ...f, free_preview: e.target.checked })} /> Partie gratuite (aperçu)</label>
        <label className="field md:col-span-2"><span>Résumé</span><textarea className="input" value={f.summary} onChange={(e) => setF({ ...f, summary: e.target.value })} /></label>
        <label className="field md:col-span-2"><span>Chapitres (un par ligne : 12:30 Titre)</span><textarea className="input num" placeholder={"0:00 Introduction\n12:30 Le Silver Bullet"} value={f.chapters} onChange={(e) => setF({ ...f, chapters: e.target.value })} /></label>
        <div className="flex gap-2 md:col-span-2">
          <button className="btn btn-primary btn-sm" onClick={save}><Save className="size-4" /> {editing ? "Enregistrer" : "Ajouter la partie"}</button>
          {editing && <button className="btn btn-ghost btn-sm" onClick={() => { setEditing(null); setF(blank); }}>Annuler</button>}
        </div>
      </div>
    </div>
  );
}

// ---------------- copytrading ----------------
const emptyLeader = { name: "", trader: "", bio: "", style: "", bot_id: "", risk_level: 3, ref_capital: 10000, status: "draft" };

function CopyTab({ ov }: { ov: Overview }) {
  const [rows, setRows] = useState<Leader[] | null>(null);
  const [id, setId] = useState<string | null>(null);
  const [f, setF] = useState(emptyLeader);
  const { run, view } = useAction();
  const load = useCallback(() => op<Leader[]>("/api/admin/leaders").then(setRows), []);
  useEffect(() => {
    load();
  }, [load]);
  const save = async () => {
    if (await run(() => op(id ? `/api/admin/leaders/${id}` : "/api/admin/leaders", id ? "PUT" : "POST", { ...f, bot_id: f.bot_id || null }), "Stratégie enregistrée.")) {
      setId(null);
      setF(emptyLeader);
      load();
    }
  };
  return (
    <div className="grid gap-6">
      {view}
      <div className="card scroll-x">
        {!rows ? <div className="p-6"><Spinner /></div> : rows.length === 0 ? <p className="p-6 text-sm text-muted">Aucune stratégie. Créez-en une et reliez-la à un bot de la console.</p> : (
          <table className="table min-w-[720px]">
            <thead><tr><th>Stratégie</th><th>Bot</th><th>Statut</th><th>Copieurs</th><th>Source</th><th /></tr></thead>
            <tbody>
              {rows.map((l) => (
                <tr key={l.id}>
                  <td><div className="font-medium">{l.name}</div><div className="text-xs text-faint">{l.trader}</div></td>
                  <td className="text-xs">{ov.bots.find((b) => b.id === l.bot_id)?.name ?? "—"}</td>
                  <td><span className="chip">{l.status_label}</span></td>
                  <td className="num">{l.followers}</td>
                  <td className="text-xs text-muted">{l.record.source_label}</td>
                  <td className="text-right"><button className="btn btn-ghost btn-sm" onClick={() => { setId(l.id); setF({ name: l.name, trader: l.trader, bio: l.bio, style: l.style, bot_id: l.bot_id ?? "", risk_level: l.risk_level, ref_capital: l.ref_capital, status: l.status }); }}><SquarePen className="size-4" /></button></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
      <div className="card grid gap-4 p-6 md:grid-cols-2">
        <h2 className="font-semibold md:col-span-2">{id ? "Modifier la stratégie" : "Nouvelle stratégie à copier"}</h2>
        <label className="field"><span>Nom</span><input className="input" placeholder="Or intraday ICT" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} /></label>
        <label className="field"><span>Trader</span><input className="input" placeholder="Khalifa Diop" value={f.trader} onChange={(e) => setF({ ...f, trader: e.target.value })} /></label>
        <label className="field"><span>Bot de la console (source des résultats)</span>
          <select className="input" value={f.bot_id} onChange={(e) => setF({ ...f, bot_id: e.target.value })}>
            <option value="">— aucun —</option>
            {ov.bots.map((b) => <option key={b.id} value={b.id}>{b.name} ({b.strategy})</option>)}
          </select>
        </label>
        <label className="field"><span>Capital de référence (USD)</span><input className="input num" type="number" min={100} value={f.ref_capital} onChange={(e) => setF({ ...f, ref_capital: Number(e.target.value) })} /></label>
        <label className="field"><span>Niveau de risque (1 à 5)</span><input className="input" type="number" min={1} max={5} value={f.risk_level} onChange={(e) => setF({ ...f, risk_level: Number(e.target.value) })} /></label>
        <label className="field"><span>Statut</span>
          <select className="input" value={f.status} onChange={(e) => setF({ ...f, status: e.target.value })}>{Object.entries(ov.labels.leader_status).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        </label>
        <label className="field md:col-span-2"><span>Style (court)</span><input className="input" placeholder="Intraday, or, sessions de Londres et New York" value={f.style} onChange={(e) => setF({ ...f, style: e.target.value })} /></label>
        <label className="field md:col-span-2"><span>Présentation</span><textarea className="input" value={f.bio} onChange={(e) => setF({ ...f, bio: e.target.value })} /></label>
        <div className="flex gap-2 md:col-span-2">
          <button className="btn btn-primary btn-sm" onClick={save}><Save className="size-4" /> Enregistrer</button>
          {id && <button className="btn btn-ghost btn-sm" onClick={() => { setId(null); setF(emptyLeader); }}>Annuler</button>}
        </div>
      </div>
    </div>
  );
}

// ---------------- settings ----------------
function SettingsTab() {
  const [f, setF] = useState<{ telegram_url: string; discord_url: string; env_telegram?: boolean; env_discord?: boolean } | null>(null);
  const { run, view } = useAction();
  useEffect(() => {
    op<{ telegram_url: string; discord_url: string; env_telegram: boolean; env_discord: boolean }>("/api/admin/settings").then(setF);
  }, []);
  if (!f) return <Spinner />;
  const save = () => run(async () => setF(await op("/api/admin/settings", "PUT", { telegram_url: f.telegram_url, discord_url: f.discord_url })), "Réglages enregistrés.");
  return (
    <div className="max-w-2xl">
      {view}
      <div className="card grid gap-4 p-6">
        <h2 className="font-semibold">Liens de la communauté privée</h2>
        <p className="text-sm text-muted">
          Montrés uniquement aux membres qui y ont droit (Starter et plus, groupe Elite, acheteurs de la formation ICT), dans leur espace membre. Ils sont
          enregistrés sur votre serveur, jamais dans le code publié.
        </p>
        <label className="field"><span>Lien d&apos;invitation Telegram (https://t.me/…)</span><input className="input" value={f.telegram_url} onChange={(e) => setF({ ...f, telegram_url: e.target.value })} /></label>
        <label className="field"><span>Lien d&apos;invitation Discord (https://discord.gg/…)</span><input className="input" value={f.discord_url} onChange={(e) => setF({ ...f, discord_url: e.target.value })} /></label>
        <div><button className="btn btn-primary btn-sm" onClick={save}><Save className="size-4" /> Enregistrer</button></div>
      </div>
    </div>
  );
}

// ---------------- leads ----------------
function LeadsTab() {
  const [rows, setRows] = useState<{ email: string; interest: string; created_at: number }[] | null>(null);
  useEffect(() => {
    op<{ email: string; interest: string; created_at: number }[]>("/api/admin/leads").then(setRows);
  }, []);
  const label: Record<string, string> = { copytrading: "Copytrading", next_bot: "Nouveau robot", academie: "Académie", newsletter: "Newsletter", formation: "Formations", mentorat: "Mentorat", licence: "Licences EA" };
  return (
    <div className="card scroll-x">
      {!rows ? <div className="p-6"><Spinner /></div> : rows.length === 0 ? <p className="p-6 text-sm text-muted">Aucun prospect pour le moment.</p> : (
        <table className="table min-w-[520px]">
          <thead><tr><th>E-mail</th><th>Intérêt</th><th>Date</th></tr></thead>
          <tbody>{rows.map((r) => <tr key={`${r.email}-${r.interest}`}><td>{r.email}</td><td>{label[r.interest] ?? r.interest}</td><td className="num text-muted">{dateFr(r.created_at)}</td></tr>)}</tbody>
        </table>
      )}
    </div>
  );
}
