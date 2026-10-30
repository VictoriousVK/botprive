"use client";

import { AnimatePresence, motion } from "framer-motion";
import { ArrowUp, BookOpen, Bot, Lock, RotateCcw, TriangleAlert } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { Markdown } from "@/components/markdown";
import { Notice, Spinner } from "@/components/ui";
import { api, type CoachAnswer, type CoachState } from "@/lib/api";
import { useSession } from "@/lib/session";

type Turn = { role: "user" | "assistant"; content: string; sources?: CoachAnswer["sources"]; outOfBase?: boolean; error?: boolean };

const STARTERS = [
  "Quelle différence entre un order block et un breaker block ?",
  "Comment repérer un FVG et à quoi sert le consequent encroachment ?",
  "À quelle heure GMT est le Silver Bullet de 10 h cet hiver ?",
  "Comment déterminer mon biais journalier sur l'or ?",
];

export function CoachView() {
  const { me, ready, site } = useSession();
  const [state, setState] = useState<CoachState | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!me) return;
    api<CoachState>("/api/m/coach").then(setState).catch((e) => setErr(e instanceof Error ? e.message : "Erreur"));
  }, [me]);

  if (!ready) return <div className="container-x py-14"><Spinner /></div>;

  return (
    <div className="container-x py-10 sm:py-14">
      <header className="max-w-3xl">
        <p className="eyebrow">Coach IA · ICT</p>
        <h1 className="h-section mt-2">Posez votre question. La réponse cite ses sources.</h1>
        <p className="mt-3 text-muted">
          Order blocks, FVG, liquidité, structure, killzones, Silver Bullet… Le coach répond à partir de la base de référence de la formation Victorious Trader, et vous dit quand une question en sort.
        </p>
      </header>
      <div className="mt-8">
        {!me ? (
          <Gate icon={<Lock className="size-6" />} title="Réservé aux membres">
            Connectez-vous pour utiliser le coach.
            <div className="mt-5 flex flex-wrap justify-center gap-2">
              <Link href="/compte/?vue=connexion" className="btn btn-primary btn-sm">Connexion</Link>
              <Link href="/compte/?vue=inscription" className="btn btn-ghost btn-sm">Créer un compte</Link>
            </div>
          </Gate>
        ) : err ? (
          <Notice kind="error">{err}</Notice>
        ) : !state ? (
          <Spinner />
        ) : !state.enabled || !site?.coach ? (
          <Gate icon={<Bot className="size-6" />} title="Bientôt disponible">Le coach IA est en cours d&apos;activation. Revenez très vite.</Gate>
        ) : !state.entitled ? (
          <Gate icon={<Lock className="size-6" />} title="Inclus dans l'offre Quant Elite">
            Le coach IA fait partie de l&apos;abonnement Quant Elite.
            <div className="mt-5"><Link href="/tarifs/" className="btn btn-primary btn-sm">Voir les offres</Link></div>
          </Gate>
        ) : (
          <Chat state={state} />
        )}
      </div>
    </div>
  );
}

function Gate({ icon, title, children }: { icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <div className="card mx-auto grid max-w-lg place-items-center px-6 py-12 text-center">
      <div className="grid size-12 place-items-center rounded-2xl bg-brand-500/15 text-brand-300">{icon}</div>
      <div className="mt-4 font-[family-name:var(--font-display)] text-lg font-bold">{title}</div>
      <div className="mt-2 max-w-sm text-sm text-muted">{children}</div>
    </div>
  );
}

