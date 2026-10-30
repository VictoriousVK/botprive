"use client";

import { Brain, History, Lightbulb, Sparkles, Trash2 } from "lucide-react";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { AppShell, Usage, useApp } from "@/components/app-shell";
import { Bullets, Disclaimer, LabelChip, RunSteps, Section, Seg, useAction, useLoad } from "@/components/app-ui";
import { Notice, Spinner, Stat } from "@/components/ui";
import { BEHAVIOR_LABEL, COACH_LABEL, appApi, pc, rr, tone, when, useRunStream, type Lesson, type Review } from "@/lib/app";

type ReviewRow = { id: string; status: string; created_at: number; label: string | null; error: string | null };
type Episode = { id: string; period: string; summary: string; trajectory: string; what_worked: string; what_didnt_work: string; key_points: string[]; created_at: number };
const LESSON_STATUS: Record<string, [string, string]> = { proposed: ["Proposée", "chip-blue"], accepted: ["Active", "chip-green"], edited: ["Active (modifiée)", "chip-green"], rejected: ["Refusée", ""], retired: ["Retirée", ""] };

export function ReviewView() {
  return (
    <AppShell title="Coach IA" subtitle="Revue de votre journal : chiffres calculés sur vos trades, leçons validées par vous" feature="coach">
      <Coach />
    </AppShell>
  );
}

function Coach() {
  const { app, reload: reloadApp } = useApp();
  const params = useSearchParams();
  const [days, setDays] = useState("7");
  const [question, setQuestion] = useState("");
  const [trace, setTrace] = useState<string | null>(null);
  const [current, setCurrent] = useState<string | null>(params.get("id"));
  const [review, setReview] = useState<Review | null>(null);
  const history = useLoad<ReviewRow[]>("/api/app/coach/reviews");
  const lessons = useLoad<Lesson[]>("/api/app/lessons");
  const { busy, run, note } = useAction();

  const load = useCallback(async (id: string) => {
    const r = await appApi<Review>(`/api/app/coach/reviews/${id}`).catch(() => null);
    setReview(r);
  }, []);
  useEffect(() => {
    if (current) load(current);
  }, [current, load]);

  const { steps, status } = useRunStream(trace, () => {
    if (trace) {
      setCurrent(trace);
      load(trace);
    }
    history.reload();
    lessons.reload();
    reloadApp();
  });

  const start = async () => {
    const out = await run(() => appApi<{ trace_id: string }>("/api/app/coach/review", "POST", { days: Number(days), question: question.trim() || null }));
    if (out) {
      setReview(null);
      setCurrent(null);
      setTrace(out.trace_id);
    }
  };

  const refresh = () => {
    if (current) load(current);
    lessons.reload();
  };

  return (
    <div className="grid gap-5 lg:grid-cols-3">
      <div className="grid content-start gap-5 lg:col-span-2">
        <Section title="Nouvelle revue" icon={<Sparkles className="size-4" />} actions={<Usage k="coach" label="Revues" />}>
          <div className="grid gap-3">
            <div className="flex flex-wrap items-center gap-3">
              <span className="text-sm text-muted">Période</span>
              <Seg label="Période de la revue" value={days} onChange={setDays} options={[["7", "7 jours"], ["30", "30 jours"], ["90", "90 jours"]]} />
            </div>
            <label className="field">
              <span>Une question pour le Coach (facultatif)</span>
              <textarea className="input min-h-20" maxLength={1000} value={question} onChange={(e) => setQuestion(e.target.value)} placeholder="Ex. : pourquoi je perds surtout le vendredi ?" />
            </label>
            <div className="flex flex-wrap items-center gap-3">
              <button className="btn btn-primary btn-sm" disabled={busy || status === "running"} onClick={start}>Lancer la revue</button>
              {!app?.ai && <span className="text-xs text-faint">Aucun modèle configuré : la revue est rédigée par les règles, à partir des mêmes chiffres.</span>}
            </div>
            {note}
            <RunSteps steps={steps} status={status} />
          </div>
        </Section>
        {review ? <Verdict review={review} onChanged={refresh} /> : current && <Spinner />}
      </div>

      <div className="grid content-start gap-5">
        <Section title="Revues précédentes" icon={<History className="size-4" />}>
          {history.data?.length ? (
            <ul className="grid gap-1.5 text-sm">
              {history.data.map((r) => (
                <li key={r.id}>
                  <button className={`flex w-full flex-wrap items-center gap-2 rounded-lg px-2 py-1.5 text-left hover:bg-white/[0.04] ${current === r.id ? "bg-white/[0.06]" : ""}`} onClick={() => { setTrace(null); setCurrent(r.id); }}>
                    <span className="text-muted">{when(r.created_at)}</span>
                    {r.label ? <LabelChip map={COACH_LABEL} k={r.label} /> : <span className="chip">{r.status === "waiting" ? "leçons à valider" : r.status === "failed" ? "échec" : "en cours"}</span>}
                  </button>
                </li>
              ))}
            </ul>
          ) : <p className="text-sm text-muted">Aucune revue.</p>}
        </Section>
        <LessonsPanel lessons={lessons.data} reload={lessons.reload} />
        <Memory />
      </div>
    </div>
  );
}

