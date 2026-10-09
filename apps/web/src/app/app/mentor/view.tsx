"use client";

import { BookMarked, GraduationCap, History } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { AppShell, Usage } from "@/components/app-shell";
import { Disclaimer, LabelChip, Section, useAction, useLoad } from "@/components/app-ui";
import { Notice } from "@/components/ui";
import { appApi, when, type MentorAnswer } from "@/lib/app";

const MENTOR_LABEL: Record<string, [string, string]> = {
  ANSWERED: ["Réponse sourcée", "chip-green"], PARTIAL: ["Réponse partielle", "chip-gold"], OUT_OF_CORPUS: ["Hors des contenus", ""], REFUSED_ADVICE: ["Pas de conseil personnalisé", "chip-red"],
};
const fmtTs = (s: number) => `${Math.floor(s / 60)} min ${String(s % 60).padStart(2, "0")} s`;

export function MentorView() {
  return (
    <AppShell title="Mentor IA" subtitle="Questions de cours, réponses tirées des contenus de la formation, avec leurs sources" feature="mentor">
      <Mentor />
    </AppShell>
  );
}

function Mentor() {
  const [q, setQ] = useState("");
  const [answer, setAnswer] = useState<(MentorAnswer & { question?: string }) | null>(null);
  const history = useLoad<{ id: string; created_at: number; output: MentorAnswer | null }[]>("/api/app/mentor/history");
  const { busy, run, note } = useAction();
  const ask = async () => {
    const out = await run(() => appApi<MentorAnswer>("/api/app/mentor/ask", "POST", { question: q }));
    if (out) { setAnswer({ ...out, question: q }); history.reload(); }
  };
  return (
    <div className="grid gap-5 lg:grid-cols-3">
      <div className="grid content-start gap-5 lg:col-span-2">
        <Section title="Votre question" icon={<GraduationCap className="size-4" />} actions={<Usage k="mentor" label="Questions" />}>
          <form onSubmit={(e) => { e.preventDefault(); if (q.trim().length >= 3) ask(); }} className="grid gap-3">
            <textarea className="input min-h-24" maxLength={1000} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Ex. : quelle différence entre un MSS et un CHoCH ? Comment repérer un Silver Bullet valide ?" />
            <div className="flex flex-wrap items-center gap-3">
              <button className="btn btn-primary btn-sm" disabled={busy || q.trim().length < 3}>{busy ? "Recherche…" : "Demander"}</button>
              <span className="text-xs text-faint">Le Mentor répond à partir des contenus de la formation uniquement ; il ne donne pas de signaux ni de conseil personnalisé.</span>
            </div>
          </form>
          {note}
        </Section>
        {answer && <Answer a={answer} />}
      </div>
      <Section title="Questions précédentes" icon={<History className="size-4" />}>
        {history.data?.length ? (
          <ul className="grid gap-1.5 text-sm">
            {history.data.filter((h) => h.output).map((h) => (
              <li key={h.id}>
                <button className="flex w-full flex-col gap-1 rounded-lg px-2 py-1.5 text-left hover:bg-white/[0.04]" onClick={() => setAnswer(h.output!)}>
                  <span className="line-clamp-2 text-fg/85">{h.output!.summary}</span>
                  <span className="text-xs text-faint">{when(h.created_at)}</span>
                </button>
              </li>
            ))}
          </ul>
        ) : <p className="text-sm text-muted">Aucune question.</p>}
      </Section>
    </div>
  );
}

function Answer({ a }: { a: MentorAnswer & { question?: string } }) {
  return (
    <Section title="Réponse" icon={<BookMarked className="size-4" />} actions={<LabelChip map={MENTOR_LABEL} k={a.label} />}>
      {a.question && <p className="mb-3 text-sm italic text-muted">« {a.question} »</p>}
      <p className="whitespace-pre-line text-sm leading-relaxed text-fg/90">{a.summary}</p>
      {a.exercise && (
        <Notice kind="info" className="mt-4"><span className="font-semibold">Exercice : </span>{a.exercise}</Notice>
      )}
      {a.citations.length > 0 && (
        <div className="mt-4">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Sources</h3>
          <ul className="grid gap-1 text-sm">
            {a.citations.map((c) => (
              <li key={c.chunk_id} className="flex flex-wrap gap-2">
                {c.ref?.startsWith("course:")
                  ? <Link href={`/academie/cours/?c=${encodeURIComponent(c.ref.slice(7))}`} className="chip chip-blue hover:border-brand-400/60">{c.title}</Link>
                  : <span className="chip chip-blue">{c.title}</span>}
                {c.ref && !c.ref.startsWith("course:") && !c.ref.startsWith("skill:") && <span className="text-muted">{c.ref}</span>}
                {c.timestamp_s != null && <span className="text-muted">à {fmtTs(c.timestamp_s)}</span>}
              </li>
            ))}
          </ul>
        </div>
      )}
      {a.caveats.length > 0 && <Notice kind="warn" className="mt-4">{a.caveats.join(" ")}</Notice>}
      <Disclaimer text={a.disclaimer} narratedBy={a.narrated_by} />
    </Section>
  );
}