function Chat({ state }: { state: CoachState }) {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [q, setQ] = useState("");
  const [busy, setBusy] = useState(false);
  const [remaining, setRemaining] = useState(state.remaining);
  const end = useRef<HTMLDivElement>(null);
  const input = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    end.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [turns, busy]);

  const ask = async (question: string) => {
    const text = question.trim();
    if (text.length < 3 || busy) return;
    const history = turns.filter((t) => !t.error).map(({ role, content }) => ({ role, content })).slice(-8);
    setTurns((t) => [...t, { role: "user", content: text }]);
    setQ("");
    setBusy(true);
    try {
      const r = await api<CoachAnswer>("/api/m/coach", { method: "POST", body: { question: text, history } });
      setTurns((t) => [...t, { role: "assistant", content: r.answer, sources: r.sources, outOfBase: r.out_of_base }]);
      setRemaining(r.remaining);
    } catch (e) {
      setTurns((t) => [...t, { role: "assistant", content: e instanceof Error ? e.message : "Erreur", error: true }]);
    } finally {
      setBusy(false);
      input.current?.focus();
    }
  };

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_17rem]">
      <section className="card flex min-h-[60vh] flex-col overflow-hidden" aria-label="Conversation avec le coach">
        <div className="flex items-center justify-between gap-3 border-b border-white/5 px-5 py-3 text-xs text-muted">
          <span className="inline-flex items-center gap-2"><span className="size-1.5 rounded-full bg-up-400 animate-pulse-dot" aria-hidden /> Coach ICT</span>
          <span className="num">{remaining} / {state.limit} questions aujourd&apos;hui</span>
        </div>
        <div className="flex-1 space-y-5 overflow-y-auto px-5 py-6" aria-live="polite">
          {turns.length === 0 && (
            <div>
              <p className="text-sm text-muted">Pour commencer, essayez :</p>
              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                {STARTERS.map((s) => (
                  <button key={s} onClick={() => ask(s)} className="rounded-xl border border-white/10 bg-white/[0.02] px-4 py-3 text-left text-sm text-fg/90 transition-colors hover:border-brand-400/40 hover:bg-brand-400/5">{s}</button>
                ))}
              </div>
            </div>
          )}
          <AnimatePresence initial={false}>
            {turns.map((t, i) => (
              <motion.div key={i} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25 }} className={t.role === "user" ? "flex justify-end" : ""}>
                {t.role === "user" ? (
                  <div className="max-w-[85%] rounded-2xl rounded-br-md bg-brand-600/30 px-4 py-2.5 text-[0.94rem] text-white">{t.content}</div>
                ) : t.error ? (
                  <Notice kind="error">{t.content}</Notice>
                ) : (
                  <div className="max-w-[95%]">
                    <Markdown text={t.content} />
                    <div className="mt-3 flex flex-wrap items-center gap-1.5">
                      {t.outOfBase && <span className="chip chip-gold"><TriangleAlert className="size-3" /> Hors base de référence</span>}
                      {t.sources?.map((s) => <span key={s.id} className="chip"><BookOpen className="size-3" /> {s.title}</span>)}
                    </div>
                  </div>
                )}
              </motion.div>
            ))}
          </AnimatePresence>
          {busy && <Spinner label="Le coach consulte la base…" />}
          <div ref={end} />
        </div>
        <form
          className="border-t border-white/5 p-3"
          onSubmit={(e) => {
            e.preventDefault();
            ask(q);
          }}
        >
          <div className="flex items-end gap-2 rounded-xl border border-white/10 bg-ink-950 p-2 focus-within:border-brand-400/50">
            <label htmlFor="coach-q" className="sr-only">Votre question</label>
            <textarea
              id="coach-q"
              ref={input}
              rows={2}
              maxLength={2000}
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  ask(q);
                }
              }}
              placeholder="Ex. : comment valider un MSS sur le M5 ?"
              className="min-h-[2.75rem] flex-1 resize-none bg-transparent px-2 py-1.5 text-[0.94rem] outline-none placeholder:text-faint"
              disabled={remaining <= 0}
            />
            <button className="btn btn-primary btn-sm !px-3" disabled={busy || q.trim().length < 3 || remaining <= 0} aria-label="Envoyer">
              <ArrowUp className="size-4" />
            </button>
          </div>
          <div className="mt-2 flex flex-wrap items-center justify-between gap-2 px-1 text-[11px] text-faint">
            <span>Pédagogique uniquement : aucun signal ni conseil en investissement.</span>
            {turns.length > 0 && <button type="button" className="inline-flex items-center gap-1 hover:text-white" onClick={() => setTurns([])}><RotateCcw className="size-3" /> Nouvelle conversation</button>}
          </div>
        </form>
      </section>
      <aside className="card h-fit p-5">
        <div className="text-xs font-semibold uppercase tracking-wider text-faint">Base de référence</div>
        <ul className="mt-3 grid gap-1 text-sm">
          {state.topics.map((t) => (
            <li key={t.id}>
              <button className="w-full rounded-lg px-2 py-1.5 text-left text-muted transition-colors hover:bg-white/5 hover:text-white" onClick={() => ask(`Explique-moi simplement : ${t.title}`)} disabled={busy || remaining <= 0}>
                {t.title}
              </button>
            </li>
          ))}
        </ul>
      </aside>
    </div>
  );
}