function Verdict({ review, onChanged }: { review: Review; onChanged: () => void }) {
  const v = review.verdict;
  if (review.status === "failed") return <Notice kind="error">La revue a échoué : {review.error ?? "erreur inconnue"}.</Notice>;
  if (!v) return <Spinner label="Revue en cours…" />;
  const k = v.kpis;
  return (
    <Section title="Verdict du Coach" icon={<Brain className="size-4" />} actions={<><LabelChip map={COACH_LABEL} k={v.label} /><span className="chip" title="Confiance calculée par les règles (taille d'échantillon, couverture des R)">Confiance {v.confidence} %</span></>}>
      <div className="grid gap-5">
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <Stat label="Trades" value={k.n} />
          <Stat label="Réussite" value={pc(k.win_rate)} />
          <Stat label="Espérance" value={rr(k.expectancy_r)} tone={tone(k.expectancy_r)} />
          <Stat label="Pertes consécutives max" value={k.max_consecutive_losses} />
        </div>
        <p className="whitespace-pre-line text-sm leading-relaxed text-fg/90">{v.summary}</p>
        {v.flags.length > 0 && (
          <div>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Écarts mesurés</h3>
            <ul className="grid gap-2">
              {v.flags.map((f) => (
                <li key={f.kind} className="flex flex-wrap gap-2 text-sm"><span className="chip chip-gold">{BEHAVIOR_LABEL[f.kind] ?? f.kind}</span><span className="text-fg/85">{f.detail}</span></li>
              ))}
            </ul>
          </div>
        )}
        {v.lessons.length > 0 && (
          <div>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Leçons proposées</h3>
            <div className="grid gap-3">
              {v.lessons.map((l) => <LessonCard key={l.id} lesson={l} onChanged={onChanged} />)}
            </div>
            <p className="mt-2 text-xs text-faint">Rien n&apos;est mémorisé sans votre accord : acceptez, reformulez ou refusez chaque leçon. Cinq leçons actives au plus ; la plus ancienne non renforcée se retire.</p>
          </div>
        )}
        {v.reflection_questions.length > 0 && (
          <div>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">Questions pour votre prochaine séance</h3>
            <Bullets items={v.reflection_questions} />
          </div>
        )}
        {v.caveats.length > 0 && <Notice kind="warn"><Bullets items={v.caveats} /></Notice>}
        <Disclaimer text={v.disclaimer} narratedBy={v.narrated_by} />
      </div>
    </Section>
  );
}

function LessonCard({ lesson, onChanged }: { lesson: Lesson; onChanged: () => void }) {
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(lesson.text);
  const { busy, run, note } = useAction();
  const decide = async (decision: string, body?: string) => {
    if (await run(() => appApi(`/api/app/lessons/${lesson.id}`, "POST", { decision, text: body ?? null }))) {
      setEditing(false);
      onChanged();
    }
  };
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.02] p-4">
      <div className="mb-2 flex flex-wrap items-center gap-2">
        <Lightbulb className="size-4 text-gold-400" aria-hidden />
        <span className="chip">{BEHAVIOR_LABEL[lesson.behavior] ?? lesson.behavior}</span>
        <LabelChip map={LESSON_STATUS} k={lesson.status} />
      </div>
      {editing ? (
        <textarea className="input min-h-20 text-sm" maxLength={400} value={text} onChange={(e) => setText(e.target.value)} />
      ) : (
        <p className="text-sm leading-relaxed">{lesson.text}</p>
      )}
      {lesson.status === "proposed" && (
        <div className="mt-3 flex flex-wrap gap-2">
          {editing ? (
            <>
              <button className="btn btn-primary btn-sm" disabled={busy || text.trim().length < 10} onClick={() => decide("edit", text)}>Valider ma version</button>
              <button className="btn btn-ghost btn-sm" onClick={() => setEditing(false)}>Annuler</button>
            </>
          ) : (
            <>
              <button className="btn btn-primary btn-sm" disabled={busy} onClick={() => decide("accept")}>Accepter</button>
              <button className="btn btn-ghost btn-sm" disabled={busy} onClick={() => setEditing(true)}>Reformuler</button>
              <button className="btn btn-ghost btn-sm" disabled={busy} onClick={() => decide("reject")}>Refuser</button>
            </>
          )}
        </div>
      )}
      {note}
    </div>
  );
}

function LessonsPanel({ lessons, reload }: { lessons: Lesson[] | null; reload: () => void }) {
  const { busy, run } = useAction();
  const active = (lessons ?? []).filter((l) => l.status === "accepted" || l.status === "edited");
  return (
    <Section title="Leçons actives" icon={<Lightbulb className="size-4" />}>
      {active.length ? (
        <ul className="grid gap-2 text-sm">
          {active.map((l) => (
            <li key={l.id} className="rounded-lg border border-white/5 bg-white/[0.02] p-3">
              <p className="leading-relaxed">{l.text}</p>
              <div className="mt-2 flex items-center gap-2 text-xs text-faint">
                {l.effective_strength != null && <span title="Force de la leçon : elle décroît si le comportement ne se reproduit plus">force {Math.round(l.effective_strength * 100)} %</span>}
                <button className="ml-auto text-brand-300 hover:underline" disabled={busy} onClick={async () => { if (await run(() => appApi(`/api/app/lessons/${l.id}`, "POST", { decision: "retire" }))) reload(); }}>Retirer</button>
              </div>
            </li>
          ))}
        </ul>
      ) : <p className="text-sm text-muted">Aucune leçon active.</p>}
    </Section>
  );
}

function Memory() {
  const { data, reload } = useLoad<Episode[]>("/api/app/memory");
  const [edit, setEdit] = useState<string | null>(null);
  const [text, setText] = useState("");
  const { busy, run, note } = useAction();
  return (
    <Section title="Mémoire du Coach" icon={<Brain className="size-4" />}>
      <p className="mb-3 text-xs text-faint">Un résumé par semaine revue, relu par le Coach à la revue suivante. Vous pouvez le corriger ou le supprimer.</p>
      {data?.length ? (
        <ul className="grid gap-2 text-sm">
          {data.slice(0, 8).map((e) => (
            <li key={e.id} className="rounded-lg border border-white/5 bg-white/[0.02] p-3">
              <div className="mb-1 flex items-center gap-2 text-xs">
                <span className="chip">{e.period}</span>
                <button className="ml-auto text-brand-300 hover:underline" onClick={() => { setEdit(edit === e.id ? null : e.id); setText(e.summary); }}>{edit === e.id ? "Fermer" : "Corriger"}</button>
                <button className="text-faint hover:text-down-400" aria-label="Supprimer ce résumé" disabled={busy}
                  onClick={async () => { if (confirm("Supprimer ce résumé de la mémoire du Coach ?") && (await run(() => appApi(`/api/app/memory/${e.id}`, "DELETE")))) reload(); }}>
                  <Trash2 className="size-3.5" aria-hidden />
                </button>
              </div>
              {edit === e.id ? (
                <div className="grid gap-2">
                  <textarea className="input min-h-24 text-sm" maxLength={2000} value={text} onChange={(x) => setText(x.target.value)} />
                  <button className="btn btn-primary btn-sm justify-self-start" disabled={busy || !text.trim()} onClick={async () => { if (await run(() => appApi(`/api/app/memory/${e.id}`, "PUT", { summary: text }))) { setEdit(null); reload(); } }}>Enregistrer</button>
                </div>
              ) : <p className="line-clamp-4 leading-relaxed text-fg/85">{e.summary}</p>}
            </li>
          ))}
        </ul>
      ) : <p className="text-sm text-muted">Vide pour l&apos;instant.</p>}
      {note}
    </Section>
  );
}
